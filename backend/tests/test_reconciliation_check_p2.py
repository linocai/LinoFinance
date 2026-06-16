"""v2.2.0 P2 — 对账一致性/冲突检测器 (GET /reconciliation/check) + recompute.

Read-only multi-dimension detector (PROJECT_PLAN §5.3/§5.4): R1 信用三数拆解 / R2
账单↔还款现金流 / R3 余额↔录真实余额 / R4 孤儿状态一致性. Plus the credit
recompute endpoint (R1 内部纠错) that re-derives ``current_liability := Σcycle``.

The detector must never write the DB; some orphan/drift states the normal API
path won't produce, so they're manufactured directly against the shared engine
via ``client.session_factory``.
"""
from datetime import date
from decimal import Decimal

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.entry import FinancialEntry
from app.models.reimbursement import ReimbursementClaim


# --- helpers ---------------------------------------------------------------


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


def _check(client):
    response = client.get("/api/v1/reconciliation/check")
    assert response.status_code == 200, response.text
    return response.json()


def _account_in_check(payload, account_id):
    return next(a for a in payload["accounts"] if a["account_id"] == account_id)


def _conflict(account, code):
    return [c for c in account["conflicts"] if c["code"] == code]


# --- empty / happy ---------------------------------------------------------


def test_check_empty_db_has_no_conflicts(client) -> None:
    payload = _check(client)
    assert payload["has_conflicts"] is False
    assert payload["accounts"] == []
    assert payload["orphans"] == []
    assert "checked_at" in payload


def test_check_balanced_credit_account_is_info_only(client) -> None:
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")

    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    assert account["has_conflicts"] is False
    # R1 breakdown is always present for credit accounts.
    assert account["breakdown"]["stored_liability"] == "600.00"
    assert account["breakdown"]["open_statements_total"] == "600.00"
    assert account["breakdown"]["unbilled_charges"] == "0.00"
    r1 = _conflict(account, "credit_three_way")
    assert len(r1) == 1
    assert r1[0]["severity"] == "info"
    assert r1[0]["fix"] == "none"


# --- R1 信用三数拆解 -------------------------------------------------------


def test_r1_breakdown_splits_current_due_and_other_due(client) -> None:
    # Two open cycles: 本期待还 600（最早到期）+ 其他期未还 800 = 合计 1400.
    card = _create_credit_account(client, "Card")
    _create_cycle(
        client,
        card["id"],
        start="2026-04-01",
        end="2026-04-30",
        statement="2026-05-01",
        due="2026-05-20",
        statement_amount="600",
    )
    _create_cycle(
        client,
        card["id"],
        start="2026-05-01",
        end="2026-05-31",
        statement="2026-06-01",
        due="2026-06-20",
        statement_amount="800",
    )
    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    r1 = _conflict(account, "credit_three_way")[0]
    assert r1["sum_open_statements"] == "1400.00"
    assert "本期待还 600.00" in r1["detail"]
    assert "其他期未还 800.00" in r1["detail"]
    # Both cycles surface as offending pointers (界面展开).
    cycle_ptrs = [p for p in r1["offending"] if p["type"] == "credit_statement_cycle"]
    assert len(cycle_ptrs) == 2


def test_r1_flags_drifted_stored_liability_as_conflict(client) -> None:
    # Manufacture drift: stored_liability ≠ Σcycle (legacy data not yet recomputed).
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")

    with client.session_factory() as db:
        account = db.get(Account, card["id"])
        account.current_liability = Decimal("1400")
        db.commit()

    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    assert account["has_conflicts"] is True
    r1 = _conflict(account, "credit_three_way")[0]
    assert r1["severity"] == "conflict"
    assert r1["stored_liability"] == "1400.00"
    assert r1["expected_liability"] == "600.00"
    assert r1["delta"] == "800.00"
    assert r1["fix"] == "internal_recompute"


# --- R2 账单 ↔ 还款现金流 --------------------------------------------------


def _make_open_cycle_with_balance(client) -> tuple[dict, str]:
    """A credit account with a charged cycle that auto-generates a repayment
    cash flow (statement 300, 未还 300)."""
    card = _create_credit_account(client, "Card")
    cycle = _create_cycle(client, card["id"])
    category = client.post(
        "/api/v1/categories", json={"name": "Travel", "type": "expense"}
    ).json()
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
    return card, cycle["id"]


def test_r2_balanced_cycle_cashflow_has_no_conflict(client) -> None:
    card, _ = _make_open_cycle_with_balance(client)
    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    assert _conflict(account, "statement_cashflow") == []


