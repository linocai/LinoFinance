import json
from datetime import date

from app.services import ai_provider


class _FakeLLMResponse:
    """Minimal stand-in for the urllib response context manager."""

    def __init__(self, payload: dict) -> None:
        self._data = json.dumps(payload).encode("utf-8")

    def read(self) -> bytes:
        return self._data

    def __enter__(self) -> "_FakeLLMResponse":
        return self

    def __exit__(self, *exc) -> bool:
        return False


def _patch_llm(monkeypatch, llm_output: dict, captured: dict):
    """Patch the provider's HTTP call to return `llm_output` (the parsed JSON the
    model would emit) and record the outgoing request for assertions. No real
    key and no real network call are ever used."""

    def fake_urlopen(request, timeout=None):
        captured["endpoint"] = request.full_url
        captured["authorization"] = request.get_header("Authorization")
        captured["body"] = json.loads(request.data.decode("utf-8"))
        response_payload = {
            "choices": [{"message": {"content": json.dumps(llm_output)}}],
            "usage": {"prompt_tokens": 5, "completion_tokens": 7},
        }
        return _FakeLLMResponse(response_payload)

    monkeypatch.setattr(ai_provider.urllib.request, "urlopen", fake_urlopen)


def create_account(client, name="Checking", balance="500"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "balance",
            "currency": "CNY",
            "current_balance": balance,
        },
    )
    assert response.status_code == 201
    return response.json()


def create_category(client, name="Food", category_type="expense"):
    response = client.post("/api/v1/categories", json={"name": name, "type": category_type})
    assert response.status_code == 201
    return response.json()


def create_confirmed_expense(client, account_id, category_id, amount="50"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Existing expense",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category_id,
                    "direction": "expense",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account_id,
                    "movement_type": "balance_out",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_ai_config_reads_env_shape_without_exposing_secret(client) -> None:
    response = client.get("/api/v1/ai/config")

    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "openai_compatible"
    assert body["api_key_configured"] is False
    assert body["auto_confirm_limit_cny"] == "1000"
    assert "api_key" not in body


def test_low_risk_ai_entry_can_execute_as_auto_confirm_candidate(client) -> None:
    account = create_account(client)
    category = create_category(client)

    response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "今天午餐 88 元",
            "actions": [
                {
                    "action_type": "CreateEntry",
                    "payload": {
                        "title": "Lunch",
                        "date": "2026-05-16",
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
                    "explanation": "Small complete CNY expense.",
                }
            ],
        },
    )

    assert response.status_code == 201
    plan = response.json()
    assert plan["status"] == "auto_confirm_candidate"
    assert plan["risk_level"] == "low"
    assert plan["auto_confirm_eligible"] is True
    assert plan["actions"][0]["requires_confirmation"] is False

    execute_response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})

    assert execute_response.status_code == 200
    executed = execute_response.json()
    assert executed["status"] == "executed"
    assert executed["actions"][0]["status"] == "executed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "412.00"

    audit_logs = client.get("/api/v1/audit-logs", params={"target_type": "financial_entry"}).json()
    assert [log["action_type"] for log in audit_logs] == ["AIActionExecution"]


def test_high_risk_void_entry_requires_approval_and_strong_confirmation(client) -> None:
    account = create_account(client)
    category = create_category(client)
    entry = create_confirmed_expense(client, account["id"], category["id"])
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "450.00"

    response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "帮我作废这笔账",
            "actions": [
                {
                    "action_type": "VoidEntry",
                    "payload": {"entry_id": entry["id"]},
                    "explanation": "Voiding a confirmed entry changes history.",
                }
            ],
        },
    )

    assert response.status_code == 201
    plan = response.json()
    assert plan["risk_level"] == "high"
    assert plan["status"] == "requires_confirmation"

    unapproved_execute = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})
    assert unapproved_execute.status_code == 400
    assert unapproved_execute.json()["detail"] == "AI plan requires approval before execution"

    approve_response = client.post(f"/api/v1/ai/plans/{plan['id']}/approve", json={})
    assert approve_response.status_code == 200

    weak_execute = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})
    assert weak_execute.status_code == 400
    assert weak_execute.json()["detail"] == "High-risk AI plans require strong confirmation"

    execute_response = client.post(
        f"/api/v1/ai/plans/{plan['id']}/execute",
        json={"strong_confirm": "EXECUTE_HIGH_RISK"},
    )
    assert execute_response.status_code == 200
    assert execute_response.json()["status"] == "executed"
    assert client.get(f"/api/v1/entries/{entry['id']}").json()["status"] == "voided"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "500.00"


