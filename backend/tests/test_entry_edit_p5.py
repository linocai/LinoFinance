"""v3.0.0 P5 — PATCH /entries/{id} = void+recreate edit (high-risk matrix).

Editing an entry voids the original (reversing its balance/liability effect and
abandoning its pending reimbursement claims) and recreates a brand-new entry
from the full replacement payload, all in one transaction. These tests pin the
correctness matrix from PROJECT_PLAN §5.3 / §5.5 风险3:
  1. edit amount → account balance & credit ``current_liability≡Σcycle`` stay right
  2. edit a credit charge's date → cycle re-attachment (may land a *different* cycle)
  3. edit a reimbursement entry → old claim abandoned, new claim issued, no double-count
  4. edit a voided entry → rejected
  5. plain expense: move account / category / date happy path
  6. structural-linkage reject (installment source + settled cash-flow product)
plus 404 and failure-atomicity.
"""

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
    assert response.status_code == 201, response.text
    return response.json()


def create_category(client, name="Dining", category_type="expense"):
    response = client.post(
        "/api/v1/categories",
        json={"name": name, "type": category_type},
    )
    assert response.status_code == 201, response.text
    return response.json()


def create_usd_cny_rate(client, rate="6.8", date="2026-05-01"):
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": rate,
            "date": date,
            "source": "manual",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def create_statement_cycle(
    client,
    credit_account_id,
    currency="USD",
    cycle_start_date="2026-05-01",
    cycle_end_date="2026-05-31",
    statement_date="2026-06-01",
    due_date="2026-06-20",
):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account_id,
            "cycle_start_date": cycle_start_date,
            "cycle_end_date": cycle_end_date,
            "statement_date": statement_date,
            "due_date": due_date,
            "currency": currency,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _expense_entry_payload(account, category, amount, currency="CNY", date="2026-05-16", title="Lunch"):
    return {
        "title": title,
        "date": date,
        "status": "confirmed",
        "category_lines": [
            {
                "category_id": category["id"],
                "direction": "expense",
                "amount": amount,
                "currency": currency,
            }
        ],
        "account_movements": [
            {
                "account_id": account["id"],
                "movement_type": "balance_out",
                "amount": amount,
                "currency": currency,
            }
        ],
    }


def _credit_charge_payload(credit_account, category, amount, currency="USD", date="2026-05-16", title="Flight"):
    return {
        "title": title,
        "date": date,
        "status": "confirmed",
        "category_lines": [
            {
                "category_id": category["id"],
                "direction": "expense",
                "amount": amount,
                "currency": currency,
            }
        ],
        "account_movements": [
            {
                "account_id": credit_account["id"],
                "movement_type": "credit_charge",
                "amount": amount,
                "currency": currency,
            }
        ],
    }


