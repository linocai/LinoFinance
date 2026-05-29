"""Per-request authentication context attached by the auth middleware.

The middleware sets ``request.state.auth`` to one of:

- ``AuthContext(mode="admin", ...)`` when the legacy env admin token was used
  (ops / curl / deploy smoke); ``user`` and ``session`` are ``None``.
- ``AuthContext(mode="user", ...)`` when a DB-backed Apple session token was
  used; ``user`` and ``session`` are populated.

Routes read it via the ``get_auth_context`` dependency.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Optional

from fastapi import HTTPException, Request, status

if TYPE_CHECKING:
    from app.models.auth_session import AuthSession
    from app.models.user import User


@dataclass
class AuthContext:
    mode: str  # "admin" | "user"
    user: Optional["User"] = None
    session: Optional["AuthSession"] = None

    @property
    def is_admin(self) -> bool:
        return self.mode == "admin"

    @property
    def is_user(self) -> bool:
        return self.mode == "user"


def get_auth_context(request: Request) -> Optional[AuthContext]:
    """Return the AuthContext set by the middleware, or None if auth is off.

    Auth is off for local dev when ``LINOFINANCE_API_AUTH_TOKEN`` is unset and
    the environment is not production; in that case routes that need an auth
    context should treat the caller as an implicit admin.
    """
    return getattr(request.state, "auth", None)


def require_session(request: Request) -> "AuthSession":
    """Dependency: require a user (session-token) auth context.

    Raises 400 if the caller used the admin token, mirroring the plan's
    "Admin token cannot ..." errors.
    """
    auth = get_auth_context(request)
    if auth is None or auth.mode == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin token cannot use this endpoint",
        )
    if auth.session is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid API token",
        )
    return auth.session
