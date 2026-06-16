"""v2.2.0 P1 — credit liability single source of truth.

Locks the invariant ``current_liability ≡ Σ(non-voided statement cycle:
statement_amount − paid_amount)`` (PROJECT_PLAN §5.2 公式, D1=甲) end to end:
charge/repayment keep it equal to ``Σcycle``, opening liability must be expressed
as a cycle (the bare ``current_liability`` opening number is rejected), and the
legacy "set actual liability" reconciliation path no longer applies to credit
accounts.
"""
from decimal import Decimal


def _create_account(client, name, account_type="balance", currency="CNY", balance="0"):
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


def _create_credit_account(client, name="Card", currency="CNY"):
    response = client.post(
        "/api/v1/accounts",
        json={"name": name, "type": "credit", "currency": currency},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_category(client, name="Travel", category_type="expense"):
    response = client.post(
        "/api/v1/categories", json={"name": name, "type": category_type}
    )
    assert response.status_code == 201
    return response.json()


def _create_cycle(
    client,
    account_id,
    start="2026-05-01",
    end="2026-05-31",
    statement="2026-06-01",
    due="2026-06-20",
    currency="CNY",
    statement_amount="0",
):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": account_id,
            "cycle_start_date": start,
            "cycle_end_date": end,
            "statement_date": statement,
            "due_date": due,
            "currency": currency,
            "statement_amount": statement_amount,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _liability(client, account_id):
    return Decimal(
        client.get(f"/api/v1/accounts/{account_id}").json()["current_liability"]
    )


def _cycle_total(client, account_id):
    cycles = client.get(
        f"/api/v1/credit-statement-cycles?credit_account_id={account_id}"
    ).json()
    total = Decimal("0")
    for cycle in cycles:
        if cycle["status"] == "voided":
            continue
        total += Decimal(cycle["statement_amount"]) - Decimal(cycle["paid_amount"])
    return total


# --- opening-liability 收口 -------------------------------------------------


def test_create_credit_account_with_nonzero_opening_liability_is_rejected(client) -> None:
    # 病灶 A 收口: a bare opening current_liability on a credit account is now a
    # 422 — opening debt must be expressed as a statement cycle.
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": "Legacy Card",
            "type": "credit",
            "currency": "CNY",
            "current_liability": "1400",
        },
    )
    assert response.status_code == 422
    assert "current_liability" in response.text


def test_create_credit_account_with_zero_liability_succeeds(client) -> None:
    account = _create_credit_account(client, "Fresh Card")
    assert Decimal(account["current_liability"]) == Decimal("0")


def test_opening_liability_via_cycle_drives_current_liability(client) -> None:
    # An opening balance expressed as a cycle's statement_amount is immediately
    # reflected in current_liability through the single source of truth.
    account = _create_credit_account(client, "Card")
    _create_cycle(client, account["id"], statement_amount="600")
    assert _liability(client, account["id"]) == Decimal("600.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])


# --- charge / repayment keep current_liability ≡ Σcycle ---------------------


def test_charge_then_repayment_keeps_liability_equal_to_sum_cycle(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    card = _create_credit_account(client, "Card")
    cycle = _create_cycle(client, card["id"])
    category = _create_category(client)

    # Charge 300.
    charge = client.post(
        "/api/v1/entries",
        json={
            "title": "Dinner",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "300",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": card["id"],
                    "movement_type": "credit_charge",
                    "amount": "300",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert charge.status_code == 201, charge.text
    assert _liability(client, card["id"]) == Decimal("300.00")
    assert _liability(client, card["id"]) == _cycle_total(client, card["id"])

    # Repay 200 — liability tracks Σcycle, not double-decremented.
    repay = client.post(
        "/api/v1/entries",
        json={
            "title": "Pay card",
            "entry_type": "transfer",
            "date": "2026-06-10",
            "status": "confirmed",
            "account_movements": [
                {
                    "account_id": checking["id"],
                    "movement_type": "transfer_out",
                    "amount": "200",
                    "currency": "CNY",
                },
                {
                    "account_id": card["id"],
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_repayment",
                    "amount": "200",
                    "currency": "CNY",
                },
            ],
        },
    )
    assert repay.status_code == 201, repay.text
    # Σcycle = 300 statement − 200 paid = 100; liability must equal it exactly.
    assert _liability(client, card["id"]) == Decimal("100.00")
    assert _liability(client, card["id"]) == _cycle_total(client, card["id"])


def test_void_repayment_restores_liability_to_sum_cycle(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    card = _create_credit_account(client, "Card")
    cycle = _create_cycle(client, card["id"])
    category = _create_category(client)

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
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": card["id"],
                    "movement_type": "credit_charge",
                    "amount": "200",
                    "currency": "CNY",
                }
            ],
        },
    )
    repayment = client.post(
        "/api/v1/entries",
        json={
            "title": "Pay card",
            "entry_type": "transfer",
            "date": "2026-06-10",
            "status": "confirmed",
            "account_movements": [
                {
                    "account_id": checking["id"],
                    "movement_type": "transfer_out",
                    "amount": "200",
                    "currency": "CNY",
                },
                {
                    "account_id": card["id"],
                    "statement_cycle_id": cycle["id"],
                    "movement_type": "credit_repayment",
                    "amount": "200",
                    "currency": "CNY",
                },
            ],
        },
    ).json()
    assert _liability(client, card["id"]) == Decimal("0.00")

    void = client.post(f"/api/v1/entries/{repayment['id']}/void")
    assert void.status_code == 200
    # After void: Σcycle = 200 − 0 = 200; liability re-derived to match.
    assert _liability(client, card["id"]) == Decimal("200.00")
    assert _liability(client, card["id"]) == _cycle_total(client, card["id"])


def test_multiple_cycles_sum_into_liability(client) -> None:
    card = _create_credit_account(client, "Card")
    _create_cycle(
        client,
        card["id"],
        start="2026-04-01",
        end="2026-04-30",
        statement="2026-05-01",
        due="2026-05-20",
        statement_amount="100",
    )
    _create_cycle(
        client,
        card["id"],
        start="2026-05-01",
        end="2026-05-31",
        statement="2026-06-01",
        due="2026-06-20",
        statement_amount="250",
    )
    # 100 + 250 across two open cycles.
    assert _liability(client, card["id"]) == Decimal("350.00")
    assert _liability(client, card["id"]) == _cycle_total(client, card["id"])


# --- credit reconciliation adjustment 收口 ----------------------------------


def test_reconciliation_adjustment_rejected_for_credit_account(client) -> None:
    # The legacy "set actual liability" path would re-introduce drift; credit
    # accounts must correct via cycles instead, so it returns 400.
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")

    response = client.post(
        "/api/v1/reconciliation/adjustments",
        json={"account_id": card["id"], "actual_amount": "1400", "reason": "fix"},
    )
    assert response.status_code == 400
    assert "derived from statement cycles" in response.json()["detail"]
    # Liability untouched: still equals Σcycle.
    assert _liability(client, card["id"]) == Decimal("600.00")


def test_reconciliation_check_credit_account_expected_equals_current(client) -> None:
    # The reconciliation row for a credit account shows expected == current (no
    # phantom drift): both read the single source of truth.
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")

    rows = client.get("/api/v1/reconciliation/accounts").json()["items"]
    credit_row = next(row for row in rows if row["account_id"] == card["id"])
    assert Decimal(credit_row["expected_amount"]) == Decimal("600.00")
    assert Decimal(credit_row["current_amount"]) == Decimal("600.00")
    assert Decimal(credit_row["delta_amount"]) == Decimal("0.00")
    assert credit_row["needs_adjustment"] is False