def _reimbursable_expense_payload(account, category, amount, expected_date="2026-06-30"):
    return {
        "title": "Taxi",
        "date": "2026-05-16",
        "status": "confirmed",
        "category_lines": [
            {
                "category_id": category["id"],
                "direction": "expense",
                "amount": amount,
                "currency": "CNY",
                "reimbursable_flag": True,
                "reimbursement_payer": "company",
                "reimbursement_expected_date": expected_date,
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
    }


def _balance(client, account_id):
    return client.get(f"/api/v1/accounts/{account_id}").json()["current_balance"]


def _liability(client, account_id):
    return client.get(f"/api/v1/accounts/{account_id}").json()["current_liability"]


def _cycle(client, cycle_id):
    return client.get(f"/api/v1/credit-statement-cycles/{cycle_id}").json()


# --- 1. edit amount → balance correct + returns NEW entry, old one voided -----


def test_edit_amount_updates_balance_and_returns_new_voided_original(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    original = client.post(
        "/api/v1/entries", json=_expense_entry_payload(account, category, "120")
    ).json()
    assert _balance(client, account["id"]) == "880.00"

    patched = client.patch(
        f"/api/v1/entries/{original['id']}",
        json=_expense_entry_payload(account, category, "200", title="Lunch (fixed)"),
    )
    assert patched.status_code == 200, patched.text
    new_entry = patched.json()

    # Replace semantics: a brand-new entry (new id) is returned, still confirmed.
    assert new_entry["id"] != original["id"]
    assert new_entry["status"] == "confirmed"
    assert new_entry["title"] == "Lunch (fixed)"
    assert new_entry["account_movements"][0]["amount"] == "200"

    # Original survives voided (audit); balance reflects only the new 200 charge.
    assert client.get(f"/api/v1/entries/{original['id']}").json()["status"] == "voided"
    assert _balance(client, account["id"]) == "800.00"

    # Ledger list now holds exactly the voided original + the new entry.
    ids = {e["id"]: e["status"] for e in client.get("/api/v1/entries").json()}
    assert ids == {original["id"]: "voided", new_entry["id"]: "confirmed"}


# --- 2a. edit credit charge amount → liability stays ≡ Σcycle ------------------


def test_edit_credit_charge_amount_keeps_liability_equal_to_cycle_sum(client) -> None:
    create_usd_cny_rate(client)
    credit = create_account(client, name="Chase", account_type="credit", currency="USD")
    cycle = create_statement_cycle(client, credit["id"])
    category = create_category(client, name="Flight")

    original = client.post(
        "/api/v1/entries", json=_credit_charge_payload(credit, category, "100")
    ).json()
    assert _liability(client, credit["id"]) == "100.00"
    assert Decimal(_cycle(client, cycle["id"])["statement_amount"]) == Decimal("100")

    patched = client.patch(
        f"/api/v1/entries/{original['id']}",
        json=_credit_charge_payload(credit, category, "60"),
    )
    assert patched.status_code == 200, patched.text

    # Liability recomputed from Σcycle; the single cycle now carries 60.
    assert _liability(client, credit["id"]) == "60.00"
    assert Decimal(_cycle(client, cycle["id"])["statement_amount"]) == Decimal("60")
    # Invariant: stored liability == cycle statement − paid.
    cyc = _cycle(client, cycle["id"])
    assert Decimal(_liability(client, credit["id"])) == Decimal(
        cyc["statement_amount"]
    ) - Decimal(cyc["paid_amount"])


# --- 2b. edit credit charge DATE → re-attaches to a different cycle ------------


def test_edit_credit_charge_date_reattaches_to_a_different_cycle(client) -> None:
    create_usd_cny_rate(client)
    credit = create_account(client, name="Chase", account_type="credit", currency="USD")
    cycle_may = create_statement_cycle(client, credit["id"])  # 2026-05-01..05-31
    cycle_jun = create_statement_cycle(
        client,
        credit["id"],
        cycle_start_date="2026-06-01",
        cycle_end_date="2026-06-30",
        statement_date="2026-07-01",
        due_date="2026-07-20",
    )
    category = create_category(client, name="Flight")

    original = client.post(
        "/api/v1/entries",
        json=_credit_charge_payload(credit, category, "100", date="2026-05-16"),
    ).json()
    # Auto-attached to the May cycle.
    assert original["account_movements"][0]["statement_cycle_id"] == cycle_may["id"]
    assert Decimal(_cycle(client, cycle_may["id"])["statement_amount"]) == Decimal("100")
    assert Decimal(_cycle(client, cycle_jun["id"])["statement_amount"]) == Decimal("0")

    # Move the charge into June → it must re-attach to the June cycle.
    patched = client.patch(
        f"/api/v1/entries/{original['id']}",
        json=_credit_charge_payload(credit, category, "100", date="2026-06-15"),
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["account_movements"][0]["statement_cycle_id"] == cycle_jun["id"]

    # May cycle emptied, June cycle now carries the charge; liability unchanged (100).
    assert Decimal(_cycle(client, cycle_may["id"])["statement_amount"]) == Decimal("0")
    assert Decimal(_cycle(client, cycle_jun["id"])["statement_amount"]) == Decimal("100")
    assert _liability(client, credit["id"]) == "100.00"


# --- 3. edit reimbursement entry → old claim abandoned, new claim, no dup ------


def test_edit_reimbursement_entry_abandons_old_claim_and_issues_new(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client, name="Taxi")

    def reimbursable_payload(amount):
        return {
            "title": "Taxi",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": amount,
                    "currency": "CNY",
                    "reimbursable_flag": True,
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": "2026-06-30",
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
        }

    original = client.post("/api/v1/entries", json=reimbursable_payload("100")).json()

    pending = client.get("/api/v1/reimbursement-claims?status=pending").json()
    assert len(pending) == 1
    assert Decimal(pending[0]["amount"]) == Decimal("100")
    old_claim_id = pending[0]["id"]
    # Dashboard receivable reflects exactly the one pending claim.
    assert Decimal(
        client.get("/api/v1/dashboard/summary").json()["reimbursement_receivable_total_cny"]
    ) == Decimal("100")

    # Edit the reimbursement amount 100 → 150.
    patched = client.patch(
        f"/api/v1/entries/{original['id']}", json=reimbursable_payload("150")
    )
    assert patched.status_code == 200, patched.text

    # Old claim abandoned; a single fresh pending claim of 150 exists.
    assert client.get(f"/api/v1/reimbursement-claims/{old_claim_id}").json()["status"] == "abandoned"
    pending_after = client.get("/api/v1/reimbursement-claims?status=pending").json()
    assert len(pending_after) == 1
    assert pending_after[0]["id"] != old_claim_id
    assert Decimal(pending_after[0]["amount"]) == Decimal("150")

    # Net-worth receivable follows the edit with NO double-count (150, not 250).
    assert Decimal(
        client.get("/api/v1/dashboard/summary").json()["reimbursement_receivable_total_cny"]
    ) == Decimal("150")
    assert _balance(client, account["id"]) == "850.00"


# --- 3b. edit source expense of a FINAL reimbursement claim → rejected ---------
# (v3.0.0 评审 重要-1): a received/abandoned claim makes void+recreate corrupt
# the ledger — void skips FINAL claims, so the source expense reverses while the
# received income entry survives (phantom income) and recreate mints a second
# pending claim (double-counted receivable). Guard must reject BEFORE any change.


def test_edit_source_expense_with_received_claim_is_rejected(client) -> None:
    account = create_account(client, balance="1000")
    expense_category = create_category(client, name="Taxi")
    income_category = create_category(client, name="Reimb income", category_type="income")

    payload = _reimbursable_expense_payload(account, expense_category, "100")
    source = client.post("/api/v1/entries", json=payload).json()
    assert _balance(client, account["id"]) == "900.00"

    claim = client.get("/api/v1/reimbursement-claims?status=pending").json()[0]

    # Mark received → income entry E2 created, money lands back, claim terminal.
    received = client.post(
        f"/api/v1/reimbursement-claims/{claim['id']}/mark-received",
        json={
            "actual_received_date": "2026-06-15",
            "received_account_id": account["id"],
            "entry": {
                "title": "Taxi reimbursed",
                "date": "2026-06-15",
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
        },
    )
    assert received.status_code == 200, received.text
    assert client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()["status"] == "received"
    assert _balance(client, account["id"]) == "1000.00"  # -100 spend +100 reimbursed

    # Editing the SOURCE expense is now blocked — its claim is terminal.
    response = client.patch(f"/api/v1/entries/{source['id']}", json=payload)
    assert response.status_code == 400
    assert "报销" in response.json()["detail"]
    # Nothing rolled back: source still confirmed, received claim + balance intact.
    assert client.get(f"/api/v1/entries/{source['id']}").json()["status"] == "confirmed"
    assert client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()["status"] == "received"
    assert _balance(client, account["id"]) == "1000.00"


def test_edit_source_expense_with_abandoned_claim_is_rejected(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client, name="Taxi")

    payload = _reimbursable_expense_payload(account, category, "100")
    source = client.post("/api/v1/entries", json=payload).json()
    assert _balance(client, account["id"]) == "900.00"

    claim = client.get("/api/v1/reimbursement-claims?status=pending").json()[0]
    abandoned = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/abandon")
    assert abandoned.status_code == 200, abandoned.text
    assert abandoned.json()["status"] == "abandoned"

    response = client.patch(f"/api/v1/entries/{source['id']}", json=payload)
    assert response.status_code == 400
    assert "报销" in response.json()["detail"]
    # Untouched: source still confirmed, claim still abandoned, balance still -100.
    assert client.get(f"/api/v1/entries/{source['id']}").json()["status"] == "confirmed"
    assert client.get(f"/api/v1/reimbursement-claims/{claim['id']}").json()["status"] == "abandoned"
    assert _balance(client, account["id"]) == "900.00"


# --- 4. edit a voided entry → rejected ----------------------------------------


def test_edit_voided_entry_is_rejected(client) -> None:
    account = create_account(client, balance="500")
    category = create_category(client)

    entry = client.post(
        "/api/v1/entries", json=_expense_entry_payload(account, category, "80")
    ).json()
    assert client.post(f"/api/v1/entries/{entry['id']}/void").status_code == 200

    response = client.patch(
        f"/api/v1/entries/{entry['id']}",
        json=_expense_entry_payload(account, category, "90"),
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Voided entries cannot be edited"
    # Balance untouched (still fully rolled back from the void).
    assert _balance(client, account["id"]) == "500.00"


# --- 5. plain expense: move account / category / date happy path ---------------


def test_edit_moves_account_category_and_date(client) -> None:
    src = create_account(client, name="Cash", balance="1000")
    dst = create_account(client, name="Bank", balance="2000")
    cat_a = create_category(client, name="Dining")
    cat_b = create_category(client, name="Books")

    original = client.post(
        "/api/v1/entries",
        json=_expense_entry_payload(src, cat_a, "100", date="2026-05-16"),
    ).json()
    assert _balance(client, src["id"]) == "900.00"

    moved_payload = {
        "title": "Moved",
        "date": "2026-05-20",
        "status": "confirmed",
        "category_lines": [
            {
                "category_id": cat_b["id"],
                "direction": "expense",
                "amount": "70",
                "currency": "CNY",
            }
        ],
        "account_movements": [
            {
                "account_id": dst["id"],
                "movement_type": "balance_out",
                "amount": "70",
                "currency": "CNY",
            }
        ],
    }
    patched = client.patch(f"/api/v1/entries/{original['id']}", json=moved_payload)
    assert patched.status_code == 200, patched.text
    new_entry = patched.json()
    assert new_entry["date"] == "2026-05-20"
    assert new_entry["category_lines"][0]["category_id"] == cat_b["id"]
    assert new_entry["account_movements"][0]["account_id"] == dst["id"]

    # Source restored to full, destination reduced by the new amount.
    assert _balance(client, src["id"]) == "1000.00"
    assert _balance(client, dst["id"]) == "1930.00"


# --- 6. structural-linkage rejects --------------------------------------------


def test_edit_installment_source_entry_is_rejected(client) -> None:
    create_usd_cny_rate(client)
    credit = create_account(client, name="Chase", account_type="credit", currency="USD")
    create_statement_cycle(client, credit["id"])
    category = create_category(client, name="Laptop")

    source = client.post(
        "/api/v1/entries", json=_credit_charge_payload(credit, category, "300")
    ).json()
    plan = client.post(
        "/api/v1/installment-plans",
        json={
            "linked_entry_id": source["id"],
            "credit_account_id": credit["id"],
            "total_amount": "300",
            "currency": "USD",
            "number_of_payments": 3,
            "start_date": "2026-06-01",
        },
    )
    assert plan.status_code == 201, plan.text

    response = client.patch(
        f"/api/v1/entries/{source['id']}",
        json=_credit_charge_payload(credit, category, "250"),
    )
    assert response.status_code == 400
    assert "系统联动" in response.json()["detail"]
    # Original untouched — liability still reflects the 300 charge.
    assert _liability(client, credit["id"]) == "300.00"


def test_edit_settled_cash_flow_product_entry_is_rejected(client) -> None:
    account = create_account(client, name="Bank", balance="1000")
    category = create_category(client, name="Salary", category_type="income")

    item = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Payday",
            "direction": "inflow",
            "cash_flow_type": "salary",
            "amount": "500",
            "currency": "CNY",
            "expected_date": "2026-05-20",
            "account_id": account["id"],
            "category_id": category["id"],
        },
    ).json()

    settle = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "Payday received",
                "date": "2026-05-20",
                "status": "confirmed",
                "category_lines": [
                    {
                        "category_id": category["id"],
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
            }
        },
    )
    assert settle.status_code == 200, settle.text
    product_entry_id = settle.json()["entry"]["id"]

    response = client.patch(
        f"/api/v1/entries/{product_entry_id}",
        json={
            "title": "hacked",
            "date": "2026-05-20",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "income",
                    "amount": "900",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_in",
                    "amount": "900",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 400
    assert "系统联动" in response.json()["detail"]
    # Settlement balance intact (1000 + 500), never bumped to 900.
    assert _balance(client, account["id"]) == "1500.00"


# --- edge: 404 + failure atomicity --------------------------------------------


def test_edit_missing_entry_returns_404(client) -> None:
    account = create_account(client, balance="100")
    category = create_category(client)
    response = client.patch(
        "/api/v1/entries/does-not-exist",
        json=_expense_entry_payload(account, category, "10"),
    )
    assert response.status_code == 404


def test_edit_with_invalid_new_payload_rolls_back_and_keeps_original(client) -> None:
    account = create_account(client, balance="1000")
    category = create_category(client)

    original = client.post(
        "/api/v1/entries", json=_expense_entry_payload(account, category, "120")
    ).json()
    assert _balance(client, account["id"]) == "880.00"

    # New payload has a mismatched category/movement total → recreate raises,
    # the whole transaction (incl. the void half) rolls back.
    bad = client.patch(
        f"/api/v1/entries/{original['id']}",
        json={
            "title": "Bad",
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
    assert bad.status_code == 400
    # Original still confirmed, balance unchanged from before the failed edit.
    assert client.get(f"/api/v1/entries/{original['id']}").json()["status"] == "confirmed"
    assert _balance(client, account["id"]) == "880.00"
