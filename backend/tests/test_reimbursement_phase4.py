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
    assert claim["status"] == "pending"
    assert claim["cash_flow_item_id"] is not None

    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["direction"] == "inflow"
    assert cash_flow["cash_flow_type"] == "reimbursement"
    assert cash_flow["amount"] == "500"
    assert cash_flow["status"] == "expected"
    assert cash_flow["linked_reimbursement_id"] == claim["id"]


def test_draft_reimbursable_entry_is_rejected(client) -> None:
    # v1.4.0: draft status is removed, so a reimbursable entry can no longer be
    # parked as a draft. Sending status=draft is rejected (422) and creates
    # neither a claim nor any balance change.
    account = create_account(client, balance="1000")
    category = create_category(client)

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Client trip",
            "date": "2026-05-16",
            "status": "draft",
            "category_lines": [
                {
                    "category_id": category["id"],
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

    assert response.status_code == 422
    assert client.get("/api/v1/reimbursement-claims").json() == []
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"


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


def test_submit_and_approve_endpoints_are_idempotent_noops(client) -> None:
    # v2.1.0 P2 / D4: the approval ceremony is gone for single-user use, but the
    # submit/approve endpoints are physically retained so old clients don't 404.
    # They must be safe no-ops: the claim stays pending and never picks up a
    # non-three-state value, and the linked cash flow stays expected.
    account = create_account(client, balance="1000")
    category = create_category(client)
    create_reimbursable_entry(client, account, category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    submit_response = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/submit")
    assert submit_response.status_code == 200
    assert submit_response.json()["status"] == "pending"

    approve_response = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/approve")
    assert approve_response.status_code == 200
    approved_claim = approve_response.json()
    assert approved_claim["status"] == "pending"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{approved_claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "expected"


def test_reject_endpoint_maps_to_abandon(client) -> None:
    # v2.1.0 P2 / D4: single-user has no "rejected" semantics, so the retained
    # reject endpoint is mapped to abandon (pending -> abandoned), cancelling the
    # linked cash flow. It must never write the legacy "rejected" value.
    account = create_account(client, balance="1000")
    category = create_category(client)
    create_reimbursable_entry(client, account, category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    reject_response = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/reject")
    assert reject_response.status_code == 200
    assert reject_response.json()["status"] == "abandoned"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "cancelled"


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


def test_settle_on_reimbursement_linked_cash_flow_is_rejected(client) -> None:
    """Settling a claim-linked receivable directly is blocked (audit 1.3)."""
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Reimbursement Income", category_type="income")
    create_reimbursable_entry(client, account, expense_category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]
    cash_flow_id = claim["cash_flow_item_id"]

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{cash_flow_id}/settle",
        json={
            "entry": {
                "title": "Sneaky settle",
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

    assert settle_response.status_code == 400
    assert "mark-received" in settle_response.json()["detail"]
    # The item is untouched and no entry was created by the rejected settle.
    cash_flow = client.get(f"/api/v1/cash-flow-items/{cash_flow_id}").json()
    assert cash_flow["status"] == "expected"
    assert cash_flow["linked_entry_id"] is None
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "500.00"


def test_blocked_settle_then_mark_received_yields_single_income_entry(client) -> None:
    """After the settle bypass is blocked, mark-received still produces exactly
    one income entry — the double-count regression guard (audit 1.3)."""
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Reimbursement Income", category_type="income")
    create_reimbursable_entry(client, account, expense_category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]
    cash_flow_id = claim["cash_flow_item_id"]

    # Bypass attempt is rejected (no entry created).
    blocked = client.post(
        f"/api/v1/cash-flow-items/{cash_flow_id}/settle",
        json={
            "entry": {
                "title": "Sneaky settle",
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
    assert blocked.status_code == 400

    entries_before = client.get("/api/v1/entries").json()

    # The sanctioned path generates exactly one income entry.
    receive = client.post(
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
    assert receive.status_code == 200
    income_entry_id = receive.json()["entry"]["id"]

    entries_after = client.get("/api/v1/entries").json()
    new_entries = [e for e in entries_after if e["id"] not in {x["id"] for x in entries_before}]
    assert len(new_entries) == 1
    assert new_entries[0]["id"] == income_entry_id

    cash_flow = client.get(f"/api/v1/cash-flow-items/{cash_flow_id}").json()
    assert cash_flow["status"] == "settled"
    assert cash_flow["linked_entry_id"] == income_entry_id
    assert receive.json()["reimbursement_claim"]["status"] == "received"
    # Balance returns to its pre-expense level: -500 (expense) +500 (received).
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"


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

    pending_claims = client.get("/api/v1/reimbursement-claims?status=pending").json()
    received_claims = client.get("/api/v1/reimbursement-claims?status=received").json()

    assert len(pending_claims) == 1
    assert received_claims == []
    assert Decimal(pending_claims[0]["converted_cny_amount"]) == Decimal("500")


# ---------------------------------------------------------------------------
# v2.1.0 P2 — three-state reimbursement (pending / received / abandoned)
# ---------------------------------------------------------------------------


def test_confirmed_reimbursable_entry_defaults_claim_to_pending(client) -> None:
    # When a reimbursable line omits an explicit status, the auto-created claim
    # defaults to "pending" and its cash flow to "expected".
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
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": "2026-06-10",
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
    claim = client.get("/api/v1/reimbursement-claims").json()[0]
    assert claim["status"] == "pending"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "expected"


def test_create_manual_claim_with_legacy_status_is_rejected(client) -> None:
    # The status pattern is collapsed to ^(pending|received|abandoned)$; a legacy
    # value such as "submitted" is now rejected at the schema layer (422) and no
    # claim is created.
    account = create_account(client, balance="1000")
    category = create_category(client)
    entry = create_plain_expense_entry(client, account, category)
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
            "status": "submitted",
        },
    )
    assert response.status_code == 422
    assert client.get("/api/v1/reimbursement-claims").json() == []


def test_create_reimbursable_line_with_legacy_status_is_rejected(client) -> None:
    # A reimbursable entry line may only pre-set status "pending"; a legacy value
    # is rejected (422) and creates neither a claim nor a balance change.
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
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": "2026-06-10",
                    "reimbursement_status": "approved",
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
    assert response.status_code == 422
    assert client.get("/api/v1/reimbursement-claims").json() == []
    assert client.get(f"/api/v1/accounts/{account['id']}").json()["current_balance"] == "1000.00"


def test_abandon_endpoint_sets_abandoned_and_cancels_cash_flow(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)
    create_reimbursable_entry(client, account, category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    abandon = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/abandon")
    assert abandon.status_code == 200
    assert abandon.json()["status"] == "abandoned"
    cash_flow = client.get(f"/api/v1/cash-flow-items/{claim['cash_flow_item_id']}").json()
    assert cash_flow["status"] == "cancelled"


def test_mark_received_without_matching_movement_is_rejected(client) -> None:
    # mark-received requires the income entry to carry a matching balance_in
    # movement; omitting it fails with 400 and leaves the claim pending.
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Reimbursement Income", category_type="income")
    create_reimbursable_entry(client, account, expense_category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    response = client.post(
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
                "account_movements": [],
            },
        },
    )
    assert response.status_code == 400
    assert "matching balance_in movement" in response.json()["detail"]
    still_pending = client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()
    assert still_pending["status"] == "pending"


def test_received_claim_is_final_and_cannot_be_abandoned(client) -> None:
    # received is a final state; attempting to abandon it fails (400).
    account = create_account(client, balance="1000")
    expense_category = create_category(client)
    income_category = create_category(client, name="Reimbursement Income", category_type="income")
    create_reimbursable_entry(client, account, expense_category)
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    receive = client.post(
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
    assert receive.status_code == 200
    assert receive.json()["reimbursement_claim"]["status"] == "received"

    abandon = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/abandon")
    assert abandon.status_code == 400
