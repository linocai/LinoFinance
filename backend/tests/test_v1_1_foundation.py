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
    audit = client.get(
        "/api/v1/audit-logs",
        params={"target_type": "account", "target_id": account["id"]},
    )
    assert audit.status_code == 200
    assert audit.json()[0]["action_type"] == "account_adjustment.create"
    assert audit.json()[0]["after_snapshot"]["adjustment_id"] == adjustment.json()["id"]


def test_ai_memos_generate_patch_and_archive(client, monkeypatch) -> None:
    prompts = []

    def fake_generate(prompt):
        prompts.append(prompt)
        return {
            "summary": f"## 月度备忘 {len(prompts)}\n现金流稳定。",
            "prompt_token": 10,
            "completion_token": 20,
            "generator": "test",
            "confidence": "0.9",
        }

    monkeypatch.setattr(ai_provider, "generate_monthly_memo", fake_generate)

    previous = client.post(
        "/api/v1/ai/memos/generate",
        json={"period_start": "2026-04-01", "period_end": "2026-04-30"},
    ).json()
    client.patch(
        f"/api/v1/ai/memos/{previous['id']}",
        json={"summary": "用户编辑后的四月 memo", "status": "published"},
    )

    generated = client.post(
        "/api/v1/ai/memos/generate?tone=warm",
        json={"period_start": "2026-05-01", "period_end": "2026-05-31"},
    )
    assert generated.status_code == 201
    memo = generated.json()
    assert memo["generator"] == "test"
    assert memo["created_at"]
    assert memo["updated_at"]
    assert "温暖" in prompts[-1]
    assert "用户编辑后的四月 memo" in prompts[-1]
    assert memo["stats_json"]["top_expense_categories"] == []
    assert "subscriptions" in memo["stats_json"]
    assert "reimbursements" in memo["stats_json"]
    assert "anomalies" in memo["stats_json"]

    regenerated = client.post(
        "/api/v1/ai/memos/generate?tone=terse",
        json={"period_start": "2026-05-01", "period_end": "2026-05-31"},
    )
    assert regenerated.status_code == 201
    assert regenerated.json()["id"] == memo["id"]
    assert "简短" in prompts[-1]
    assert len(client.get("/api/v1/ai/memos", params={"period": "2026-05"}).json()["items"]) == 1

    patched = client.patch(
        f"/api/v1/ai/memos/{memo['id']}",
        json={"summary": "更新后的 memo", "status": "published"},
    )
    assert patched.status_code == 200
    assert patched.json()["status"] == "published"
    assert patched.json()["created_at"] == memo["created_at"]

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


def test_cash_flow_pressure_includes_daily_net_window(client) -> None:
    client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Client invoice",
            "direction": "inflow",
            "cash_flow_type": "one_time",
            "amount": "100",
            "currency": "CNY",
            "expected_date": "2026-05-20",
        },
    )
    client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Rent",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": "40",
            "currency": "CNY",
            "expected_date": "2026-05-20",
        },
    )

    response = client.get(
        "/api/v1/reports/cash-flow-pressure",
        params={"anchor_date": "2026-05-20"},
    )

    assert response.status_code == 200
    daily = response.json()["daily_net_cny"]
    assert len(daily) == 30
    assert daily[0] == {
        "date": "2026-05-20",
        "inflow_cny": "100",
        "outflow_cny": "40",
        "net_cny": "60",
    }


def test_audit_limit_and_ai_related_filter(client) -> None:
    account = client.post(
        "/api/v1/accounts",
        json={
            "name": "Checking",
            "type": "balance",
            "currency": "CNY",
            "current_balance": "500",
        },
    ).json()
    category = client.post(
        "/api/v1/categories",
        json={"name": "Meals", "type": "expense"},
    ).json()
    plan_response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "午餐 88",
            "actions": [
                {
                    "action_type": "CreateEntry",
                    "payload": {
                        "title": "AI lunch",
                        "date": "2026-05-20",
                        "status": "confirmed",
                        "category_lines": [
                            {
                                "category_id": category["id"],
                                "direction": "expense",
                                "amount": "88",
                                "currency": "CNY",
                            }
                        ],
                        "account_movements": [
                            {
                                "account_id": account["id"],
                                "movement_type": "balance_out",
                                "amount": "88",
                                "currency": "CNY",
                            }
                        ],
                    },
                }
            ],
        },
    )
    assert plan_response.status_code == 201
    plan = plan_response.json()

    execute_response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})
    assert execute_response.status_code == 200
    executed = execute_response.json()
    target_id = executed["actions"][0]["target_id"]

    related = client.get(
        "/api/v1/ai/plans",
        params={"related_type": "financial_entry", "related_to": target_id},
    )
    audit = client.get(
        "/api/v1/audit-logs",
        params={"target_type": "financial_entry", "target_id": target_id, "limit": 1},
    )

    assert related.status_code == 200
    assert [item["id"] for item in related.json()] == [plan["id"]]
    assert audit.status_code == 200
    assert len(audit.json()) == 1
    assert audit.json()[0]["action_type"] == "AIActionExecution"
