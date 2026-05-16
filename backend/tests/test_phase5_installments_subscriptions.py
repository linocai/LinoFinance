def create_account(client, name, account_type, currency, balance="0"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": account_type,
            "currency": currency,
            "current_balance": balance,
        },
    )
    assert response.status_code == 201
    return response.json()


def create_category(client, name="Electronics", category_type="expense"):
    response = client.post("/api/v1/categories", json={"name": name, "type": category_type})
    assert response.status_code == 201
    return response.json()


def create_usd_cny_rate(client):
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "6.8",
            "date": "2026-05-01",
            "source": "manual",
        },
    )
    assert response.status_code == 201


def create_statement_cycle(client, credit_account_id):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account_id,
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "USD",
        },
    )
    assert response.status_code == 201
    return response.json()


def create_confirmed_credit_purchase(client):
    create_usd_cny_rate(client)
    credit_account = create_account(client, "Chase Credit", "credit", "USD")
    create_statement_cycle(client, credit_account["id"])
    category = create_category(client)
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Laptop",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "1200",
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "1200",
                    "currency": "USD",
                }
            ],
        },
    )
    assert response.status_code == 201
    return response.json(), credit_account


def test_installment_plan_generates_monthly_cash_flows(client) -> None:
    entry, credit_account = create_confirmed_credit_purchase(client)

    response = client.post(
        "/api/v1/installment-plans",
        json={
            "linked_entry_id": entry["id"],
            "credit_account_id": credit_account["id"],
            "total_amount": "1200",
            "currency": "USD",
            "number_of_payments": 3,
            "start_date": "2026-06-15",
        },
    )

    assert response.status_code == 201
    plan = response.json()
    assert plan["generated_cash_flow_count"] == 3
    assert plan["payment_amount"] == "400"
    assert plan["end_date"] == "2026-08-15"

    cash_flows = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_installment_plan_id"] == plan["id"]
    ]
    assert [item["amount"] for item in cash_flows] == ["400", "400", "400"]
    assert [item["expected_date"] for item in cash_flows] == [
        "2026-06-15",
        "2026-07-15",
        "2026-08-15",
    ]
    assert all(item["cash_flow_type"] == "installment" for item in cash_flows)
    assert client.get(f"/api/v1/accounts/{credit_account['id']}").json()["current_liability"] == "1200.00"


def test_installment_plan_requires_matching_confirmed_credit_charge(client) -> None:
    credit_account = create_account(client, "Chase Credit", "credit", "USD")
    response = client.post(
        "/api/v1/installment-plans",
        json={
            "linked_entry_id": "missing",
            "credit_account_id": credit_account["id"],
            "total_amount": "1200",
            "currency": "USD",
            "number_of_payments": 3,
            "start_date": "2026-06-15",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Linked entry not found"


def test_cancel_installment_plan_cancels_open_cash_flows(client) -> None:
    entry, credit_account = create_confirmed_credit_purchase(client)
    plan = client.post(
        "/api/v1/installment-plans",
        json={
            "linked_entry_id": entry["id"],
            "credit_account_id": credit_account["id"],
            "total_amount": "1200",
            "currency": "USD",
            "number_of_payments": 3,
            "start_date": "2026-06-15",
        },
    ).json()

    cancel_response = client.post(f"/api/v1/installment-plans/{plan['id']}/cancel")

    assert cancel_response.status_code == 200
    assert cancel_response.json()["status"] == "cancelled"
    cash_flows = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_installment_plan_id"] == plan["id"]
    ]
    assert {item["status"] for item in cash_flows} == {"cancelled"}


def test_subscription_rule_generates_next_cash_flow_without_changing_balance(client) -> None:
    account = create_account(client, "Checking", "balance", "CNY", balance="100")
    category = create_category(client, name="Streaming")

    response = client.post(
        "/api/v1/subscription-rules",
        json={
            "title": "Streaming",
            "amount": "30",
            "currency": "CNY",
            "account_id": account["id"],
            "category_id": category["id"],
            "billing_interval": "monthly",
            "billing_day": 5,
            "start_date": "2026-06-05",
        },
    )

    assert response.status_code == 201
    rule = response.json()
    assert rule["generated_cash_flow_count"] == 1
    assert rule["next_charge_date"] == "2026-06-05"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "100.00"

    cash_flow = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_subscription_rule_id"] == rule["id"]
    ][0]
    assert cash_flow["cash_flow_type"] == "subscription"
    assert cash_flow["amount"] == "30"
    assert cash_flow["expected_date"] == "2026-06-05"
    assert cash_flow["status"] == "expected"


def test_settling_subscription_cash_flow_advances_rule_and_generates_next(client) -> None:
    account = create_account(client, "Checking", "balance", "CNY", balance="100")
    category = create_category(client, name="Streaming")
    rule = client.post(
        "/api/v1/subscription-rules",
        json={
            "title": "Streaming",
            "amount": "30",
            "currency": "CNY",
            "account_id": account["id"],
            "category_id": category["id"],
            "billing_interval": "monthly",
            "billing_day": 5,
            "start_date": "2026-06-05",
        },
    ).json()
    first_cash_flow = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_subscription_rule_id"] == rule["id"]
    ][0]

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{first_cash_flow['id']}/settle",
        json={
            "entry": {
                "title": "Streaming charge",
                "date": "2026-06-05",
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
            }
        },
    )

    assert settle_response.status_code == 200
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "70.00"
    updated_rule = client.get(f"/api/v1/subscription-rules/{rule['id']}").json()
    assert updated_rule["next_charge_date"] == "2026-07-05"
    assert updated_rule["generated_cash_flow_count"] == 2

    subscription_cash_flows = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_subscription_rule_id"] == rule["id"]
    ]
    assert [item["expected_date"] for item in subscription_cash_flows] == [
        "2026-06-05",
        "2026-07-05",
    ]
    assert subscription_cash_flows[0]["status"] == "settled"
    assert subscription_cash_flows[1]["status"] == "expected"


def test_cancel_subscription_rule_cancels_open_cash_flows(client) -> None:
    account = create_account(client, "Checking", "balance", "CNY", balance="100")
    category = create_category(client, name="Streaming")
    rule = client.post(
        "/api/v1/subscription-rules",
        json={
            "title": "Streaming",
            "amount": "30",
            "currency": "CNY",
            "account_id": account["id"],
            "category_id": category["id"],
            "billing_interval": "monthly",
            "start_date": "2026-06-05",
        },
    ).json()

    cancel_response = client.post(f"/api/v1/subscription-rules/{rule['id']}/cancel")

    assert cancel_response.status_code == 200
    assert cancel_response.json()["status"] == "cancelled"
    cash_flow = [
        item
        for item in client.get("/api/v1/cash-flow-items").json()
        if item["linked_subscription_rule_id"] == rule["id"]
    ][0]
    assert cash_flow["status"] == "cancelled"
