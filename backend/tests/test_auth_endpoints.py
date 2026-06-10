"""Auth endpoints + middleware behaviour (P3).

These tests force ``auth_required`` on by setting the env admin token, then
exercise both the admin escape hatch and the DB-backed session path. The
Apple identity layer is short-circuited with ``LINOFINANCE_APPLE_DEV_SHORTCUT``
so the tests need no real Apple flow.
"""

from __future__ import annotations

from collections.abc import Generator
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app import models  # noqa: F401
from app.core.config import get_settings
from app.db.base import Base
from app.db.session import get_db
from app.main import create_app
from app.models.auth_session import AuthSession
from app.models.user import User

ADMIN_TOKEN = "admintest"


@pytest.fixture()
def db_factory() -> sessionmaker:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


@pytest.fixture()
def client(db_factory, monkeypatch) -> Generator[TestClient, None, None]:
    monkeypatch.setenv("LINOFINANCE_API_AUTH_TOKEN", ADMIN_TOKEN)
    monkeypatch.setenv("LINOFINANCE_APPLE_DEV_SHORTCUT", "true")
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    get_settings.cache_clear()

    def override_get_db() -> Generator[Session, None, None]:
        db = db_factory()
        try:
            yield db
        finally:
            db.close()

    app = create_app()
    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    get_settings.cache_clear()


def _sign_in(client, *, sub="apple-sub-1", device_label="iPhone Air", platform="ios"):
    response = client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": sub,
            "device_label": device_label,
            "platform": platform,
            "app_version": "1.2.0",
        },
    )
    return response


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_sign_in_with_apple_creates_user(client, db_factory) -> None:
    response = _sign_in(client)
    assert response.status_code == 200, response.json()
    body = response.json()
    token = body["session_token"]
    assert token
    assert body["user"]["apple_user_id"] == "apple-sub-1"
    assert body["user"]["is_admin"] is False

    me = client.get("/api/v1/auth/me", headers=_auth(token))
    assert me.status_code == 200
    assert me.json()["user"]["apple_user_id"] == "apple-sub-1"

    with db_factory() as db:
        assert db.query(User).count() == 1


def test_sign_in_with_apple_existing_user_reuses_row(client, db_factory) -> None:
    _sign_in(client, device_label="device-a")
    _sign_in(client, device_label="device-b")
    with db_factory() as db:
        assert db.query(User).count() == 1
        assert db.query(AuthSession).count() == 2


def test_sign_in_with_apple_bad_token(client, monkeypatch) -> None:
    # Turn off the dev shortcut so the real (failing) verification path runs.
    monkeypatch.setenv("LINOFINANCE_APPLE_DEV_SHORTCUT", "false")
    get_settings.cache_clear()
    response = client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": "not.a.real.jwt",
            "device_label": "x",
            "platform": "ios",
        },
    )
    assert response.status_code == 400
    assert "Invalid Apple identity token" in response.json()["detail"]


def test_sign_in_with_apple_invalid_platform(client) -> None:
    response = client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": "sub-x",
            "device_label": "x",
            "platform": "windows",
        },
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "platform must be one of: ios, macos"


def test_sign_in_with_apple_disabled_user(client, db_factory) -> None:
    with db_factory() as db:
        db.add(User(apple_user_id="disabled-sub", disabled=True))
        db.commit()
    response = _sign_in(client, sub="disabled-sub")
    assert response.status_code == 403
    assert response.json()["detail"] == "User is disabled"


def test_first_user_bootstraps_active(client, db_factory) -> None:
    """Single-user gate: the first sub on an empty table activates (audit 1.1)."""
    response = _sign_in(client, sub="owner-sub")
    assert response.status_code == 200, response.json()
    with db_factory() as db:
        user = db.query(User).one()
        assert user.apple_user_id == "owner-sub"
        assert user.disabled is False


def test_second_new_sub_is_disabled_and_refused(client, db_factory) -> None:
    """After bootstrap, a new sub is recorded disabled and refused (audit 1.1)."""
    assert _sign_in(client, sub="owner-sub").status_code == 200

    response = _sign_in(client, sub="intruder-sub")
    assert response.status_code == 403
    assert response.json()["detail"] == "User is disabled"

    # The disabled row is persisted (committed before raising) so ops can see it.
    with db_factory() as db:
        intruder = db.query(User).filter_by(apple_user_id="intruder-sub").one()
        assert intruder.disabled is True
        assert db.query(AuthSession).count() == 1  # only the owner has a session


def test_allowlisted_new_sub_activates(client, db_factory, monkeypatch) -> None:
    """A sub on the allowlist self-activates even on a non-empty table (audit 1.1)."""
    assert _sign_in(client, sub="owner-sub").status_code == 200

    monkeypatch.setenv("LINOFINANCE_APPLE_SUB_ALLOWLIST", "new-device-sub, other-sub")
    get_settings.cache_clear()

    response = _sign_in(client, sub="new-device-sub")
    assert response.status_code == 200, response.json()
    with db_factory() as db:
        user = db.query(User).filter_by(apple_user_id="new-device-sub").one()
        assert user.disabled is False


