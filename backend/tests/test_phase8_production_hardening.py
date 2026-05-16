import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import create_app


@pytest.fixture(autouse=True)
def clear_settings_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_local_api_stays_open_without_token(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.delenv("LINOFINANCE_API_AUTH_TOKEN", raising=False)

    with TestClient(create_app()) as client:
        response = client.get("/api/v1/ai/config")

    assert response.status_code == 200
    assert response.headers["x-request-id"]


def test_configured_token_protects_non_public_routes(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.setenv("LINOFINANCE_API_AUTH_TOKEN", "secret-token")

    with TestClient(create_app()) as client:
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
    with TestClient(create_app()) as client:
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