def test_r2_missing_repayment_cashflow_is_conflict(client) -> None:
    card, cycle_id = _make_open_cycle_with_balance(client)
    # Sever the cycle ↔ cash flow link so R2 sees a missing repayment.
    with client.session_factory() as db:
        cycle = db.get(CreditStatementCycle, cycle_id)
        cycle.linked_cash_flow_item_id = None
        db.commit()

    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    r2 = _conflict(account, "statement_cashflow")
    assert len(r2) == 1
    assert r2[0]["severity"] == "conflict"
    assert r2[0]["title"] == "账单缺对应还款现金流"
    assert any(p["type"] == "credit_statement_cycle" for p in r2[0]["offending"])
    assert account["has_conflicts"] is True


def test_r2_amount_mismatch_is_conflict(client) -> None:
    card, cycle_id = _make_open_cycle_with_balance(client)
    # Corrupt the linked cash flow amount so it disagrees with statement − paid.
    with client.session_factory() as db:
        cycle = db.get(CreditStatementCycle, cycle_id)
        item = db.get(CashFlowItem, cycle.linked_cash_flow_item_id)
        item.amount = Decimal("999")
        db.commit()

    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    r2 = _conflict(account, "statement_cashflow")
    assert len(r2) == 1
    assert r2[0]["title"] == "账单与还款现金流金额不符"
    # delta = linked.amount − remaining = 999 − 300.
    assert r2[0]["delta"] == "699.00"
    types = {p["type"] for p in r2[0]["offending"]}
    assert types == {"credit_statement_cycle", "cash_flow_item"}


def test_r2_cancelled_cashflow_is_conflict(client) -> None:
    card, cycle_id = _make_open_cycle_with_balance(client)
    with client.session_factory() as db:
        cycle = db.get(CreditStatementCycle, cycle_id)
        item = db.get(CashFlowItem, cycle.linked_cash_flow_item_id)
        item.status = "cancelled"
        db.commit()

    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    r2 = _conflict(account, "statement_cashflow")
    assert len(r2) == 1
    assert r2[0]["title"] == "账单关联的还款现金流已取消"


# --- R3 余额 ↔ 录真实余额 --------------------------------------------------


