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


def _cycle(client, cycle_id):
    response = client.get(f"/api/v1/credit-statement-cycles/{cycle_id}")
    assert response.status_code == 200, response.text
    return response.json()


# --- PATCH edit -------------------------------------------------------------


def test_patch_statement_amount_drives_liability(client) -> None:
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    linked_id = cycle["linked_cash_flow_item_id"]
    assert linked_id is not None
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
    # Linked repayment cash flow amount tracks the new remaining (建议-1 补测).
    assert Decimal(_cash_flow(client, linked_id)["amount"]) == Decimal("1076.33")


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
    # Linked repayment cash flow cancelled to 0 — the future repayment no longer
    # needs fulfilling. mark-paid has no linked entry, so the placeholder is
    # cancelled (not left as a settled-with-no-entry R4① orphan); v2.3.0 评审修补 重要-2.
    linked = _cash_flow(client, linked_id)
    assert linked["status"] == "cancelled"
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


# --- v2.3.0 评审修补 -------------------------------------------------------------


def _create_category(client, name="Travel", category_type="expense"):
    response = client.post(
        "/api/v1/categories",
        json={"name": name, "type": category_type},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _credit_charge_entry(client, account_id, category_id, *, date, amount="50"):
    """Auto-assign credit charge (omit statement_cycle_id) — the ledger resolves
    the covering cycle. Returns the raw POST /entries response."""
    return client.post(
        "/api/v1/entries",
        json={
            "title": "Charge",
            "date": date,
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
                    "movement_type": "credit_charge",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
        },
    )


def test_voided_cycle_does_not_absorb_new_charge(client) -> None:
    """重要-1: after voiding a cycle, a charge in that interval must NOT silently
    land on the voided cycle (which is excluded from liability + R1/R2/R4). With
    no valid covering cycle it is rejected, prompting the user to create one;
    once a valid cycle exists the charge lands there and liability tracks it.
    """
    account = _create_credit_account(client)
    category = _create_category(client)
    cycle_a = _create_cycle(client, account["id"], statement_amount="200")

    # Void cycle A (covers 2026-05-01 .. 2026-05-31).
    void = client.post(f"/api/v1/credit-statement-cycles/{cycle_a['id']}/void")
    assert void.status_code == 200, void.text
    assert _liability(client, account["id"]) == Decimal("0.00")

    # A charge dated inside A's interval, with no valid cycle, must be rejected
    # (not silently absorbed by the voided cycle).
    rejected = _credit_charge_entry(
        client, account["id"], category["id"], date="2026-05-15", amount="50"
    )
    assert rejected.status_code == 400, rejected.text
    assert (
        rejected.json()["detail"] == "Credit charge requires a matching statement cycle"
    )
    # The voided cycle is untouched; liability still 0.
    assert _liability(client, account["id"]) == Decimal("0.00")
    assert (
        Decimal(_cycle(client, cycle_a["id"])["statement_amount"]) == Decimal("200.00")
    )

    # Create a valid new cycle covering the same interval, then re-charge.
    cycle_b = _create_cycle(client, account["id"], statement_amount="0")
    ok = _credit_charge_entry(
        client, account["id"], category["id"], date="2026-05-15", amount="50"
    )
    assert ok.status_code == 201, ok.text
    assert ok.json()["account_movements"][0]["statement_cycle_id"] == cycle_b["id"]
    # Charge landed on the valid cycle; liability tracks it (voided A excluded).
    assert _liability(client, account["id"]) == Decimal("50.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])


def test_mark_paid_does_not_create_settled_orphan(client) -> None:
    """重要-2: mark-paid must not leave its linked repayment cash flow as a
    settled-with-no-entry R4① orphan ("已结算现金流缺记账"). It is cancelled
    instead, so /reconciliation/check stays clean and liability is 0.
    """
    account = _create_credit_account(client)
    cycle = _create_cycle(client, account["id"], statement_amount="600")
    linked_id = cycle["linked_cash_flow_item_id"]

    paid = client.post(f"/api/v1/credit-statement-cycles/{cycle['id']}/mark-paid")
    assert paid.status_code == 200, paid.text

    payload = client.get("/api/v1/reconciliation/check").json()
    settled_orphans = [
        o for o in payload["orphans"] if o["title"] == "已结算现金流缺记账"
    ]
    # No self-made orphan, and specifically not one pointing at the linked item.
    assert settled_orphans == []
    assert all(
        o["offending"][0]["id"] != linked_id for o in payload["orphans"]
    )
    # Invariant holds: liability 0 = Σcycle.
    assert _liability(client, account["id"]) == Decimal("0.00")
    assert _liability(client, account["id"]) == _cycle_total(client, account["id"])
