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

from app.core.config import Settings

LOGGER = logging.getLogger("linofinance.api")


def is_public_api_path(path: str, settings: Settings) -> bool:
    prefix = settings.api_v1_prefix.rstrip("/")
    public_paths = {
        f"{prefix}/health",
        f"{prefix}/openapi.json",
        f"{prefix}/docs",
        f"{prefix}/redoc",
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

        expected_token = self.settings.api_auth_token or ""
        actual_token = _extract_token(request)
        if actual_token is None or not hmac.compare_digest(actual_token, expected_token):
            return JSONResponse(
                status_code=401,
                content={"detail": "Missing or invalid API token"},
                headers={"WWW-Authenticate": "Bearer"},
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