def test_ai_notification_rule_action_executes_with_audit_log(client) -> None:
    response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "每月 20 号提醒我还信用卡",
            "actions": [
                {
                    "action_type": "GenerateNotificationRule",
                    "payload": {
                        "title": "Credit card repayment reminder",
                        "rule_type": "credit_repayment",
                        "channel": "in_app",
                        "trigger_payload": {"days_before": 3},
                        "next_trigger_date": "2026-06-17",
                    },
                    "explanation": "Reminder rules require review before enabling.",
                }
            ],
        },
    )
    assert response.status_code == 201
    plan = response.json()
    assert plan["risk_level"] == "medium"
    assert plan["status"] == "requires_confirmation"

    assert client.post(f"/api/v1/ai/plans/{plan['id']}/approve", json={}).status_code == 200
    execute_response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})

    assert execute_response.status_code == 200
    rule_id = execute_response.json()["actions"][0]["target_id"]
    rule = client.get(f"/api/v1/notification-rules/{rule_id}").json()
    assert rule["status"] == "active"
    assert rule["rule_type"] == "credit_repayment"

    audit_logs = client.get("/api/v1/audit-logs", params={"target_id": rule_id}).json()
    assert audit_logs[0]["target_type"] == "notification_rule"
    assert audit_logs[0]["action_type"] == "AIActionExecution"


def test_ai_can_confirm_cash_flow_status_with_audit_and_rollback(client) -> None:
    cash_flow_response = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected refund",
            "direction": "inflow",
            "cash_flow_type": "one_time",
            "amount": "120",
            "currency": "CNY",
            "expected_date": "2026-06-01",
        },
    )
    assert cash_flow_response.status_code == 201
    cash_flow = cash_flow_response.json()

    response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "确认这笔预计回款",
            "actions": [
                {
                    "action_type": "SetCashFlowStatus",
                    "payload": {
                        "cash_flow_item_id": cash_flow["id"],
                        "status": "confirmed",
                    },
                    "explanation": "Cash-flow status changes should be reviewed.",
                }
            ],
        },
    )
    assert response.status_code == 201
    plan = response.json()
    assert plan["risk_level"] == "medium"
    assert plan["status"] == "requires_confirmation"

    assert client.post(f"/api/v1/ai/plans/{plan['id']}/approve", json={}).status_code == 200
    execute_response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})

    assert execute_response.status_code == 200
    executed_plan = execute_response.json()
    action = executed_plan["actions"][0]
    assert action["status"] == "executed"
    assert action["target_type"] == "cash_flow_item"
    assert client.get(f"/api/v1/cash-flow-items/{cash_flow['id']}").json()["status"] == "confirmed"

    audit_logs = client.get("/api/v1/audit-logs", params={"target_id": cash_flow["id"]}).json()
    assert audit_logs[0]["target_type"] == "cash_flow_item"
    assert audit_logs[0]["action_type"] == "AIActionExecution"

    rollback_response = client.post(f"/api/v1/ai/actions/{action['id']}/rollback")
    assert rollback_response.status_code == 200
    assert rollback_response.json()["status"] == "rolled_back"
    assert client.get(f"/api/v1/cash-flow-items/{cash_flow['id']}").json()["status"] == "expected"


