import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import create_app
from app.services import ai_provider


@pytest.fixture(autouse=True)
def clear_settings_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_search_finds_account_and_entry(client) -> None:
    account = client.post(
        "/api/v1/accounts",
        json={"name": "Lino Checking", "type": "balance", "currency": "CNY"},
    ).json()
    category = client.post(
        "/api/v1/categories",
        json={"name": "Office", "type": "expense"},
    ).json()
    entry_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Office chair",
            "date": "2026-05-20",
            "status": "draft",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "80",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "80",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert entry_response.status_code == 201

    account_search = client.get("/api/v1/search", params={"q": "Lino"})
    entry_search = client.get("/api/v1/search", params={"q": "chair", "types": "entry"})

    assert account_search.status_code == 200
    assert account_search.json()["items"][0]["type"] == "account"
    assert entry_search.status_code == 200
    assert entry_search.json()["items"][0]["title"] == "Office chair"


def test_search_requires_token_when_auth_enabled(monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_ENVIRONMENT", "local")
    monkeypatch.setenv("LINOFINANCE_API_AUTH_TOKEN", "secret-token")
    get_settings.cache_clear()

    with TestClient(create_app()) as authed_app:
        response = authed_app.get("/api/v1/search", params={"q": "anything"})

    assert response.status_code == 401


def test_attachments_upload_download_and_reject_large_file(client, monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("LINOFINANCE_STORAGE_ROOT", str(tmp_path))
    get_settings.cache_clear()

    upload = client.post(
        "/api/v1/attachments",
        data={
            "owner_type": "entry_category_line",
            "owner_id": "line-1",
            "uploaded_by": "test",
        },
        files={"file": ("invoice.txt", b"hello invoice", "text/plain")},
    )
    assert upload.status_code == 201
    attachment = upload.json()
    assert attachment["checksum_sha256"]

    download = client.get(f"/api/v1/attachments/{attachment['id']}")
    assert download.status_code == 200
    assert download.content == b"hello invoice"

    too_large = client.post(
        "/api/v1/attachments",
        data={"owner_type": "entry_category_line", "owner_id": "line-1"},
        files={"file": ("large.bin", b"x" * (10 * 1024 * 1024 + 1), "application/octet-stream")},
    )
    assert too_large.status_code == 413


def test_reconciliation_adjustment_zeroes_drift(client) -> None:
    account = client.post(
        "/api/v1/accounts",
        json={
            "name": "Wallet",
            "type": "balance",
            "currency": "CNY",
            "current_balance": "100",
        },
    ).json()

    before = client.get("/api/v1/reconciliation/accounts").json()["items"][0]
    assert before["delta_amount"] == "100.00"
    assert before["needs_adjustment"] is True

    adjustment = client.post(
        "/api/v1/reconciliation/adjustments",
        json={"account_id": account["id"], "actual_amount": "100", "reason": "opening balance"},
    )
    assert adjustment.status_code == 201
    assert adjustment.json()["delta_amount"] == "100.00"

    after = client.get("/api/v1/reconciliation/accounts").json()["items"][0]
    assert after["delta_amount"] == "0.00"
    assert after["needs_adjustment"] is False


def test_ai_memos_generate_patch_and_archive(client, monkeypatch) -> None:
    def fake_generate(prompt):
        assert "2026-05-01" in prompt
        return {
            "summary": "## 月度备忘\n现金流稳定。",
            "prompt_token": 10,
            "completion_token": 20,
            "generator": "test",
            "confidence": "0.9",
        }

    monkeypatch.setattr(ai_provider, "generate_monthly_memo", fake_generate)

    generated = client.post(
        "/api/v1/ai/memos/generate",
        json={"period_start": "2026-05-01", "period_end": "2026-05-31"},
    )
    assert generated.status_code == 201
    memo = generated.json()
    assert memo["generator"] == "test"

    patched = client.patch(
        f"/api/v1/ai/memos/{memo['id']}",
        json={"summary": "更新后的 memo", "status": "published"},
    )
    assert patched.status_code == 200
    assert patched.json()["status"] == "published"

    delete_response = client.delete(f"/api/v1/ai/memos/{memo['id']}")
    assert delete_response.status_code == 204
    assert client.get("/api/v1/ai/memos", params={"period": "2026-05"}).json()["items"] == []


def test_push_devices_register_idempotently_and_disable(client) -> None:
    first = client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "device-a",
            "platform": "ios",
            "apns_token": "token-1",
            "app_version": "1.1",
        },
    )
    assert first.status_code == 201
    first_body = first.json()

    second = client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "device-b",
            "platform": "ios",
            "apns_token": "token-1",
            "app_version": "1.1.1",
        },
    )
    assert second.status_code == 201
    second_body = second.json()
    assert second_body["id"] == first_body["id"]
    assert second_body["device_id"] == "device-b"
    assert second_body["app_version"] == "1.1.1"

    delete_response = client.delete(f"/api/v1/push/devices/{second_body['id']}")
    assert delete_response.status_code == 204
