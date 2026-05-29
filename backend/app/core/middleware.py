from __future__ import annotations

import hmac
import json
import logging
import time
from dataclasses import dataclass
from threading import Lock
from uuid import uuid4

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.auth_context import AuthContext
from app.core.config import Settings

LOGGER = logging.getLogger("linofinance.api")


def is_public_api_path(path: str, settings: Settings) -> bool:
    prefix = settings.api_v1_prefix.rstrip("/")
    public_paths = {
        f"{prefix}/health",
        f"{prefix}/openapi.json",
        f"{prefix}/docs",
        f"{prefix}/redoc",
        # Sign in with Apple is the bootstrap — there is no token yet.
        f"{prefix}/auth/apple",
    }
    if path in public_paths:
        return True
    return path.startswith(f"{prefix}/docs/")


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        started_at = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            LOGGER.exception(
                json.dumps(
                    {
                        "event": "api_request_error",
                        "request_id": request_id,
                        "method": request.method,
                        "path": request.url.path,
                        "client": _client_host(request),
                    },
                    ensure_ascii=False,
                )
            )
            raise

        duration_ms = round((time.perf_counter() - started_at) * 1000, 2)
        response.headers["x-request-id"] = request_id
        LOGGER.info(
            json.dumps(
                {
                    "event": "api_request",
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                    "client": _client_host(request),
                },
                ensure_ascii=False,
            )
        )
        return response


class APIAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, settings: Settings) -> None:
        super().__init__(app)
        self.settings = settings

    async def dispatch(self, request: Request, call_next) -> Response:
        if is_public_api_path(request.url.path, self.settings) or not self.settings.auth_required:
            return await call_next(request)

        actual_token = _extract_token(request)
        if actual_token is None:
            return _unauthorized()

        # Admin escape hatch — the env token still works for ops / curl /
        # deploy smoke and bypasses the users table entirely.
        if self.settings.api_auth_token and hmac.compare_digest(
            actual_token, self.settings.api_auth_token
        ):
            request.state.auth = AuthContext(mode="admin")
            return await call_next(request)

        # Session-token path — DB-backed Apple session.
        session = _resolve_session_token(request, actual_token)
        if session is None:
            return _unauthorized()

        request.state.auth = AuthContext(
            mode="user", user=session.user, session=session
        )
        return await call_next(request)


@dataclass
class _RateLimitWindow:
    started_at: float
    count: int


class _InMemoryRateLimiter:
    def __init__(self, limit_per_minute: int) -> None:
        self.limit_per_minute = limit_per_minute
        self._windows: dict[str, _RateLimitWindow] = {}
        self._lock = Lock()

    def hit(self, key: str, now: float) -> tuple[bool, int, int]:
        with self._lock:
            window = self._windows.get(key)
            if window is None or now - window.started_at >= 60:
                window = _RateLimitWindow(started_at=now, count=0)
                self._windows[key] = window

            window.count += 1
            retry_after = max(1, int(60 - (now - window.started_at)))
            remaining = max(0, self.limit_per_minute - window.count)
            return window.count <= self.limit_per_minute, retry_after, remaining


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, settings: Settings) -> None:
        super().__init__(app)
        self.settings = settings
        self.limiter = _InMemoryRateLimiter(settings.api_rate_limit_per_minute)

    async def dispatch(self, request: Request, call_next) -> Response:
        if is_public_api_path(request.url.path, self.settings) or not self.settings.rate_limit_active:
            return await call_next(request)

        key = _rate_limit_key(request, self.settings)
        allowed, retry_after, remaining = self.limiter.hit(key, time.monotonic())
        headers = {
            "X-RateLimit-Limit": str(self.settings.api_rate_limit_per_minute),
            "X-RateLimit-Remaining": str(remaining),
        }
        if not allowed:
            headers["Retry-After"] = str(retry_after)
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded"},
                headers=headers,
            )

        response = await call_next(request)
        response.headers.update(headers)
        return response


def _unauthorized() -> JSONResponse:
    return JSONResponse(
        status_code=401,
        content={"detail": "Missing or invalid API token"},
        headers={"WWW-Authenticate": "Bearer"},
    )


def _open_db_session(request: Request):
    """Open a DB session honouring the app's get_db dependency override.

    Tests override ``get_db`` with an in-memory SQLite factory via
    ``app.dependency_overrides``; the middleware runs outside the dependency
    system, so it resolves the same factory here. Falls back to the
    production ``SessionLocal``.
    """
    from app.db.session import SessionLocal, get_db

    override = request.app.dependency_overrides.get(get_db)
    if override is not None:
        gen = override()
        return next(gen), gen
    return SessionLocal(), None


def _resolve_session_token(request: Request, token: str):
    """Resolve an active session for the token, detached for post-request use.

    Returns None for any unresolvable token — including when the session store
    is unreachable — so a bad token always yields a clean 401 rather than a 500.
    """
    from app.services import auth as auth_service

    try:
        db, gen = _open_db_session(request)
    except Exception:
        LOGGER.exception("Failed to open session store for token auth")
        return None

    try:
        session = auth_service.get_session_for_token(db, token)
        if session is None:
            return None
        # Touch last_seen_at inline (single indexed update, < 1 ms). The commit
        # expires attributes; re-fetch with the user eager-loaded afterwards.
        auth_service.touch_session_last_seen(db, session.id)
        session = auth_service.get_session_for_token(db, token)
        if session is None:
            return None
        # Force-load relationship, then detach so attributes survive after the
        # session closes.
        _ = session.user
        db.expunge(session)
        if session.user is not None:
            db.expunge(session.user)
        return session
    except Exception:
        LOGGER.exception("Session token resolution failed")
        return None
    finally:
        if gen is not None:
            try:
                next(gen)
            except StopIteration:
                pass
        else:
            db.close()


def _extract_token(request: Request) -> str | None:
    authorization = request.headers.get("authorization")
    if authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() == "bearer" and token:
            return token.strip()
    token = request.headers.get("x-linofinance-api-token")
    if token:
        return token.strip()
    return None


def _rate_limit_key(request: Request, settings: Settings) -> str:
    if settings.trusted_proxy_headers:
        forwarded_for = request.headers.get("x-forwarded-for")
        if forwarded_for:
            return forwarded_for.split(",", maxsplit=1)[0].strip()
    return _client_host(request)


def _client_host(request: Request) -> str:
    if request.client is None:
        return "unknown"
    return request.client.host
