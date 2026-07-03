"""v2.5.0 P1 — pending reimbursement receivable folded into net worth.

All dates are generated relative to ``app_today()`` and never hard-coded, so
these tests do not drift as wall-clock time advances (unlike the pre-existing
``test_dashboard_v1_1_6.py`` credit-cycle cases whose hard-coded ``due_date``
rots — see PROJECT_PLAN §4).

Covered (§5.4 P1):
  ① pending receivable counts toward net worth (CNY total + per-currency);
  ② received + abandoned do NOT count;
  ③ multi-currency per-currency correctness;
  ④ CNY conversion of a foreign-currency bucket is correct;
  ⑤ no pending -> receivable is 0 and net worth is the old value (regression);
  ⑥ missing-rate scenario -> GET still 200, receivable falls back to stored
     ``converted_cny_amount`` (and None stored contributes 0), never 400.
Plus a no-double-count regression walking expense -> claim -> void.
"""

from datetime import timedelta
from decimal import Decimal

from app.core.timeutils import app_today
from app.models.reimbursement import ReimbursementClaim


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


def _create_expense_category(client, name="Travel"):
    response = client.post(
        "/api/v1/categories", json={"name": name, "type": "expense"}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_income_category(client, name="Reimbursement income"):
    response = client.post(
        "/api/v1/categories", json={"name": name, "type": "income"}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _usd_rate(client, rate="7", on_date=None):
    on_date = on_date or app_today()
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": rate,
            "date": on_date.isoformat(),
            "source": "manual",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_reimbursable_entry(
    client,
    account,
    expense_category,
    amount="500",
    currency="CNY",
):
    """A confirmed reimbursable expense -> a pending claim is auto-created.

    The entry date is today and the reimbursement expected date is 30 days out,
    both relative to ``app_today()`` so the fixture never drifts.
    """
    today = app_today()
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Client trip",
            "date": today.isoformat(),
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": expense_category["id"],
                    "direction": "expense",
                    "amount": amount,
                    "currency": currency,
                    "reimbursable_flag": True,
                    "reimbursement_payer": "company",
                    "reimbursement_expected_date": (
                        today + timedelta(days=30)
                    ).isoformat(),
                    "reimbursement_status": "pending",
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
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _summary(client):
    response = client.get("/api/v1/dashboard/summary")
    assert response.status_code == 200, response.text
    return response.json()


def _by_ccy(rows):
    return {row["currency"]: Decimal(row["amount"]) for row in rows}


def _single_pending_claim(client):
    claims = client.get("/api/v1/reimbursement-claims").json()
    pending = [c for c in claims if c["status"] == "pending"]
    assert len(pending) == 1, pending
    return pending[0]


# ── ① pending receivable counts toward net worth (CNY) ──────────────────────
def test_pending_receivable_counts_in_net_worth_cny(client) -> None:
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    category = _create_expense_category(client)

    baseline = _summary(client)
    assert Decimal(baseline["reimbursement_receivable_total_cny"]) == Decimal("0")
    # Wallet 1000, no receivable yet -> net worth 1000.
    assert Decimal(baseline["net_worth_cny"]) == Decimal("1000")

    # Spend 500 reimbursable: balance drops to 500, a 500 pending claim appears.
    _create_reimbursable_entry(client, wallet, category, amount="500")

    summary = _summary(client)
    assert Decimal(summary["balance_total_cny"]) == Decimal("500")
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("500")
    # net worth = 500 balance + 500 receivable = 1000 (back to the pre-spend value).
    assert Decimal(summary["net_worth_cny"]) == Decimal("1000")

    receivable_by_ccy = _by_ccy(summary["reimbursement_receivable_by_currency"])
    assert receivable_by_ccy == {"CNY": Decimal("500")}
    net = _by_ccy(summary["net_worth_by_currency"])
    assert net == {"CNY": Decimal("1000")}


# ── ② received + abandoned do NOT count ─────────────────────────────────────
def test_received_receivable_not_counted(client) -> None:
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    income_account = _create_account(client, "Payout", "balance", "CNY", "0")
    expense_category = _create_expense_category(client)
    _create_income_category(client)  # for mark-received entry income line

    _create_reimbursable_entry(client, wallet, expense_category, amount="500")
    claim = _single_pending_claim(client)

    # Mark the claim received: money lands in an account, claim -> received.
    today = app_today()
    resp = client.post(
        f"/api/v1/reimbursement-claims/{claim['id']}/mark-received",
        json={
            "actual_received_date": today.isoformat(),
            "received_account_id": income_account["id"],
            "entry": {
                "title": "Reimbursement received",
                "date": today.isoformat(),
                "status": "confirmed",
                "category_lines": [
                    {
                        "category_id": _create_income_category(
                            client, "Reimb income 2"
                        )["id"],
                        "direction": "income",
                        "amount": "500",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": income_account["id"],
                        "movement_type": "balance_in",
                        "amount": "500",
                        "currency": "CNY",
                    }
                ],
            },
        },
    )
    assert resp.status_code == 200, resp.text

    summary = _summary(client)
    # Received claim is no longer a receivable; the 500 is now real balance.
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("0")
    assert summary["reimbursement_receivable_by_currency"] == [
        {"currency": "CNY", "amount": "0"}
    ]
    # balance = wallet 500 + payout 500 = 1000; net worth = 1000 (no double count).
    assert Decimal(summary["balance_total_cny"]) == Decimal("1000")
    assert Decimal(summary["net_worth_cny"]) == Decimal("1000")


def test_abandoned_receivable_not_counted(client) -> None:
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    category = _create_expense_category(client)

    _create_reimbursable_entry(client, wallet, category, amount="500")
    claim = _single_pending_claim(client)

    resp = client.post(f"/api/v1/reimbursement-claims/{claim['id']}/abandon")
    assert resp.status_code == 200, resp.text

    summary = _summary(client)
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("0")
    assert summary["reimbursement_receivable_by_currency"] == [
        {"currency": "CNY", "amount": "0"}
    ]
    # balance stayed at 500 (the spend is real); net worth = 500, no receivable.
    assert Decimal(summary["balance_total_cny"]) == Decimal("500")
    assert Decimal(summary["net_worth_cny"]) == Decimal("500")


# ── ③ + ④ multi-currency per-currency + CNY conversion of a foreign bucket ──
def test_multi_currency_receivable_per_currency_and_cny_conversion(client) -> None:
    _usd_rate(client, rate="7")  # 1 USD = 7 CNY
    cny_wallet = _create_account(client, "CNYWallet", "balance", "CNY", "1000")
    usd_wallet = _create_account(client, "USDWallet", "balance", "USD", "100")
    cny_cat = _create_expense_category(client, "CNY travel")
    usd_cat = _create_expense_category(client, "USD travel")

    # CNY reimbursable 300, USD reimbursable 40.
    _create_reimbursable_entry(client, cny_wallet, cny_cat, amount="300", currency="CNY")
    _create_reimbursable_entry(client, usd_wallet, usd_cat, amount="40", currency="USD")

    summary = _summary(client)

    receivable_by_ccy = _by_ccy(summary["reimbursement_receivable_by_currency"])
    # ③ per-currency buckets are in ORIGINAL currency (not converted).
    assert receivable_by_ccy == {"CNY": Decimal("300"), "USD": Decimal("40")}

    # ④ total CNY = 300 (CNY) + 40 USD * 7 = 300 + 280 = 580.
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("580")

    # per-currency net worth folds receivable into each currency bucket:
    #   CNY: balance 700 (1000-300) + receivable 300 = 1000
    #   USD: balance 60  (100-40)  + receivable 40  = 100
    net = _by_ccy(summary["net_worth_by_currency"])
    assert net == {"CNY": Decimal("1000"), "USD": Decimal("100")}


# ── ⑤ no pending -> receivable 0, net worth unchanged (regression) ──────────
def test_no_pending_receivable_is_zero_and_net_worth_unchanged(client) -> None:
    _create_account(client, "Wallet", "balance", "CNY", "1000")
    _create_account(client, "Funds", "investment", "CNY", "500")

    summary = _summary(client)
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("0")
    # by_currency still carries the CNY floor row at 0.
    assert summary["reimbursement_receivable_by_currency"] == [
        {"currency": "CNY", "amount": "0"}
    ]
    # net worth = 1000 balance + 500 investment = 1500 (pre-v2.5.0 formula).
    assert Decimal(summary["net_worth_cny"]) == Decimal("1500")
    assert _by_ccy(summary["net_worth_by_currency"]) == {"CNY": Decimal("1500")}


# ── ⑥ missing-rate fallback -> still 200, uses stored converted_cny_amount ───
def test_missing_rate_falls_back_to_stored_converted_and_stays_200(client) -> None:
    """A USD pending claim exists but there is NO USD rate for today.

    Manufacture the USD claim directly against the shared in-memory engine
    (conftest exposes ``session_factory`` for exactly this) so the dashboard's
    real-time ``convert_to_cny`` raises and the stored-``converted_cny_amount``
    fallback is exercised — the overview must still open (200).
    """
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    category = _create_expense_category(client)
    # A real CNY reimbursable entry gives us a valid linked_entry_id to reuse.
    entry = _create_reimbursable_entry(client, wallet, category, amount="500")
    entry_id = entry["id"]
    line_id = entry["category_lines"][0]["id"]

    today = app_today()
    # Insert two USD pending claims with NO USD rate in the DB:
    #   - one with a stored converted_cny_amount (fallback = that stored value)
    #   - one with converted_cny_amount = None (contributes 0)
    session = client.session_factory()
    try:
        session.add(
            ReimbursementClaim(
                linked_entry_id=entry_id,
                linked_entry_line_id=line_id,
                amount=Decimal("40"),
                currency="USD",
                converted_cny_amount=Decimal("280"),  # stored fallback value
                payer="company",
                expected_date=today + timedelta(days=30),
                status="pending",
            )
        )
        session.add(
            ReimbursementClaim(
                linked_entry_id=entry_id,
                linked_entry_line_id=line_id,
                amount=Decimal("10"),
                currency="USD",
                converted_cny_amount=None,  # None -> contributes 0
                payer="company",
                expected_date=today + timedelta(days=30),
                status="pending",
            )
        )
        session.commit()
    finally:
        session.close()

    summary = _summary(client)  # asserts 200

    # USD bucket original-currency sum = 40 + 10 = 50 (still shown by-currency).
    receivable_by_ccy = _by_ccy(summary["reimbursement_receivable_by_currency"])
    assert receivable_by_ccy["USD"] == Decimal("50")
    assert receivable_by_ccy["CNY"] == Decimal("500")

    # CNY total = 500 (CNY, real rate=1) + USD fallback (280 stored + 0) = 780.
    assert Decimal(summary["reimbursement_receivable_total_cny"]) == Decimal("780")

    # net worth = balance 500 (1000-500) + receivable 780 = 1280.
    assert Decimal(summary["net_worth_cny"]) == Decimal("1280")


# ── no-double-count regression: expense -> claim -> void ────────────────────
def test_no_double_count_expense_claim_void(client) -> None:
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    category = _create_expense_category(client)

    # Baseline net worth = 1000.
    assert Decimal(_summary(client)["net_worth_cny"]) == Decimal("1000")

    # Reimbursable spend drops balance to 500 but adds a 500 receivable ->
    # net worth returns to ~1000 (expense already lowered it, receivable adds back).
    entry = _create_reimbursable_entry(client, wallet, category, amount="500")
    after_spend = _summary(client)
    assert Decimal(after_spend["balance_total_cny"]) == Decimal("500")
    assert Decimal(after_spend["reimbursement_receivable_total_cny"]) == Decimal("500")
    assert Decimal(after_spend["net_worth_cny"]) == Decimal("1000")

    # Void the entry: its claim is auto-abandoned, balance restored to 1000,
    # receivable back to 0 — net worth stays 1000 with no leftover receivable.
    resp = client.post(f"/api/v1/entries/{entry['id']}/void")
    assert resp.status_code == 200, resp.text

    after_void = _summary(client)
    assert Decimal(after_void["balance_total_cny"]) == Decimal("1000")
    assert Decimal(after_void["reimbursement_receivable_total_cny"]) == Decimal("0")
    assert Decimal(after_void["net_worth_cny"]) == Decimal("1000")
