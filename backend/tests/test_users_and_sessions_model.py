"""Model-level tests for the v1.2 auth tables (P1)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, event, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app import models  # noqa: F401
from app.db.base import Base
from app.models.auth_session import AuthSession
from app.models.user import User


@pytest.fixture()
def session() -> Session:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # SQLite ignores ON DELETE CASCADE unless foreign_keys pragma is on;
    # enable it so the cascade behaviour matches the production Postgres.
    @event.listens_for(engine, "connect")
    def _enable_sqlite_fk(dbapi_connection, _record):  # noqa: ANN001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    Base.metadata.create_all(bind=engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db = factory()
    try:
        yield db
    finally:
        db.close()


def _make_session(user_id: str, token_hash: str) -> AuthSession:
    now = datetime.now(timezone.utc)
    return AuthSession(
        user_id=user_id,
        token_hash=token_hash,
        device_label="iPhone Air · iOS 18.4",
        platform="ios",
        app_version="1.2.0",
        issued_at=now,
        last_seen_at=now,
        expires_at=now + timedelta(days=365),
    )


def test_create_user_minimal(session: Session) -> None:
    user = User(apple_user_id="apple-sub-1")
    session.add(user)
    session.commit()

    loaded = session.execute(
        select(User).where(User.apple_user_id == "apple-sub-1")
    ).scalar_one()
    assert loaded.email is None
    assert loaded.email_verified is False
    assert loaded.is_admin is False
    assert loaded.disabled is False
    assert loaded.id


def test_create_session_default_expires_in_365d(session: Session) -> None:
    user = User(apple_user_id="apple-sub-2")
    session.add(user)
    session.commit()

    issued = datetime.now(timezone.utc)
    auth_session = AuthSession(
        user_id=user.id,
        token_hash="hash-2",
        device_label="local",
        platform="macos",
        issued_at=issued,
        last_seen_at=issued,
        expires_at=issued + timedelta(days=365),
    )
    session.add(auth_session)
    session.commit()

    delta = auth_session.expires_at - auth_session.issued_at
    assert abs(delta - timedelta(days=365)) <= timedelta(seconds=1)


def test_user_cascade_delete_sessions(session: Session) -> None:
    user = User(apple_user_id="apple-sub-3")
    session.add(user)
    session.commit()
    session.add(_make_session(user.id, "hash-3a"))
    session.add(_make_session(user.id, "hash-3b"))
    session.commit()

    assert session.execute(select(AuthSession)).scalars().all()

    session.delete(user)
    session.commit()

    assert session.execute(select(AuthSession)).scalars().all() == []


def test_apple_user_id_unique(session: Session) -> None:
    session.add(User(apple_user_id="dup-sub"))
    session.commit()

    session.add(User(apple_user_id="dup-sub"))
    with pytest.raises(IntegrityError):
        session.commit()
    session.rollback()
