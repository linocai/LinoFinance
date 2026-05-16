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


def create_category(client, name="Dining", category_type="expense"):
    response = client.post(
        "/api/v1/categories",
        json={
            "name": name,
            "type": category_type,
        },
    )
    assert response.status_code == 201
    return response.json()


def create_usd_cny_rate(client):
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "6.8",
            "date": "2026-05-16",
            "source": "manual",
        },
    )
    assert response.status_code == 201
    return response.json()


def create_statement_cycle(client, credit_account_id, currency="USD"):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account_id,
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": currency,
        },
    )
    assert response.status_code == 201
    return response.json()


def test_draft_entry_does_not_change_balance_until_confirmed(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Lunch",
            "date": "2026-05-16",
            "status": "draft",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "120",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "120",
                    "currency": "CNY",
                }
            ],
        },
    )

    assert response.status_code == 201
    entry = response.json()
    assert entry["status"] == "draft"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"

    confirm_response = client.post(f"/api/v1/entries/{entry['id']}/confirm")

    assert confirm_response.status_code == 200
    assert confirm_response.json()["status"] == "confirmed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "880.00"


def test_confirmed_entry_changes_balance_immediately(client) -> None:
    account = create_account(client, balance="500")
    category = create_category(client)

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Coffee",
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
    )

    assert response.status_code == 201
    assert response.json()["status"] == "confirmed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "470.00"


def test_usd_credit_charge_uses_manual_rate_and_increases_liability(client) -> None:
    create_usd_cny_rate(client)
    account = create_account(client, name="Chase Credit", account_type="credit", currency="USD")
    create_statement_cycle(client, account["id"])
    category = create_category(client, name="Flight")

    response = client.post(
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
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "credit_charge",
                    "amount": "100",
                    "currency": "USD",
                }
            ],
        },
    )

    assert response.status_code == 201
    entry = response.json()
    assert entry["category_lines"][0]["converted_cny_amount"] == "680"
    assert entry["account_movements"][0]["converted_cny_amount"] == "680"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_liability"] == "100.00"


def test_v1_currency_paths_and_payload_conversion_are_strict(client) -> None:
    unsupported_account = client.post(
        "/api/v1/accounts",
        json={
            "name": "EUR Wallet",
            "type": "balance",
            "currency": "EUR",
        },
    )
    assert unsupported_account.status_code == 400
    assert unsupported_account.json()["detail"] == "Unsupported currency for V1"

    unsupported_pair = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "USD",
            "rate": "1",
            "date": "2026-05-16",
            "source": "manual",
        },
    )
    assert unsupported_pair.status_code == 400
    assert unsupported_pair.json()["detail"] == "V1 currency rates must convert a non-CNY currency to CNY"

    account = create_account(client, balance="1000")
    category = create_category(client)
    bad_converted_amount = client.post(
        "/api/v1/entries",
        json={
            "title": "Bad converted amount",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "100",
                    "currency": "CNY",
                    "converted_cny_amount": "99",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "100",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert bad_converted_amount.status_code == 400
    assert bad_converted_amount.json()["detail"] == "converted_cny_amount does not match the exchange rate"


def test_explicit_exchange_rate_must_be_valid_for_entry_date_and_currency(client) -> None:
    future_rate = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "6.9",
            "date": "2026-06-01",
            "source": "manual",
        },
    ).json()
    usd_account = create_account(client, name="USD Wallet", currency="USD")
    usd_category = create_category(client, name="USD Dining")

    future_rate_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Future-rate expense",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": usd_category["id"],
                    "direction": "expense",
                    "amount": "10",
                    "currency": "USD",
                    "exchange_rate_id": future_rate["id"],
                }
            ],
            "account_movements": [
                {
                    "account_id": usd_account["id"],
                    "movement_type": "balance_out",
                    "amount": "10",
                    "currency": "USD",
                    "exchange_rate_id": future_rate["id"],
                }
            ],
        },
    )
    assert future_rate_response.status_code == 400
    assert future_rate_response.json()["detail"] == "Currency rate cannot be dated after the entry date"

    cny_account = create_account(client, name="CNY Wallet")
    cny_category = create_category(client, name="CNY Dining")
    cny_with_rate_response = client.post(
        "/api/v1/entries",
        json={
            "title": "CNY with rate",
            "date": "2026-06-02",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": cny_category["id"],
                    "direction": "expense",
                    "amount": "10",
                    "currency": "CNY",
                    "exchange_rate_id": future_rate["id"],
                }
            ],
            "account_movements": [
                {
                    "account_id": cny_account["id"],
                    "movement_type": "balance_out",
                    "amount": "10",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert cny_with_rate_response.status_code == 400
    assert cny_with_rate_response.json()["detail"] == "CNY amounts cannot use an exchange rate"


def test_confirmed_entry_rejects_mismatched_category_and_movement_totals(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Bad split",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "120",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "110",
                    "currency": "CNY",
                }
            ],
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Expense category total must match spending movements"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"


def test_void_confirmed_entry_rolls_back_balance(client) -> None:
    account = create_account(client, balance="500")
    category = create_category(client)
    entry_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Groceries",
            "date": "2026-05-16",
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
    entry = entry_response.json()
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "420.00"

    void_response = client.post(f"/api/v1/entries/{entry['id']}/void")

    assert void_response.status_code == 200
    assert void_response.json()["status"] == "voided"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "500.00"


def test_dashboard_summary_uses_backend_balances_and_status_counts(client) -> None:
    create_usd_cny_rate(client)
    create_account(client, balance="1000")
    credit_account = create_account(
        client,
        name="Chase Credit",
        account_type="credit",
        currency="USD",
    )
    create_statement_cycle(client, credit_account["id"])
    category = create_category(client)

    client.post(
        "/api/v1/entries",
        json={
            "title": "Draft lunch",
            "date": "2026-05-16",
            "status": "draft",
        },
    )
    client.post(
        "/api/v1/entries",
        json={
            "title": "Card dinner",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "50",
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "50",
                    "currency": "USD",
                }
            ],
        },
    )

    summary_response = client.get("/api/v1/dashboard/summary")

    assert summary_response.status_code == 200
    summary = summary_response.json()
    assert Decimal(summary["balance_total_cny"]) == Decimal("1000")
    assert Decimal(summary["credit_liability_total_cny"]) == Decimal("340")
    assert Decimal(summary["net_worth_cny"]) == Decimal("660")
    assert summary["draft_entry_count"] == 1
    assert summary["confirmed_entry_count"] == 1
    assert summary["voided_entry_count"] == 0
