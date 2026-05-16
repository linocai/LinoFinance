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
