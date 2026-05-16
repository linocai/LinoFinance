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


def create_category(client, name="Travel", category_type="expense"):
    response = client.post("/api/v1/categories", json={"name": name, "type": category_type})
    assert response.status_code == 201
    return response.json()


def create_reimbursable_entry(client, account, expense_category, status="confirmed"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Client trip",
            "date": "2026-05-16",
            "status": status,
            "category_lines": [
                {
                    "category_id": expense_category["id"],
                    "direction": "expense",
                    "amount": "500",
                    "currency": "CNY",
                    "reimbursable_flag": True,
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": "2026-06-10",
                    "reimbursement_status": "submitted",
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
    )
    assert response.status_code == 201
    return response.json()


def create_plain_expense_entry(client, account, expense_category, amount="500"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Client dinner",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": expense_category["id"],
                    "direction": "expense",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_confirmed_reimbursable_entry_creates_claim_and_future_cash_flow(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    entry = create_reimbursable_entry(client, account, category)

    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "500.00"

    claims = client.get("/api/v1/reimbursement-claims").json()
    assert len(claims) == 1
    claim = claims[0]
    assert claim["linked_entry_id"] == entry["id"]
    assert claim["linked_entry_line_id"] == entry["category_lines"][0]["id"]
    assert claim["amount"] == "500"
    assert claim["currency"] == "CNY"
    assert claim["payer"] == "company"
    assert claim["expected_date"] == "2026-06-10"
    assert claim["status"] == "submitted"
    assert claim["cash_flow_item_id"] is not None

    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["direction"] == "inflow"
    assert cash_flow["cash_flow_type"] == "reimbursement"
    assert cash_flow["amount"] == "500"
    assert cash_flow["status"] == "expected"
    assert cash_flow["linked_reimbursement_id"] == claim["id"]


def test_draft_reimbursable_entry_creates_claim_only_after_confirm(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    entry = create_reimbursable_entry(client, account, category, status="draft")

    assert client.get("/api/v1/reimbursement-claims").json() == []
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"

    confirm_response = client.post(f"/api/v1/entries/{entry['id']}/confirm")

    assert confirm_response.status_code == 200
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "500.00"
    claims = client.get("/api/v1/reimbursement-claims").json()
    assert len(claims) == 1
    assert claims[0]["linked_entry_id"] == entry["id"]


def test_confirmed_reimbursable_entry_requires_expected_date(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    response = client.post(
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
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Reimbursable lines require reimbursement_expected_date"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"
    assert client.get("/api/v1/reimbursement-claims").json() == []


def test_approve_claim_marks_reimbursement_cash_flow_confirmed(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    create_reimbursable_entry(client, account, category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    approve_response = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/approve")

    assert approve_response.status_code == 200
    approved_claim = approve_response.json()
    assert approved_claim["status"] == "approved"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{approved_claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "confirmed"


def test_mark_reimbursement_received_creates_income_entry_and_settles_cash_flow(client) -> None:
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Reimbursement Income", category_type="income")
    create_reimbursable_entry(client, account, expense_category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    receive_response = client.post(
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

    assert receive_response.status_code == 200
    result = receive_response.json()
    assert result["reimbursement_claim"]["status"] == "received"
    assert result["reimbursement_claim"]["received_entry_id"] == result["entry"]["id"]
    assert result["entry"]["status"] == "confirmed"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"

    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "settled"
    assert cash_flow["linked_entry_id"] == result["entry"]["id"]


def test_void_original_reimbursable_entry_abandons_claim_and_cancels_cash_flow(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    entry = create_reimbursable_entry(client, account, category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    void_response = client.post(f"/api/v1/entries/{entry['id']}/void")

    assert void_response.status_code == 200
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"
    abandoned_claim = client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()
    assert abandoned_claim["status"] == "abandoned"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "cancelled"


def test_manual_claim_rejects_duplicate_linked_entry_line(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    entry = create_reimbursable_entry(client, account, category)
    line = entry["category_lines"][0]

    response = client.post(
        "/api/v1/reimbursement-claims",
        json={
            "linked_entry_id": entry["id"],
            "linked_entry_line_id": line["id"],
            "amount": "500",
            "currency": "CNY",
            "payer": "company",
            "expected_date": "2026-06-10",
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Reimbursement claim already exists for linked expense line"


def test_manual_claim_must_match_confirmed_expense_line(client) -> None:
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Refund Income", category_type="income")
    expense_entry = create_plain_expense_entry(client, account, expense_category)

    amount_mismatch = client.post(
        "/api/v1/reimbursement-claims",
        json={
            "linked_entry_id": expense_entry["id"],
            "linked_entry_line_id": expense_entry["category_lines"][0]["id"],
            "amount": "499",
            "currency": "CNY",
            "payer": "company",
            "expected_date": "2026-06-10",
        },
    )
    assert amount_mismatch.status_code == 400
    assert amount_mismatch.json()["detail"] == "Reimbursement amount must match linked expense line"

    income_entry = client.post(
        "/api/v1/entries",
        json={
            "title": "Refund",
            "date": "2026-05-17",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": income_category["id"],
                    "direction": "income",
                    "amount": "100",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_in",
                    "amount": "100",
                    "currency": "CNY",
                }
            ],
        },
    ).json()

    income_line_response = client.post(
        "/api/v1/reimbursement-claims",
        json={
            "linked_entry_id": income_entry["id"],
            "linked_entry_line_id": income_entry["category_lines"][0]["id"],
            "amount": "100",
            "currency": "CNY",
            "payer": "company",
            "expected_date": "2026-06-10",
        },
    )
    assert income_line_response.status_code == 400
    assert income_line_response.json()["detail"] == "Reimbursement claims must link an expense line"


def test_reimbursement_center_can_filter_by_status(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    create_reimbursable_entry(client, account, category)

    submitted_claims = client.get("/api/v1/reimbursement-claims?status=submitted").json()
    approved_claims = client.get("/api/v1/reimbursement-claims?status=approved").json()

    assert len(submitted_claims) == 1
    assert approved_claims == []
    assert Decimal(submitted_claims[0]["converted_cny_amount"]) == Decimal("500")
