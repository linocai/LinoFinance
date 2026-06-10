def create_account(client, name="Chase Credit", account_type="credit", currency="USD", balance="0"):
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


def create_category(client, name="Travel", category_type="expense"):
    response = client.post(
        "/api/v1/categories",
        json={"name": name, "type": category_type},
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
            "date": "2026-05-01",
            "source": "manual",
        },
    )
    assert response.status_code == 201
    return response.json()


def create_cycle(client, account_id, start="2026-05-01", end="2026-05-31"):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": account_id,
            "cycle_start_date": start,
            "cycle_end_date": end,
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "USD",
        },
    )
    assert response.status_code == 201
    return response.json()


def test_create_and_list_credit_statement_cycle(client) -> None:
    account = create_account(client)

    cycle = create_cycle(client, account["id"])

    assert cycle["credit_account_id"] == account["id"]
    assert cycle["statement_amount"] == "0"
    assert cycle["paid_amount"] == "0"
    assert cycle["remaining_amount"] == "0"
    assert cycle["status"] == "open"

    list_response = client.get(f"/api/v1/credit-statement-cycles?credit_account_id={account['id']}")
    assert list_response.status_code == 200
    assert [item["id"] for item in list_response.json()] == [cycle["id"]]


def test_statement_cycle_requires_credit_account_and_matching_currency(client) -> None:
    balance_account = create_account(
        client,
        name="Checking",
        account_type="balance",
        currency="CNY",
    )
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": balance_account["id"],
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "CNY",
        },
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Statement cycles can only be created for credit accounts"

    credit_account = create_account(client)
    mismatch_response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account["id"],
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "CNY",
        },
    )
    assert mismatch_response.status_code == 400
    assert mismatch_response.json()["detail"] == "Statement cycle currency must match credit account currency"


def test_credit_charge_auto_assigns_matching_cycle_and_updates_statement_amount(client) -> None:
    create_usd_cny_rate(client)
    credit_account = create_account(client)
    cycle = create_cycle(client, credit_account["id"])
    category = create_category(client)

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
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "100",
                    "currency": "USD",
                }
            ],
        },
    )

    assert response.status_code == 201
    movement = response.json()["account_movements"][0]
    assert movement["statement_cycle_id"] == cycle["id"]
    assert client.get(f"/api/v1/accounts/{credit_account['id']}").json()["current_liability"] == "100.00"

    cycle_response = client.get(f"/api/v1/credit-statement-cycles/{cycle['id']}")
    assert cycle_response.status_code == 200
    updated_cycle = cycle_response.json()
    assert updated_cycle["statement_amount"] == "100"
    assert updated_cycle["paid_amount"] == "0"
    assert updated_cycle["remaining_amount"] == "100"


def test_credit_charge_without_matching_cycle_is_rejected(client) -> None:
    create_usd_cny_rate(client)
    credit_account = create_account(client)
    category = create_category(client)

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Late flight",
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
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "100",
                    "currency": "USD",
                }
            ],
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Credit charge requires a matching statement cycle"


def test_credit_repayment_updates_cycle_paid_amount_and_account_balances(client) -> None:
    create_usd_cny_rate(client)
    checking = create_account(
        client,
        name="Checking",
        account_type="balance",
        currency="USD",
        balance="500",
    )
    credit_account = create_account(client)
    cycle = create_cycle(client, credit_account["id"])
    category = create_category(client)

    charge_response = client.post(
        "/api/v1/entries",
        json={
            "title": "Hotel",
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
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_charge",
                    "amount": "200",
                    "currency": "USD",
                }
            ],
        },
    )
    assert charge_response.status_code == 201

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
    assert client.get(f"/api/v1/accounts/{checking['id']}").json()["current_balance"] == "300.00"
    assert client.get(f"/api/v1/accounts/{credit_account['id']}").json()["current_liability"] == "0.00"

    updated_cycle = client.get(f"/api/v1/credit-statement-cycles/{cycle['id']}").json()
    assert updated_cycle["statement_amount"] == "200"
    assert updated_cycle["paid_amount"] == "200"
    assert updated_cycle["remaining_amount"] == "0"
    assert updated_cycle["status"] == "paid"


def test_void_credit_repayment_rolls_cycle_and_balances_back(client) -> None:
    create_usd_cny_rate(client)
    checking = create_account(
        client,
        name="Checking",
        account_type="balance",
        currency="USD",
        balance="500",
    )
    credit_account = create_account(client)
    cycle = create_cycle(client, credit_account["id"])
    category = create_category(client)

    client.post(
        "/api/v1/entries",
        json={
            "title": "Hotel",
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
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_charge",
                    "amount": "200",
                    "currency": "USD",
                }
            ],
        },
    )
    repayment = client.post(
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
    ).json()

    void_response = client.post(f"/api/v1/entries/{repayment['id']}/void")

    assert void_response.status_code == 200
    assert client.get(f"/api/v1/accounts/{checking['id']}").json()["current_balance"] == "500.00"
    assert client.get(f"/api/v1/accounts/{credit_account['id']}").json()["current_liability"] == "200.00"

    updated_cycle = client.get(f"/api/v1/credit-statement-cycles/{cycle['id']}").json()
    assert updated_cycle["statement_amount"] == "200"
    assert updated_cycle["paid_amount"] == "0"
    assert updated_cycle["remaining_amount"] == "200"


def _post_cycle(client, account_id, start, end, statement, due):
    return client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": account_id,
            "cycle_start_date": start,
            "cycle_end_date": end,
            "statement_date": statement,
            "due_date": due,
            "currency": "USD",
        },
    )


def test_overlapping_statement_cycle_is_rejected(client) -> None:
    # P5 / audit 2.6: a new cycle whose [start, end] interval overlaps an
    # existing cycle for the same credit account must be rejected, so the
    # consumption auto-assignment (cycle_start_date desc) never mis-attributes.
    account = create_account(client)
    first = _post_cycle(client, account["id"], "2026-05-01", "2026-05-31", "2026-06-01", "2026-06-20")
    assert first.status_code == 201

    # Overlaps the first cycle (2026-05-15 falls inside 2026-05-01..2026-05-31).
    overlap = _post_cycle(client, account["id"], "2026-05-15", "2026-06-15", "2026-06-16", "2026-07-05")
    assert overlap.status_code == 400
    assert "overlap" in overlap.json()["detail"].lower()


def test_adjacent_non_overlapping_statement_cycles_are_allowed(client) -> None:
    # Same account, back-to-back non-overlapping windows must both succeed.
    account = create_account(client)
    first = _post_cycle(client, account["id"], "2026-05-01", "2026-05-31", "2026-06-01", "2026-06-20")
    assert first.status_code == 201

    second = _post_cycle(client, account["id"], "2026-06-01", "2026-06-30", "2026-07-01", "2026-07-20")
    assert second.status_code == 201

    cycles = client.get(
        f"/api/v1/credit-statement-cycles?credit_account_id={account['id']}"
    ).json()
    assert len(cycles) == 2


def test_overlap_check_scoped_to_same_account(client) -> None:
    # A cycle on a different credit account with the same dates is fine.
    account_a = create_account(client, name="Card A")
    account_b = create_account(client, name="Card B")
    first = _post_cycle(client, account_a["id"], "2026-05-01", "2026-05-31", "2026-06-01", "2026-06-20")
    assert first.status_code == 201

    same_dates_other_account = _post_cycle(
        client, account_b["id"], "2026-05-01", "2026-05-31", "2026-06-01", "2026-06-20"
    )
    assert same_dates_other_account.status_code == 201