def test_ai_can_update_reimbursement_status_with_audit_and_rollback(client) -> None:
    account = create_account(client)
    category = create_category(client)
    entry = create_confirmed_expense(client, account["id"], category["id"], amount="80")
    claim_response = client.post(
        "/api/v1/reimbursement-claims",
        json={
            "linked_entry_id": entry["id"],
            "linked_entry_line_id": entry["category_lines"][0]["id"],
            "amount": "80",
            "currency": "CNY",
            "payer": "company",
            "expected_date": "2026-06-10",
        },
    )
    assert claim_response.status_code == 201
    claim = claim_response.json()

    response = client.post(
        "/api/v1/ai/plans",
        json={
            "source_text": "这笔报销不打算要了",
            "actions": [
                {
                    # v2.1.0 P2: reimbursement is three-state now; the only status
                    # the AI can set directly is "abandoned" (pending is initial,
                    # received requires mark-received).
                    "action_type": "UpdateReimbursementStatus",
                    "payload": {
                        "reimbursement_claim_id": claim["id"],
                        "status": "abandoned",
                    },
                    "explanation": "Reimbursement status changes require confirmation.",
                }
            ],
        },
    )
    assert response.status_code == 201
    plan = response.json()
    assert plan["risk_level"] == "medium"
    assert plan["status"] == "requires_confirmation"

    assert client.post(f"/api/v1/ai/plans/{plan['id']}/approve", json={}).status_code == 200
    execute_response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})

    assert execute_response.status_code == 200
    executed_plan = execute_response.json()
    action = executed_plan["actions"][0]
    assert action["status"] == "executed"
    assert action["target_type"] == "reimbursement_claim"
    assert client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()["status"] == "abandoned"

    audit_logs = client.get("/api/v1/audit-logs", params={"target_id": claim["id"]}).json()
    assert audit_logs[0]["target_type"] == "reimbursement_claim"
    assert audit_logs[0]["action_type"] == "AIActionExecution"

    rollback_response = client.post(f"/api/v1/ai/actions/{action['id']}/rollback")
    assert rollback_response.status_code == 200
    assert rollback_response.json()["status"] == "rolled_back"
    assert client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()["status"] == "pending"


def test_ai_prompt_anchors_today_to_business_timezone(monkeypatch) -> None:
    # v3.0.0 P1: _build_system_prompt must resolve "today" via app_today()
    # (business timezone), not the server's UTC date.today() — a UTC-day
    # boundary can otherwise put the AI's anchor date a day off from the
    # user's Asia/Shanghai calendar day. Monkeypatch the name ai_provider
    # bound via `from app.core.timeutils import app_today`, so this test
    # would fail if the code ever reverts to calling date.today() directly.
    fixed_today = date(2026, 1, 2)
    monkeypatch.setattr(ai_provider, "app_today", lambda: fixed_today)

    prompt = ai_provider._build_system_prompt()

    assert "Today's date is 2026-01-02." in prompt


def test_ai_prompt_lists_void_entry_action() -> None:
    # v3.0.0 P3: VoidEntry must be advertised to the model (execution chain
    # already supports it; the prompt previously omitted it).
    prompt = ai_provider._build_system_prompt()
    assert "VoidEntry" in prompt


def test_ai_config_put_masks_key_and_honors_field_presence(client) -> None:
    # v3.0.0 P3 D0: PUT persists config; GET never echoes the full key.
    put_response = client.put(
        "/api/v1/ai/config",
        json={
            "base_url": "https://llm.example/v1",
            "api_key": "sk-secret-abcd1234",
            "model": "gpt-test",
        },
    )
    assert put_response.status_code == 200
    put_body = put_response.json()
    assert put_body["base_url"] == "https://llm.example/v1"
    assert put_body["model"] == "gpt-test"
    assert put_body["base_url_configured"] is True
    assert put_body["api_key_configured"] is True
    assert put_body["api_key_hint"] == "...1234"
    assert "api_key" not in put_body
    assert "sk-secret-abcd1234" not in json.dumps(put_body)

    get_body = client.get("/api/v1/ai/config").json()
    assert get_body["base_url"] == "https://llm.example/v1"
    assert get_body["api_key_hint"] == "...1234"
    assert "sk-secret-abcd1234" not in json.dumps(get_body)

    # Absent api_key key -> preserve existing key; model updated.
    preserve = client.put("/api/v1/ai/config", json={"model": "gpt-test-2"}).json()
    assert preserve["model"] == "gpt-test-2"
    assert preserve["api_key_configured"] is True
    assert preserve["api_key_hint"] == "...1234"
    assert preserve["base_url"] == "https://llm.example/v1"

    # Empty string -> clear that field.
    cleared = client.put("/api/v1/ai/config", json={"api_key": ""}).json()
    assert cleared["api_key_configured"] is False
    assert cleared["api_key_hint"] is None
    # base_url/model untouched by the key-only clear.
    assert cleared["base_url"] == "https://llm.example/v1"
    assert cleared["model"] == "gpt-test-2"


