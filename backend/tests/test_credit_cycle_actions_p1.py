"""v2.3.0 P1 — credit statement cycle correction actions.

Covers the new ``PATCH /credit-statement-cycles/{id}`` + ``/mark-paid`` +
``/void`` endpoints. Locks the core invariant ``current_liability ≡
Σ(non-voided cycle: statement_amount − paid_amount)`` (PROJECT_PLAN §5 D1=甲)
across every mutation, plus the linked-repayment-cash-flow sync, and the
failure paths (paid>statement, overlap, voided re-edit, missing cycle).
"""
from decimal import Decimal


def _create_credit_account(client, name="Card", currency="CNY"):
    response = client.post(
        "/api/v1/accounts",
        json={"name": name, "type": "credit", "currency": currency},
    )
    assert response.status_code == 201, response.text
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


def _cash_flow(client, item_id):
    response = client.get(f"/api/v1/cash-flow-items/{item_id}")
    assert response.status_code == 200, response.text
    return response.json()


# --- PATCH edit -------------------------------------------------------------


def test_patch_statement_amount_drives_liability(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    assert _liability(client, account["id"]) == Decimal("600.00")

    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"statement_amount": "1076.33"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert Decimal(body["statement_amount"]) == Decimal("1076.33")
    assert Decimal(body["remaining_amount"]) == Decimal("1076.33")
    # Liability immediately tracks the new Σcycle.
    assert _liability(client, account["id"]) == Decimal("1076.33")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])


def test_patch_paid_amount_reduces_liability_and_syncs_cash_flow(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    linked_id = cycle["linked_cash_flow_item_id"]
    assert linked_id is not None
    assert Decimal(_cash_flow(client, linked_id)["amount"]) == Decimal("600.00")

    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"paid_amount": "250"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert Decimal(body["paid_amount"]) == Decimal("250.00")
    assert Decimal(body["remaining_amount"]) == Decimal("350.00")
    assert body["status"] == "partially_paid"
    # Liability = 600 − 250 = 350.
    assert _liability(client, account["id"]) == Decimal("350.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])
    # Linked repayment cash flow re-synced to the new remaining.
    assert Decimal(_cash_flow(client, linked_id)["amount"]) == Decimal("350.00")


def test_patch_dates_succeeds_and_preserves_invariant(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="400")
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={
            "cycle_start_date": "2026-04-01",
            "cycle_end_date": "2026-04-30",
            "statement_date": "2026-05-01",
            "due_date": "2026-05-20",
        },
    )
    assert response.status_code == 200, response.text
    assert response.json()["cycle_start_date"] == "2026-04-01"
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])


def test_patch_paid_greater_than_statement_rejected(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"paid_amount": "700"},
    )
    assert response.status_code == 400
    assert "Paid amount" in response.json()["detail"]
    # Untouched.
    assert _liability(client, account["id"]) == Decimal("600.00")


def test_patch_lowering_statement_below_paid_rejected(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"paid_amount": "500"},
    )
    # Now lowering statement below the already-paid 500 must fail.
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"statement_amount": "400"},
    )
    assert response.status_code == 400


def test_patch_into_overlap_rejected(client) -> None:
    account = _create_credit_account(client)
    _create_cycle(
        client,
        account["id"],
        start="2026-04-01",
        end="2026-04-30",
        statement="2026-05-01",
        due="2026-05-20",
        statement_amount="100",
    )
    later = _create_cycle(
        client,
        account["id"],
        start="2026-05-01",
        end="2026-05-31",
        statement="2026-06-01",
        due="2026-06-20",
        statement_amount="200",
    )
    # Drag later cycle back into the first cycle's interval.
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{later['id']}",
        json={"cycle_start_date": "2026-04-15"},
    )
    assert response.status_code == 400
    assert "overlaps" in response.json()["detail"]


def test_patch_same_cycle_unchanged_dates_no_self_overlap(client) -> None:
    # Editing only the amount must not flag the cycle as overlapping itself.
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="100")
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"statement_amount": "150"},
    )
    assert response.status_code == 200, response.text


def test_patch_missing_cycle_returns_404(client) -> None:
    response = client.patch(
        "/api/v1/credit-statement-cycles/does-not-exist",
        json={"statement_amount": "100"},
    )
    assert response.status_code == 404


# --- mark-paid --------------------------------------------------------------


def test_mark_paid_zeroes_remaining_and_reduces_liability(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    linked_id = cycle["linked_cash_flow_item_id"]

    response = client.post(
        f"/api/v1/credit-statement-cycles/{cycle['id']}/mark-paid"
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "paid"
    assert Decimal(body["paid_amount"]) == Decimal("600.00")
    assert Decimal(body["remaining_amount"]) == Decimal("0.00")
    # That cycle contributes 0 to liability now.
    assert _liability(client, account["id"]) == Decimal("0.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])
    # Linked repayment cash flow settled to 0.
    linked = _cash_flow(client, linked_id)
    assert linked["status"] == "settled"
    assert Decimal(linked["amount"]) == Decimal("0.00")


def test_mark_paid_on_voided_cycle_rejected(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    client.post(f"/api/v1/credit-statement-cycles/{cycle['id']}/void")
    response = client.post(
        f"/api/v1/credit-statement-cycles/{cycle['id']}/mark-paid"
    )
    assert response.status_code == 400


def test_mark_paid_missing_cycle_returns_404(client) -> None:
    response = client.post(
        "/api/v1/credit-statement-cycles/nope/mark-paid"
    )
    assert response.status_code == 404


# --- void -------------------------------------------------------------------


def test_void_excludes_cycle_from_liability(client) -> None:
    account = _create_credit_account(client)
    keep = _create_cycle(
        client,
        account["id"],
        start="2026-04-01",
        end="2026-04-30",
        statement="2026-05-01",
        due="2026-05-20",
        statement_amount="100",
    )
    drop = _create_cycle(
        client,
        account["id"],
        start="2026-05-01",
        end="2026-05-31",
        statement="2026-06-01",
        due="2026-06-20",
        statement_amount="250",
    )
    assert _liability(client, account["id"]) == Decimal("350.00")

    response = client.post(
        f"/api/v1/credit-statement-cycles/{drop['id']}/void"
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "voided"
    # Only the kept cycle counts now.
    assert _liability(client, account["id"]) == Decimal("100.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])
    # Linked cash flow cancelled.
    linked_id = drop["linked_cash_flow_item_id"]
    if linked_id is not None:
        assert _cash_flow(client, linked_id)["status"] == "cancelled"
    _ = keep


def test_void_is_idempotent(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    first = client.post(f"/api/v1/credit-statement-cycles/{cycle['id']}/void")
    assert first.status_code == 200
    second = client.post(f"/api/v1/credit-statement-cycles/{cycle['id']}/void")
    assert second.status_code == 200
    assert second.json()["status"] == "voided"
    assert _liability(client, account["id"]) == Decimal("0.00")


def test_edit_voided_cycle_rejected(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    client.post(f"/api/v1/credit-statement-cycles/{cycle['id']}/void")
    response = client.patch(
        f"/api/v1/credit-statement-cycles/{cycle['id']}",
        json={"statement_amount": "100"},
    )
    assert response.status_code == 400


def test_void_missing_cycle_returns_404(client) -> None:
    response = client.post("/api/v1/credit-statement-cycles/nope/void")
    assert response.status_code == 404
