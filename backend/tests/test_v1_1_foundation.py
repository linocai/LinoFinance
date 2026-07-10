from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.config import get_settings
from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.main import create_app
from app.models.attachment import Attachment
from app.services import ai_provider, attachments as attachment_service, push_dispatch


@pytest.fixture(autouse=True)
def clear_settings_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@contextmanager
def db_session_from_client(client):
    override = client.app.dependency_overrides[get_db]
    generator = override()
    db = next(generator)
    try:
        yield db
    finally:
        generator.close()


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
            "status": "confirmed",
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


def _create_entry_category_line_id(client) -> str:
    """Create a real entry and return its first category line id.

    Attachment uploads now validate that the owner entity exists (audit 2.4),
    so tests must point at a real ``entry_category_line``.
    """
    account = client.post(
        "/api/v1/accounts",
        json={"name": "Attach Wallet", "type": "balance", "currency": "CNY", "current_balance": "500"},
    ).json()
    category = client.post(
        "/api/v1/categories",
        json={"name": "Attach Dining", "type": "expense"},
    ).json()
    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "Attachable expense",
            "date": "2026-05-20",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "20",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "20",
                    "currency": "CNY",
                }
            ],
        },
    ).json()
    return entry["category_lines"][0]["id"]


def test_attachments_upload_download_and_reject_large_file(client, monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("LINOFINANCE_STORAGE_ROOT", str(tmp_path))
    get_settings.cache_clear()

    line_id = _create_entry_category_line_id(client)

    upload = client.post(
        "/api/v1/attachments",
        data={
            "owner_type": "entry_category_line",
            "owner_id": line_id,
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

    owner_list = client.get(
        "/api/v1/attachments",
        params={"owner_type": "entry_category_line", "owner_id": line_id},
    )
    assert owner_list.status_code == 200
    assert [item["id"] for item in owner_list.json()] == [attachment["id"]]

    too_large = client.post(
        "/api/v1/attachments",
        data={"owner_type": "entry_category_line", "owner_id": line_id},
        files={"file": ("large.bin", b"x" * (10 * 1024 * 1024 + 1), "application/octet-stream")},
    )
    assert too_large.status_code == 413

    stored_file = tmp_path / attachment["storage_key"]
    assert stored_file.exists()

    delete_response = client.delete(f"/api/v1/attachments/{attachment['id']}")
    assert delete_response.status_code == 204
    assert stored_file.exists()
    assert (
        client.get(
            "/api/v1/attachments",
            params={"owner_type": "entry_category_line", "owner_id": line_id},
        ).json()
        == []
    )
    assert client.get(f"/api/v1/attachments/{attachment['id']}").status_code == 404

    with db_session_from_client(client) as db:
        row = db.get(Attachment, attachment["id"])
        assert row is not None
        row.deleted_at = datetime.now(timezone.utc) - timedelta(days=31)
        db.commit()
        assert attachment_service.cleanup_deleted_attachments(db, retention_days=30) == 1
    assert not stored_file.exists()


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

    def fake_generate(prompt, config=None):
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


def test_push_dispatch_respects_rules_devices_and_due_dedup(client, monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()

    device = client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "iphone-air",
            "platform": "ios",
            "apns_token": "apns-token",
            "app_version": "1.1",
        },
    ).json()
    rule = client.post(
        "/api/v1/notification-rules",
        json={
            "title": "Credit push",
            "rule_type": "credit_repayment",
            "channel": "system",
            "trigger_payload": {},
        },
    )
    assert rule.status_code == 201

    credit_account = client.post(
        "/api/v1/accounts",
        json={"name": "Visa", "type": "credit", "currency": "CNY"},
    ).json()
    cycle = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account["id"],
            "cycle_start_date": "2026-04-01",
            "cycle_end_date": "2026-04-30",
            "statement_date": "2026-05-01",
            "due_date": "2026-05-23",
            "currency": "CNY",
            "statement_amount": "3375",
            "minimum_payment": "260",
        },
    )
    assert cycle.status_code == 201
    assert cycle.json()["status"] == "statement_generated"
    rules_after_cycle = client.get(
        "/api/v1/notification-rules", params={"rule_type": "credit_repayment"}
    ).json()
    assert rules_after_cycle[0]["last_triggered_at"] is not None

    with db_session_from_client(client) as db:
        results = push_dispatch.dispatch_due_credit_reminders(db, anchor_date=date(2026, 5, 20))
        assert len(results) == 1
        assert results[0].sent == 1
        assert results[0].payloads[0]["target_type"] == "credit_statement_cycle"
        assert results[0].payloads[0]["target_id"] == cycle.json()["id"]

        duplicate = push_dispatch.dispatch_due_credit_reminders(db, anchor_date=date(2026, 5, 20))
        assert duplicate[0].skipped_reason == "already_sent"
        audit = db.execute(
            select(AuditLog).where(AuditLog.action_type == "push.credit_due.t_minus_3")
        ).scalar_one()
        assert audit.target_id == cycle.json()["id"]

    client.delete(f"/api/v1/push/devices/{device['id']}")
    with db_session_from_client(client) as db:
        result = push_dispatch.dispatch_event(
            db,
            push_dispatch.PushEvent(
                event_type="manual_probe",
                rule_type="credit_repayment",
                title="Probe",
                body="Should not send",
                target_type="credit_statement_cycle",
                target_id=cycle.json()["id"],
            ),
        )
        assert result.skipped_reason == "no_enabled_push_device"


