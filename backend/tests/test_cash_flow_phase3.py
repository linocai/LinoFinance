from decimal import Decimal


def create_account(client, name="Wallet", account_type="balance", currency="CNY", balance="0"):
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


def create_category(client, name="Salary", category_type="income"):
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
    return response.json()


def create_cycle(client, account_id, statement_amount="0", status="open"):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": account_id,
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "USD",
            "statement_amount": statement_amount,
            "status": status,
        },
    )
    assert response.status_code == 201
    return response.json()


def test_create_cash_flow_item_does_not_change_account_balance(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)

    response = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected salary",
            "direction": "inflow",
            "cash_flow_type": "salary",
            "amount": "1000",
            "currency": "CNY",
            "expected_date": "2026-06-01",
            "account_id": account["id"],
            "category_id": category["id"],
        },
    )

    assert response.status_code == 201
    item = response.json()
    assert item["status"] == "expected"
    assert item["converted_cny_amount"] == "1000"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "100.00"


def test_confirm_and_cancel_cash_flow_item(client) -> None:
    response = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected rent",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": "800",
            "currency": "CNY",
            "expected_date": "2026-06-05",
        },
    )
    item = response.json()

    confirm_response = client.post(f"/api/v1/cash-flow-items/{item['id']}/confirm")
    assert confirm_response.status_code == 200
    assert confirm_response.json()["status"] == "confirmed"

    cancel_response = client.post(f"/api/v1/cash-flow-items/{item['id']}/cancel")
    assert cancel_response.status_code == 200
    assert cancel_response.json()["status"] == "cancelled"


def test_settle_cash_flow_item_creates_confirmed_entry_and_changes_balance(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)
    item = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected salary",
            "direction": "inflow",
            "cash_flow_type": "salary",
            "amount": "1000",
            "currency": "CNY",
            "expected_date": "2026-06-01",
            "account_id": account["id"],
            "category_id": category["id"],
            "status": "confirmed",
        },
    ).json()

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "June salary",
                "entry_type": "single",
                "date": "2026-06-01",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "income",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_in",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )

    assert settle_response.status_code == 200
    result = settle_response.json()
    assert result["cash_flow_item"]["status"] == "settled"
    assert result["cash_flow_item"]["linked_entry_id"] == result["entry"]["id"]
    assert result["entry"]["status"] == "confirmed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1100.00"


def test_settle_cash_flow_item_requires_matching_entry_payload(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)
    item = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected salary",
            "direction": "inflow",
            "cash_flow_type": "salary",
            "amount": "1000",
            "currency": "CNY",
            "expected_date": "2026-06-01",
            "account_id": account["id"],
            "category_id": category["id"],
            "status": "confirmed",
        },
    ).json()

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "Wrong salary amount",
                "entry_type": "single",
                "date": "2026-06-01",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "income",
                        "amount": "999",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_in",
                        "amount": "999",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )

    assert settle_response.status_code == 400
    assert settle_response.json()["detail"] == "Settlement entry category lines must match the cash flow item"
    unchanged_item = client.get(f"/api/v1/cash-flow-items/{item['id']}").json()
    assert unchanged_item["status"] == "confirmed"
    assert unchanged_item["linked_entry_id"] is None
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "100.00"


def test_settle_transfer_cash_flow_requires_transfer_only_entry(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)
    item = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Transfer preview",
            "direction": "transfer",
            "cash_flow_type": "one_time",
            "amount": "50",
            "currency": "CNY",
            "expected_date": "2026-06-01",
            "account_id": account["id"],
            "status": "confirmed",
        },
    ).json()

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "Wrong transfer settlement",
                "entry_type": "single",
                "date": "2026-06-01",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "expense",
                        "amount": "50",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_out",
                        "amount": "50",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )

    assert settle_response.status_code == 400
    assert settle_response.json()["detail"] == "Settlement entry account movements must match the cash flow item"
    assert client.get(f"/api/v1/cash-flow-items/{item['id']}").json()["status"] == "confirmed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "100.00"


def test_credit_statement_cycle_with_amount_generates_repayment_cash_flow(client) -> None:
    create_usd_cny_rate(client)
    credit_account = create_account(client, name="Chase Credit", account_type="credit", currency="USD")

    cycle = create_cycle(
        client,
        credit_account["id"],
        statement_amount="300",
        status="statement_generated",
    )

    assert cycle["linked_cash_flow_item_id"] is not None
    cash_flow = client.get(f"/api/v1/cash-flow-items/{cycle['linked_cash_flow_item_id']}").json()
    assert cash_flow["cash_flow_type"] == "credit_repayment"
    assert cash_flow["direction"] == "transfer"
    assert cash_flow["amount"] == "300"
    assert cash_flow["converted_cny_amount"] == "2040"
    assert cash_flow["status"] == "confirmed"
    assert cash_flow["linked_statement_cycle_id"] == cycle["id"]


