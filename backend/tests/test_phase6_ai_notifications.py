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