def test_r3_no_recorded_actual_is_info_prompt(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    payload = _check(client)
    account = _account_in_check(payload, checking["id"])
    r3 = _conflict(account, "balance_external")
    assert len(r3) == 1
    assert r3[0]["severity"] == "info"
    assert r3[0]["external_actual"] is None
    assert r3[0]["fix"] == "external_actual"
    assert account["has_conflicts"] is False


def test_r3_balance_account_matches_after_adjustment(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    # Record real balance == stored → no conflict, R3 happy 对平.
    response = client.post(
        "/api/v1/reconciliation/adjustments",
        json={"account_id": checking["id"], "actual_amount": "1200"},
    )
    assert response.status_code == 201, response.text

    payload = _check(client)
    account = _account_in_check(payload, checking["id"])
    # After the adjustment the stored balance was set to 1200 and the last
    # recorded external actual is 1200 → matched, no conflict.
    r3 = _conflict(account, "balance_external")
    assert r3 == []
    assert account["has_conflicts"] is False


def test_r3_drift_from_recorded_actual_is_conflict(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    client.post(
        "/api/v1/reconciliation/adjustments",
        json={"account_id": checking["id"], "actual_amount": "1000"},
    )
    # Now drift the stored balance away from the recorded actual.
    with client.session_factory() as db:
        account = db.get(Account, checking["id"])
        account.current_balance = Decimal("1500")
        db.commit()

    payload = _check(client)
    account = _account_in_check(payload, checking["id"])
    r3 = _conflict(account, "balance_external")
    assert len(r3) == 1
    assert r3[0]["severity"] == "conflict"
    assert r3[0]["stored_balance"] == "1500.00"
    assert r3[0]["external_actual"] == "1000.00"
    assert r3[0]["delta"] == "500.00"


def test_r3_credit_account_uses_recompute_not_adjustment(client) -> None:
    # Credit accounts do NOT get an R3 balance_external conflict (P1 blocks the
    # adjustment path with 400); their correction is R1 recompute.
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")
    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    assert _conflict(account, "balance_external") == []
    # And the legacy adjustment path is rejected for credit (P1 guard).
    response = client.post(
        "/api/v1/reconciliation/adjustments",
        json={"account_id": card["id"], "actual_amount": "1400"},
    )
    assert response.status_code == 400


# --- R4 孤儿/状态一致性 (D4 宽) --------------------------------------------


def test_r4_settled_cashflow_without_entry_is_orphan(client) -> None:
    with client.session_factory() as db:
        item = CashFlowItem(
            title="Settled no entry",
            direction="outflow",
            cash_flow_type="expense",
            amount=Decimal("100"),
            currency="CNY",
            converted_cny_amount=Decimal("100"),
            expected_date=date(2026, 6, 1),
            status="settled",
            linked_entry_id=None,
        )
        db.add(item)
        db.commit()
        item_id = item.id

    payload = _check(client)
    orphans = payload["orphans"]
    settled = [o for o in orphans if o["title"] == "已结算现金流缺记账"]
    assert len(settled) == 1
    assert settled[0]["offending"][0]["id"] == item_id
    assert payload["has_conflicts"] is True


def test_r4_received_reimbursement_without_entry_is_orphan(client) -> None:
    with client.session_factory() as db:
        entry = FinancialEntry(
            title="Expense",
            entry_type="expense",
            date=date(2026, 6, 1),
            status="confirmed",
        )
        db.add(entry)
        db.flush()
        claim = ReimbursementClaim(
            linked_entry_id=entry.id,
            amount=Decimal("250"),
            currency="CNY",
            converted_cny_amount=Decimal("250"),
            payer="Company",
            expected_date=date(2026, 6, 10),
            status="received",
            received_entry_id=None,
        )
        db.add(claim)
        db.commit()
        claim_id = claim.id

    payload = _check(client)
    orphans = [o for o in payload["orphans"] if o["title"] == "已到账报销缺到账记账"]
    assert len(orphans) == 1
    assert orphans[0]["offending"][0]["id"] == claim_id
    assert orphans[0]["offending"][0]["type"] == "reimbursement_claim"


def test_r4_open_cycle_without_cashflow_is_orphan(client) -> None:
    # A non-voided cycle with a balance but no linked cash flow.
    card = _create_credit_account(client, "Card")
    cycle = _create_cycle(client, card["id"], statement_amount="500")
    with client.session_factory() as db:
        c = db.get(CreditStatementCycle, cycle["id"])
        c.linked_cash_flow_item_id = None
        db.commit()

    payload = _check(client)
    orphans = [o for o in payload["orphans"] if o["title"] == "未还账单缺还款现金流"]
    assert len(orphans) == 1
    assert orphans[0]["offending"][0]["id"] == cycle["id"]
    assert orphans[0]["delta"] == "500.00"


# --- recompute 接口 --------------------------------------------------------


def test_recompute_credit_realigns_drifted_account(client) -> None:
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")
    # Drift stored away from Σcycle.
    with client.session_factory() as db:
        account = db.get(Account, card["id"])
        account.current_liability = Decimal("1400")
        db.commit()

    response = client.post(f"/api/v1/reconciliation/recompute-credit/{card['id']}")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["stored_liability_before"] == "1400.00"
    assert body["recomputed_liability"] == "600.00"
    assert body["delta"] == "-800.00"
    assert body["adjustment_id"] is not None

    # Liability now equals Σcycle, and the check no longer flags R1.
    liability = Decimal(
        client.get(f"/api/v1/accounts/{card['id']}").json()["current_liability"]
    )
    assert liability == Decimal("600.00")
    payload = _check(client)
    account = _account_in_check(payload, card["id"])
    r1 = _conflict(account, "credit_three_way")[0]
    assert r1["severity"] == "info"


def test_recompute_credit_aligned_account_is_noop(client) -> None:
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")
    response = client.post(f"/api/v1/reconciliation/recompute-credit/{card['id']}")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["delta"] == "0.00"
    assert body["adjustment_id"] is None


def test_recompute_non_credit_account_is_400(client) -> None:
    checking = _create_account(client, "Checking", "balance", "CNY", "1000")
    response = client.post(
        f"/api/v1/reconciliation/recompute-credit/{checking['id']}"
    )
    assert response.status_code == 400
    assert "credit" in response.json()["detail"].lower()


def test_recompute_missing_account_is_404(client) -> None:
    response = client.post(
        "/api/v1/reconciliation/recompute-credit/does-not-exist"
    )
    assert response.status_code == 404


def test_check_is_read_only(client) -> None:
    # Running the detector must not mutate stored balances/liabilities.
    card = _create_credit_account(client, "Card")
    _create_cycle(client, card["id"], statement_amount="600")
    with client.session_factory() as db:
        account = db.get(Account, card["id"])
        account.current_liability = Decimal("1400")
        db.commit()

    _check(client)  # flags R1 conflict but must not fix it.
    liability = Decimal(
        client.get(f"/api/v1/accounts/{card['id']}").json()["current_liability"]
    )
    assert liability == Decimal("1400.00")
