"""Identity / session service for Sign in with Apple (v1.2).

Bridges the verified Apple identity to the local ``users`` and
``auth_sessions`` tables and issues opaque session tokens. The plaintext
token is returned to the caller exactly once; only its SHA-256 hash is
stored.
"""
from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.config import get_settings
from app.models.auth_session import AuthSession
from app.models.user import User
from app.services.apple_identity import (
    AppleIdentity,
    AppleIdentityError,
    verify_apple_identity_token,
)


class AuthError(Exception):
    """Base error for the auth service."""


class InvalidAppleTokenError(AuthError):
    pass


class UserDisabledError(AuthError):
    pass


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _resolve_identity(identity_token: str) -> AppleIdentity:
    settings = get_settings()
    if settings.apple_dev_shortcut and not settings.is_production:
        # DEV SHORTCUT — DO NOT enable in production (guarded in
        # Settings.validate_runtime). Treats the token verbatim as the
        # Apple `sub`, skipping JWKS verification entirely so local /
        # curl development needs no real Apple flow.
        now = int(datetime.now(timezone.utc).timestamp())
        return AppleIdentity(
            sub=identity_token,
            email=None,
            email_verified=False,
            aud=(settings.apple_signin_audiences[0] if settings.apple_signin_audiences else ""),
            iss="dev-shortcut",
            iat=now,
            exp=now + 600,
            is_private_email=False,
        )
    try:
        return verify_apple_identity_token(
            identity_token, set(settings.apple_signin_audiences)
        )
    except AppleIdentityError as exc:
        raise InvalidAppleTokenError(str(exc)) from exc


def _upsert_user(
    db: Session,
    identity: AppleIdentity,
    first_name: Optional[str],
    last_name: Optional[str],
) -> User:
    user = db.execute(
        select(User).where(User.apple_user_id == identity.sub)
    ).scalar_one_or_none()

    if user is None:
        # Single-user gate (D1): the first user to ever sign in (empty users
        # table) bootstraps as active. After that, any new Apple `sub` is
        # recorded as disabled and refused a session — unless it is on the
        # allowlist (e.g. migrating to a new Apple ID). A disabled new user is
        # committed *before* raising so the row survives for ops to inspect /
        # activate; merely flushing would be rolled back when the exception
        # aborts the request's transaction.
        settings = get_settings()
        allowlisted = identity.sub in settings.apple_sub_allowlist_set
        users_exist = (
            db.execute(select(User.id).limit(1)).scalar_one_or_none() is not None
        )
        should_disable = users_exist and not allowlisted

        display_name = _build_display_name(first_name, last_name)
        user = User(
            apple_user_id=identity.sub,
            email=identity.email,
            email_verified=identity.email_verified,
            display_name=display_name,
            is_admin=False,
            disabled=should_disable,
        )
        db.add(user)
        if should_disable:
            db.commit()
            raise UserDisabledError("User is disabled")
        db.flush()
        return user

    if user.disabled:
        raise UserDisabledError("User is disabled")

    # Apple only returns email / name on the first sign-in; never overwrite an
    # existing value. Only allow email_verified to flip to True.
    if identity.email_verified and not user.email_verified:
        user.email_verified = True
    if user.display_name is None:
        candidate = _build_display_name(first_name, last_name)
        if candidate:
            user.display_name = candidate
    return user


def _build_display_name(first_name: Optional[str], last_name: Optional[str]) -> Optional[str]:
    parts = [p.strip() for p in (first_name, last_name) if p and p.strip()]
    return " ".join(parts) if parts else None


def sign_in_with_apple(
    db: Session,
    *,
    identity_token: str,
    device_label: str,
    platform: str,
    app_version: Optional[str],
    first_name: Optional[str],
    last_name: Optional[str],
) -> tuple[User, AuthSession, str]:
    """Verify the Apple token, upsert the user, mint a session.

    Returns ``(user, session, plaintext_token)``. The plaintext token is the
    only time it leaves the server.
    """
    identity = _resolve_identity(identity_token)

    # Reject a disabled user even before minting a session.
    existing = db.execute(
        select(User).where(User.apple_user_id == identity.sub)
    ).scalar_one_or_none()
    if existing is not None and existing.disabled:
        raise UserDisabledError("User is disabled")

    user = _upsert_user(db, identity, first_name, last_name)

    settings = get_settings()
    plaintext = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)
    session = AuthSession(
        user_id=user.id,
        token_hash=hash_token(plaintext),
        device_label=device_label,
        platform=platform,
        app_version=app_version,
        issued_at=now,
        last_seen_at=now,
        expires_at=now + timedelta(days=settings.session_lifetime_days),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    db.refresh(user)
    return user, session, plaintext


def get_session_for_token(db: Session, token: str) -> Optional[AuthSession]:
    """Return the active session for a plaintext token, or None.

    Active = not revoked and not expired.
    """
    token_hash = hash_token(token)
    session = db.execute(
        select(AuthSession)
        .options(selectinload(AuthSession.user))
        .where(AuthSession.token_hash == token_hash)
    ).scalar_one_or_none()
    if session is None:
        return None
    if session.revoked_at is not None:
        return None
    if _is_expired(session.expires_at):
        return None
    # Reject sessions belonging to a user that was disabled after the session
    # was issued (audit 1.2). The user is already eager-loaded via
    # selectinload, so this costs no extra query.
    if session.user is None or session.user.disabled:
        return None
    return session


def touch_session_last_seen(db: Session, session_id: str) -> None:
    session = db.get(AuthSession, session_id)
    if session is not None:
        session.last_seen_at = datetime.now(timezone.utc)
        db.commit()


def list_sessions(db: Session, user_id: str) -> list[AuthSession]:
    now = datetime.now(timezone.utc)
    sessions = db.execute(
        select(AuthSession)
        .where(AuthSession.user_id == user_id)
        .where(AuthSession.revoked_at.is_(None))
        .order_by(AuthSession.last_seen_at.desc())
    ).scalars().all()
    return [s for s in sessions if not _is_expired(s.expires_at, now)]


def revoke_session_by_id(db: Session, user_id: str, session_id: str) -> bool:
    """Revoke a session owned by ``user_id``. Returns False if not found."""
    session = db.get(AuthSession, session_id)
    if session is None or session.user_id != user_id or session.revoked_at is not None:
        return False
    session.revoked_at = datetime.now(timezone.utc)
    db.commit()
    return True


def _is_expired(expires_at: datetime, now: Optional[datetime] = None) -> bool:
    now = now or datetime.now(timezone.utc)
    if expires_at.tzinfo is None:
        # SQLite round-trips naive datetimes; assume UTC.
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at <= now