def test_ai_plan_uses_db_config_and_injects_ledger_context(client, monkeypatch) -> None:
    # v3.0.0 P3: the LLM path resolves config DB > env, injects the user's real
    # account/category lists, and lands the returned real ids in the proposal.
    account = create_account(client)
    category = create_category(client)

    assert client.put(
        "/api/v1/ai/config",
        json={
            "base_url": "https://db-llm.test/v1",
            "api_key": "sk-db-key-9999",
            "model": "db-model-x",
        },
    ).status_code == 200

    llm_output = {
        "actions": [
            {
                "action_type": "CreateEntry",
                "payload": {
                    "title": "Lunch",
                    "date": "2026-05-16",
                    "status": "confirmed",
                    "category_lines": [
                        {
                            "category_id": category["id"],
                            "direction": "expense",
                            "amount": "30",
                            "currency": "CNY",
                        }
                    ],
                    "account_movements": [
                        {
                            "account_id": account["id"],
                            "movement_type": "balance_out",
                            "amount": "30",
                            "currency": "CNY",
                        }
                    ],
                },
                "explanation": "A small lunch expense.",
            }
        ],
        "explanation": "Parsed one expense.",
        "confidence": 0.9,
    }
    captured: dict = {}
    _patch_llm(monkeypatch, llm_output, captured)

    response = client.post("/api/v1/ai/plans", json={"source_text": "午餐 30 元"})
    assert response.status_code == 201

    # DB config was used (DB > env; env is unset in tests).
    assert captured["endpoint"] == "https://db-llm.test/v1/chat/completions"
    assert captured["authorization"] == "Bearer sk-db-key-9999"
    assert captured["body"]["model"] == "db-model-x"

    # The system prompt carried the real account + category lists.
    system_prompt = captured["body"]["messages"][0]["content"]
    assert account["id"] in system_prompt
    assert "Checking" in system_prompt
    assert category["id"] in system_prompt
    assert "Food" in system_prompt

    # The proposal landed the real ids (not blank / not fabricated).
    plan = response.json()
    payload = plan["actions"][0]["payload"]
    assert payload["account_movements"][0]["account_id"] == account["id"]
    assert payload["category_lines"][0]["category_id"] == category["id"]


def test_ai_plan_rejects_fabricated_account_id(client, monkeypatch) -> None:
    # v3.0.0 P3 defense-in-depth: an id the model invented (not in the user's
    # real lists) must be intercepted before storage/execution.
    create_account(client)
    category = create_category(client)

    llm_output = {
        "actions": [
            {
                "action_type": "CreateEntry",
                "payload": {
                    "title": "Lunch",
                    "date": "2026-05-16",
                    "status": "confirmed",
                    "category_lines": [
                        {
                            "category_id": category["id"],
                            "direction": "expense",
                            "amount": "30",
                            "currency": "CNY",
                        }
                    ],
                    "account_movements": [
                        {
                            "account_id": "acc-does-not-exist",
                            "movement_type": "balance_out",
                            "amount": "30",
                            "currency": "CNY",
                        }
                    ],
                },
                "explanation": "Fabricated account id.",
            }
        ],
    }
    captured: dict = {}
    _patch_llm(monkeypatch, llm_output, captured)

    assert client.put(
        "/api/v1/ai/config",
        json={"base_url": "https://x/v1", "api_key": "k12345", "model": "m"},
    ).status_code == 200

    response = client.post("/api/v1/ai/plans", json={"source_text": "午餐 30 元"})
    assert response.status_code == 400
    assert "acc-does-not-exist" in response.json()["detail"]
    # Nothing was stored.
    assert client.get("/api/v1/ai/plans").json() == []


def test_ai_plan_without_config_returns_clear_error(client) -> None:
    # v3.0.0 P3: with no DB row and no env config, the LLM path fails clearly.
    response = client.post("/api/v1/ai/plans", json={"source_text": "午餐 30 元"})
    assert response.status_code == 400
    assert "not configured" in response.json()["detail"].lower()


