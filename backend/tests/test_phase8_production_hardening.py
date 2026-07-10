from collections.abc import Generator

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


@pytest.fixture(autouse=True)
def clear_settings_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _create_app_with_sqlite():
    """Build the full app (all middleware intact) but back it with an in-memory
    SQLite engine so DB-touching routes work without a live Postgres.

    v3.0.0 P3 (D0): ``GET /ai/config`` used to be DB-free, so these
    auth/rate-limit tests could probe it as a cheap non-public route. Config now
    lives in the ``ai_settings`` table, so the route opens a DB session — the
    override keeps these hardening tests independent of a running Postgres.
    """
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    testing_session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override_get_db() -> Generator[Session, None, None]:
        db = testing_session_local()
        try:
            yield db
        finally:
            db.close()

    app = create_app()
    app.dependency_overrides[get_db] = override_get_db
    return app


def test_local_api_stays_open_without_token(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.delenv("LINOFINANCE_API_AUTH_TOKEN", raising=False)

    with TestClient(_create_app_with_sqlite()) as client:
        response = client.get("/api/v1/ai/config")

    assert response.status_code == 200
    assert response.headers["x-request-id"]


def test_configured_token_protects_non_public_routes(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.setenv("LINOFINANCE_API_AUTH_TOKEN", "secret-token")

    with TestClient(_create_app_with_sqlite()) as client:
        health = client.get("/api/v1/health")
        unauthorized = client.get("/api/v1/ai/config")
        invalid = client.get(
            "/api/v1/ai/config",
            headers={"Authorization": "Bearer wrong"},
        )
        authorized = client.get(
            "/api/v1/ai/config",
            headers={"Authorization": "Bearer secret-token"},
        )

    assert health.status_code == 200
    assert health.json()["auth_required"] is True
    assert unauthorized.status_code == 401
    assert invalid.status_code == 401
    assert authorized.status_code == 200


def test_production_requires_api_token(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "production")
    monkeypatch.delenv("LINOFINANCE_API_AUTH_TOKEN", raising=False)

    with pytest.raises(RuntimeError, match="LINOFINANCE_API_AUTH_TOKEN"):
        create_app()


def test_rate_limit_returns_429(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.setenv("LINOFINANCE_API_AUTH_TOKEN", "secret-token")
    monkeypatch.setenv("LINOFINANCE_API_RATE_LIMIT_ENABLED", "true")
    monkeypatch.setenv("LINOFINANCE_API_RATE_LIMIT_PER_MINUTE", "1")

    headers = {"Authorization": "Bearer secret-token"}
    with TestClient(_create_app_with_sqlite()) as client:
        unauthorized = client.get("/api/v1/ai/config")
        first = client.get("/api/v1/ai/config", headers=headers)
        second = client.get("/api/v1/ai/config", headers=headers)

    assert unauthorized.status_code == 401
    assert unauthorized.headers["x-request-id"]
    assert "x-ratelimit-limit" not in unauthorized.headers
    assert first.status_code == 200
    assert first.headers["x-ratelimit-limit"] == "1"
    assert second.status_code == 429
    assert second.headers["retry-after"]