def test_credit_charge_generates_and_repayment_settles_repayment_cash_flow(client) -> None:
    create_usd_cny_rate(client)
    checking = create_account(
        client,
        name="Checking",
        account_type="balance",
        currency="USD",
        balance="500",
    )
    credit_account = create_account(client, name="Chase Credit", account_type="credit", currency="USD")
    cycle = create_cycle(client, credit_account["id"])
    category = create_category(client, name="Travel", category_type="expense")

    charge_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Flight",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "200",
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "200",
                    "currency": "USD",
                }
            ],
        },
    )
    assert charge_response.status_code == 201

    updated_cycle = client.get(f"/api/v1/credit-statement-cycles/{cycle['id']}").json()
    cash_flow_id = updated_cycle["linked_cash_flow_item_id"]
    assert cash_flow_id is not None
    generated_cash_flow = client.get(f"/api/v1/cash-flow-items/{cash_flow_id}").json()
    assert generated_cash_flow["amount"] == "200"
    assert generated_cash_flow["status"] == "expected"

    repayment_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Pay Chase",
            "entry_type": "transfer",
            "date": "2026-06-10",
            "status": "confirmed",
            "account_movements": [
                {
                    "account_id": checking["id"],
                    "movement_type": "transfer_out",
                    "amount": "200",
                    "currency": "USD",
                },
                {
                    "account_id": credit_account["id"],
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_repayment",
                    "amount": "200",
                    "currency": "USD",
                },
            ],
        },
    )

    assert repayment_response.status_code == 201
    settled_cash_flow = client.get(f"/api/v1/cash-flow-items/{cash_flow_id}").json()
    assert settled_cash_flow["amount"] == "0"
    assert settled_cash_flow["converted_cny_amount"] == "0"
    # The cycle was paid off via a direct credit_repayment movement, so the
    # auto-generated repayment placeholder (no linked_entry_id) is cancelled, not
    # left as a settled-with-no-entry R4① orphan (v2.3.0 评审修补 重要-2).
    assert settled_cash_flow["status"] == "cancelled"
    assert Decimal(client.get(f"/api/v1/accounts/{credit_account['id']}").json()["current_liability"]) == Decimal("0")


def test_recancel_is_idempotent(client) -> None:
    response = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected rent",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": "800",
            "currency": "CNY",
            "expected_date": "2026-06-05",
        },
    )
    item = response.json()

    first = client.post(f"/api/v1/cash-flow-items/{item['id']}/cancel")
    assert first.status_code == 200
    assert first.json()["status"] == "cancelled"

    # Cancel again — must be a 200 idempotent no-op, not a 400.
    second = client.post(f"/api/v1/cash-flow-items/{item['id']}/cancel")
    assert second.status_code == 200
    assert second.json()["status"] == "cancelled"


def test_list_hides_cancelled_by_default(client) -> None:
    create_account(client, balance="0")
    keep = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Keep",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": "100",
            "currency": "CNY",
            "expected_date": "2026-06-05",
        },
    ).json()
    drop = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Drop",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": "200",
            "currency": "CNY",
            "expected_date": "2026-06-06",
        },
    ).json()

    cancel_response = client.post(f"/api/v1/cash-flow-items/{drop['id']}/cancel")
    assert cancel_response.status_code == 200

    default_ids = {row["id"] for row in client.get("/api/v1/cash-flow-items").json()}
    assert keep["id"] in default_ids
    assert drop["id"] not in default_ids

    all_ids = {
        row["id"]
        for row in client.get("/api/v1/cash-flow-items?include_cancelled=true").json()
    }
    assert keep["id"] in all_ids
    assert drop["id"] in all_ids

    cancelled_only = client.get("/api/v1/cash-flow-items?status=cancelled").json()
    cancelled_ids = {row["id"] for row in cancelled_only}
    assert cancelled_ids == {drop["id"]}


def test_settled_cannot_be_cancelled(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)
    item = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Expected salary",
            "direction": "inflow",
            "cash_flow_type": "salary",
            "amount": "1000",
            "currency": "CNY",
            "expected_date": "2026-06-01",
            "account_id": account["id"],
            "category_id": category["id"],
            "status": "confirmed",
        },
    ).json()

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "June salary",
                "entry_type": "single",
                "date": "2026-06-01",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "income",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_in",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )
    assert settle_response.status_code == 200

    cancel_response = client.post(f"/api/v1/cash-flow-items/{item['id']}/cancel")
    assert cancel_response.status_code == 400
    assert "Settled" in cancel_response.json()["detail"]