def test_existing_session_dies_when_user_disabled(client, db_factory) -> None:
    """A live session is rejected the moment its user is disabled (audit 1.2)."""
    token = _sign_in(client, sub="owner-sub").json()["session_token"]
    # Sanity: the session works before disabling.
    assert client.get("/api/v1/dashboard/summary", headers=_auth(token)).status_code == 200

    with db_factory() as db:
        user = db.query(User).filter_by(apple_user_id="owner-sub").one()
        user.disabled = True
        db.commit()

    # Any gated route now returns a clean 401, not a 500.
    assert client.get("/api/v1/dashboard/summary", headers=_auth(token)).status_code == 401
    assert client.get("/api/v1/auth/me", headers=_auth(token)).status_code == 401


def test_admin_env_token_unaffected_by_gate(client) -> None:
    """The admin env token bypasses the users table entirely (audit 1.1/1.2)."""
    response = client.get("/api/v1/dashboard/summary", headers=_auth(ADMIN_TOKEN))
    assert response.status_code == 200


def test_me_returns_user_for_session_token(client) -> None:
    token = _sign_in(client).json()["session_token"]
    me = client.get("/api/v1/auth/me", headers=_auth(token))
    assert me.status_code == 200
    body = me.json()
    assert body["user"] is not None
    assert body["session"] is not None
    assert body.get("admin") is False


def test_me_returns_admin_for_env_token(client) -> None:
    me = client.get("/api/v1/auth/me", headers=_auth(ADMIN_TOKEN))
    assert me.status_code == 200
    assert me.json() == {"user": None, "session": None, "admin": True}


def test_logout_revokes_session(client) -> None:
    token = _sign_in(client).json()["session_token"]
    logout = client.post("/api/v1/auth/logout", headers=_auth(token))
    assert logout.status_code == 204
    me = client.get("/api/v1/auth/me", headers=_auth(token))
    assert me.status_code == 401


def test_logout_rejects_admin_token(client) -> None:
    logout = client.post("/api/v1/auth/logout", headers=_auth(ADMIN_TOKEN))
    assert logout.status_code == 400
    assert logout.json()["detail"] == "Admin token cannot log out"


def test_list_sessions_marks_current(client) -> None:
    token_a = _sign_in(client, device_label="device-a").json()["session_token"]
    token_b = _sign_in(client, device_label="device-b").json()["session_token"]

    list_a = client.get("/api/v1/auth/sessions", headers=_auth(token_a)).json()
    assert len(list_a["items"]) == 2
    current_a = [i for i in list_a["items"] if i["is_current"]]
    assert len(current_a) == 1
    assert current_a[0]["device_label"] == "device-a"

    list_b = client.get("/api/v1/auth/sessions", headers=_auth(token_b)).json()
    current_b = [i for i in list_b["items"] if i["is_current"]]
    assert len(current_b) == 1
    assert current_b[0]["device_label"] == "device-b"


def test_revoke_other_session(client) -> None:
    resp_a = _sign_in(client, device_label="device-a").json()
    token_a, _ = resp_a["session_token"], None
    token_b = _sign_in(client, device_label="device-b").json()["session_token"]

    # Find the *other* session's id from token_a's list.
    items = client.get("/api/v1/auth/sessions", headers=_auth(token_a)).json()["items"]
    other_id = [i["id"] for i in items if not i["is_current"]][0]

    delete = client.delete(f"/api/v1/auth/sessions/{other_id}", headers=_auth(token_a))
    assert delete.status_code == 204

    # token_b (the revoked one) is now dead; token_a still works.
    assert client.get("/api/v1/auth/me", headers=_auth(token_b)).status_code == 401
    assert client.get("/api/v1/auth/me", headers=_auth(token_a)).status_code == 200


def test_revoke_nonexistent_session(client) -> None:
    token = _sign_in(client).json()["session_token"]
    delete = client.delete("/api/v1/auth/sessions/does-not-exist", headers=_auth(token))
    assert delete.status_code == 404
    assert delete.json()["detail"] == "Session not found"


def test_session_token_path_works_for_other_routes(client) -> None:
    token = _sign_in(client).json()["session_token"]
    response = client.get("/api/v1/dashboard/summary", headers=_auth(token))
    assert response.status_code == 200


def test_env_admin_token_still_works_for_other_routes(client) -> None:
    response = client.get("/api/v1/dashboard/summary", headers=_auth(ADMIN_TOKEN))
    assert response.status_code == 200


def test_no_token_is_unauthorized(client) -> None:
    response = client.get("/api/v1/dashboard/summary")
    assert response.status_code == 401


def test_expired_session_returns_401(client, db_factory) -> None:
    token = _sign_in(client).json()["session_token"]
    with db_factory() as db:
        session = db.query(AuthSession).one()
        session.expires_at = datetime.now(timezone.utc) - timedelta(days=1)
        db.commit()
    me = client.get("/api/v1/auth/me", headers=_auth(token))
    assert me.status_code == 401