def test_push_dispatch_requires_matching_active_rule(client, monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()
    client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "iphone-air",
            "platform": "ios",
            "apns_token": "apns-token",
            "app_version": "1.1",
        },
    )
    client.post(
        "/api/v1/notification-rules",
        json={
            "title": "Paused credit push",
            "rule_type": "credit_repayment",
            "channel": "system",
            "trigger_payload": {},
            "status": "paused",
        },
    )

    with db_session_from_client(client) as db:
        result = push_dispatch.dispatch_event(
            db,
            push_dispatch.PushEvent(
                event_type="manual_probe",
                rule_type="credit_repayment",
                title="Probe",
                body="Paused rules should not send",
                target_type="credit_statement_cycle",
                target_id="cycle-1",
            ),
        )

    assert result.skipped_reason == "no_matching_notification_rule"


def test_credit_charge_statement_generation_dispatches_push(client, monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()
    client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "iphone-air",
            "platform": "ios",
            "apns_token": "apns-token",
            "app_version": "1.1",
        },
    )
    client.post(
        "/api/v1/notification-rules",
        json={
            "title": "Credit push",
            "rule_type": "credit_repayment",
            "channel": "system",
            "trigger_payload": {},
        },
    )
    credit_account = client.post(
        "/api/v1/accounts",
        json={"name": "Visa", "type": "credit", "currency": "CNY"},
    ).json()
    cycle = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account["id"],
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "CNY",
        },
    ).json()
    category = client.post(
        "/api/v1/categories",
        json={"name": "Travel", "type": "expense"},
    ).json()

    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "Flight",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "100",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_charge",
                    "amount": "100",
                    "currency": "CNY",
                }
            ],
        },
    )

    assert entry.status_code == 201
    updated_cycle = client.get(f"/api/v1/credit-statement-cycles/{cycle['id']}").json()
    assert updated_cycle["statement_amount"] == "100"
    rule = client.get("/api/v1/notification-rules", params={"rule_type": "credit_repayment"}).json()[0]
    assert rule["last_triggered_at"] is not None


def test_reimbursement_status_dispatches_system_push(client, monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()
    client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "iphone-air",
            "platform": "ios",
            "apns_token": "apns-token",
            "app_version": "1.1",
        },
    )
    client.post(
        "/api/v1/notification-rules",
        json={
            "title": "Reimbursement push",
            "rule_type": "reimbursement",
            "channel": "system",
            "trigger_payload": {"status": "received"},
        },
    )
    account = client.post(
        "/api/v1/accounts",
        json={"name": "Wallet", "type": "balance", "currency": "CNY", "current_balance": "1000"},
    ).json()
    category = client.post(
        "/api/v1/categories",
        json={"name": "Travel", "type": "expense"},
    ).json()
    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "Client trip",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "500",
                    "currency": "CNY",
                    "reimbursable_flag": True,
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": "2026-06-10",
                    "reimbursement_status": "pending",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "500",
                    "currency": "CNY",
                }
            ],
        },
    ).json()
    income_category = client.post(
        "/api/v1/categories",
        json={"name": "Reimbursement Income", "type": "income"},
    ).json()
    claim = client.get("/api/v1/reimbursement-claims").json()[0]
    assert claim["linked_entry_line_id"] == entry["category_lines"][0]["id"]

    # v2.1.0 P2: the dispatch trigger is now mark-received (the approval ceremony
    # is gone); marking a claim received fires the reimbursement system push.
    received = client.post(
        f"/api/v1/reimbursement-claims/{claim['id']}/mark-received",
        json={
            "actual_received_date": "2026-06-09",
            "received_account_id": account["id"],
            "entry": {
                "title": "Company reimbursement",
                "date": "2026-06-09",
                "category_lines": [
                    {
                        "category_id": income_category["id"],
                        "direction": "income",
                        "amount": "500",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_in",
                        "amount": "500",
                        "currency": "CNY",
                    }
                ],
            },
        },
    )

    assert received.status_code == 200
    rule = client.get("/api/v1/notification-rules", params={"rule_type": "reimbursement"}).json()[0]
    assert rule["last_triggered_at"] is not None


def test_high_risk_ai_plan_dispatches_system_push(client, monkeypatch) -> None:
    monkeypatch.setenv("LINOFINANCE_APNS_DRY_RUN", "true")
    get_settings.cache_clear()
    client.post(
        "/api/v1/push/devices",
        json={
            "device_id": "iphone-air",
            "platform": "ios",
            "apns_token": "apns-token",
            "app_version": "1.1",
        },
    )
    client.post(
        "/api/v1/notification-rules",
        json={
            "title": "AI push",
            "rule_type": "ai_plan",
            "channel": "system",
            "trigger_payload": {},
        },
    )

    plan = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "删除一条记录",
            "actions": [
                {
                    "action_type": "VoidEntry",
                    "payload": {"entry_id": "entry-1"},
                    "explanation": "destructive",
                }
            ],
            "explanation": "needs confirmation",
            "confidence": "0.9",
        },
    )

    assert plan.status_code == 201
    assert plan.json()["risk_level"] == "high"
    assert plan.json()["status"] == "requires_confirmation"
    rule = client.get("/api/v1/notification-rules", params={"rule_type": "ai_plan"}).json()[0]
    assert rule["last_triggered_at"] is not None


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