def _put_ai_config(client) -> None:
    assert client.put(
        "/api/v1/ai/config",
        json={
            "base_url": "https://db-llm.test/v1",
            "api_key": "sk-db-key-9999",
            "model": "db-model-x",
        },
    ).status_code == 200


def _incomplete_entry_llm_output(category_id=None) -> dict:
    """A CreateEntry proposal whose movement has NO account_id — the exact shape
    the system prompt tells the LLM to produce when it can't map the receipt to
    a listed account (v3.1.x 快修: previously 400'd at create, unstorable)."""
    category_lines = []
    if category_id is not None:
        category_lines.append(
            {
                "category_id": category_id,
                "direction": "expense",
                "amount": "20",
                "currency": "CNY",
            }
        )
    return {
        "actions": [
            {
                "action_type": "CreateEntry",
                "payload": {
                    "title": "扫码付款",
                    "date": "2026-05-16",
                    "status": "confirmed",
                    "category_lines": category_lines,
                    "account_movements": [
                        {
                            "movement_type": "balance_out",
                            "amount": "20.00",
                            "currency": "CNY",
                        }
                    ],
                },
                "explanation": "无法确定账户，account_id 留空。",
            }
        ],
        "explanation": "Parsed one expense without a resolvable account.",
        "confidence": 0.8,
    }


def test_ai_plan_stores_id_incomplete_proposal_requires_confirmation(client, monkeypatch) -> None:
    # v3.1.x 快修: an id-incomplete proposal (missing account_id only) must be
    # STORABLE — parked as requires_confirmation for the review UI to complete —
    # and must never be an auto-confirm candidate regardless of amount (20 CNY
    # is far below the 1000 auto-confirm limit).
    create_account(client)
    category = create_category(client)
    _put_ai_config(client)
    _patch_llm(monkeypatch, _incomplete_entry_llm_output(category["id"]), {})

    response = client.post("/api/v1/ai/plans", json={"source_text": "扫码付了20元"})
    assert response.status_code == 201
    plan = response.json()
    assert plan["status"] == "requires_confirmation"
    assert plan["risk_level"] == "medium"
    assert plan["auto_confirm_eligible"] is False
    # Payload stored intact — movement still has no account_id for the UI to fill.
    movement = plan["actions"][0]["payload"]["account_movements"][0]
    assert "account_id" not in movement


def test_ai_plan_incomplete_other_schema_errors_still_reject(client, monkeypatch) -> None:
    # Leniency is ONLY for missing account_id/category_id. A payload that is
    # broken in any other way (here: movement missing `amount` too) stays a
    # hard create-time 400.
    create_account(client)
    category = create_category(client)
    _put_ai_config(client)
    llm_output = _incomplete_entry_llm_output(category["id"])
    del llm_output["actions"][0]["payload"]["account_movements"][0]["amount"]
    _patch_llm(monkeypatch, llm_output, {})

    response = client.post("/api/v1/ai/plans", json={"source_text": "扫码付了20元"})
    assert response.status_code == 400


def test_ai_plan_incomplete_execute_rejected_cleanly(client, monkeypatch) -> None:
    # Executing an id-incomplete plan without completing it must fail cleanly at
    # the strict execute-time validation (`_apply_action` re-validates
    # EntryCreate) and write nothing to the ledger.
    account = create_account(client)
    category = create_category(client)
    _put_ai_config(client)
    _patch_llm(monkeypatch, _incomplete_entry_llm_output(category["id"]), {})

    plan = client.post("/api/v1/ai/plans", json={"source_text": "扫码付了20元"}).json()
    assert client.post(f"/api/v1/ai/plans/{plan['id']}/approve", json={}).status_code == 200

    response = client.post(f"/api/v1/ai/plans/{plan['id']}/execute", json={})
    assert response.status_code == 400

    # Nothing hit the ledger and the account balance is untouched.
    entries = client.get("/api/v1/entries").json()
    assert all(e["title"] != "扫码付款" for e in entries)
    refreshed = client.get(f"/api/v1/accounts/{account['id']}").json()
    assert refreshed["current_balance"] == account["current_balance"]
