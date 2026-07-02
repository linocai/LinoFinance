"""GET /entries pagination + account_id filter + N+1 fix (v2.4.0 P2).

The core guarantee: calling ``GET /entries`` with no params returns the whole
set, equivalent to the pre-v2.4.0 per-entry ``get_entry`` path. Since the batch
loader now sorts lines/movements by ``created_at ASC, id ASC`` (deterministic,
replacing the old unguaranteed insertion order — see PROJECT_PLAN §5.5 风险1),
"equivalent" means: same entries in the same order, each with the same *set* of
lines/movements and the same derived per-line/per-movement fields, and the
per-entry order stable across repeated calls (so the frontend
``categoryLines.first.direction`` is deterministic).
"""

from __future__ import annotations


def _create_account(client, name="Wallet", account_type="balance", currency="CNY", balance="0"):
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


def _create_category(client, name="Dining", category_type="expense"):
    response = client.post(
        "/api/v1/categories", json={"name": name, "type": category_type}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_expense_entry(client, account, category, amount, title, date="2026-06-01"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": title,
            "date": date,
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
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
    assert response.status_code == 201, response.text
    return response.json()


def _create_transfer_entry(client, from_account, to_account, amount, title, date="2026-06-01"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": title,
            "entry_type": "transfer",
            "date": date,
            "status": "confirmed",
            "account_movements": [
                {
                    "account_id": from_account["id"],
                    "movement_type": "transfer_out",
                    "amount": amount,
                    "currency": "CNY",
                },
                {
                    "account_id": to_account["id"],
                    "movement_type": "transfer_in",
                    "amount": amount,
                    "currency": "CNY",
                },
            ],
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


# ---------------------------------------------------------------------------
# No params == full scan, equivalent to the old per-entry path
# ---------------------------------------------------------------------------


def test_no_params_returns_full_set_equivalent_to_per_entry(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="1000")
    savings = _create_account(client, name="Savings", balance="0")
    dining = _create_category(client, name="Dining")
    travel = _create_category(client, name="Travel")

    e1 = _create_expense_entry(client, wallet, dining, "50", "Lunch", date="2026-06-01")
    e2 = _create_expense_entry(client, wallet, travel, "120", "Train", date="2026-06-03")
    e3 = _create_transfer_entry(client, wallet, savings, "200", "Move", date="2026-06-02")

    listed = client.get("/api/v1/entries").json()
    # Build the reference from the per-entry endpoint (the old code path shape).
    reference = [client.get(f"/api/v1/entries/{e['id']}").json() for e in (e1, e2, e3)]
    reference_by_id = {e["id"]: e for e in reference}

    # Same count and same newest-first ordering (date DESC, created_at DESC).
    assert len(listed) == 3
    assert [e["id"] for e in listed] == [e2["id"], e3["id"], e1["id"]]

    # Every entry is byte-identical to its per-entry read (lines/movements are a
    # single row each here, so ordering is unambiguous).
    for entry in listed:
        assert entry == reference_by_id[entry["id"]]


def test_no_params_multi_line_entry_is_set_equal_and_deterministic(client) -> None:
    # An entry with several same-direction category lines: order among them is
    # immaterial to the frontend (kind() reads only .first.direction, and a
    # confirmed entry's lines share a direction), but the batch loader must be
    # a superset-preserving, deterministic (repeatable) ordering.
    wallet = _create_account(client, name="Wallet", balance="1000")
    c1 = _create_category(client, name="C1")
    c2 = _create_category(client, name="C2")
    c3 = _create_category(client, name="C3")

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Split",
            "date": "2026-06-01",
            "status": "confirmed",
            "category_lines": [
                {"category_id": c1["id"], "direction": "expense", "amount": "10", "currency": "CNY"},
                {"category_id": c2["id"], "direction": "expense", "amount": "20", "currency": "CNY"},
                {"category_id": c3["id"], "direction": "expense", "amount": "30", "currency": "CNY"},
            ],
            "account_movements": [
                {"account_id": wallet["id"], "movement_type": "balance_out", "amount": "60", "currency": "CNY"},
            ],
        },
    )
    assert response.status_code == 201, response.text

    first = client.get("/api/v1/entries").json()[0]
    per_entry = client.get(f"/api/v1/entries/{first['id']}").json()

    # Same set of lines regardless of order.
    def _line_key(line):
        return (line["category_id"], line["direction"], line["amount"])

    assert sorted(_line_key(x) for x in first["category_lines"]) == sorted(
        _line_key(x) for x in per_entry["category_lines"]
    )
    assert len(first["category_lines"]) == 3
    # All same direction → kind() is stable irrespective of order.
    assert {x["direction"] for x in first["category_lines"]} == {"expense"}
    # Deterministic: the list-endpoint order repeats across calls.
    again = client.get("/api/v1/entries").json()[0]
    assert [x["id"] for x in again["category_lines"]] == [
        x["id"] for x in first["category_lines"]
    ]


def test_first_line_direction_derived_field_is_stable(client) -> None:
    # The frontend LedgerModel.kind(of:) relies on categoryLines.first.direction.
    wallet = _create_account(client, name="Wallet", balance="1000")
    salary_cat = _create_category(client, name="Salary", category_type="income")
    dining = _create_category(client, name="Dining")

    _create_expense_entry(client, wallet, dining, "50", "Lunch")
    client.post(
        "/api/v1/entries",
        json={
            "title": "Payday",
            "date": "2026-06-05",
            "status": "confirmed",
            "category_lines": [
                {"category_id": salary_cat["id"], "direction": "income", "amount": "5000", "currency": "CNY"}
            ],
            "account_movements": [
                {"account_id": wallet["id"], "movement_type": "balance_in", "amount": "5000", "currency": "CNY"}
            ],
        },
    )

    listed = client.get("/api/v1/entries").json()
    by_title = {e["title"]: e for e in listed}
    assert by_title["Lunch"]["category_lines"][0]["direction"] == "expense"
    assert by_title["Payday"]["category_lines"][0]["direction"] == "income"


# ---------------------------------------------------------------------------
# limit / offset paging
# ---------------------------------------------------------------------------


def test_limit_offset_slices_after_ordering(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="10000")
    dining = _create_category(client, name="Dining")
    # Distinct dates so ordering is deterministic (date DESC).
    entries = []
    for i in range(5):
        entries.append(
            _create_expense_entry(
                client, wallet, dining, "10", f"E{i}", date=f"2026-06-0{i + 1}"
            )
        )
    # Newest first: E4, E3, E2, E1, E0
    full = client.get("/api/v1/entries").json()
    assert [e["title"] for e in full] == ["E4", "E3", "E2", "E1", "E0"]

    page1 = client.get("/api/v1/entries?limit=2").json()
    assert [e["title"] for e in page1] == ["E4", "E3"]

    page2 = client.get("/api/v1/entries?limit=2&offset=2").json()
    assert [e["title"] for e in page2] == ["E2", "E1"]

    page3 = client.get("/api/v1/entries?limit=2&offset=4").json()
    assert [e["title"] for e in page3] == ["E0"]


def test_limit_out_of_range_returns_422(client) -> None:
    assert client.get("/api/v1/entries?limit=0").status_code == 422
    assert client.get("/api/v1/entries?limit=501").status_code == 422
    assert client.get("/api/v1/entries?limit=-1").status_code == 422
    assert client.get("/api/v1/entries?offset=-1").status_code == 422
    # Boundaries are valid.
    assert client.get("/api/v1/entries?limit=1").status_code == 200
    assert client.get("/api/v1/entries?limit=500").status_code == 200


# ---------------------------------------------------------------------------
# account_id EXISTS filter
# ---------------------------------------------------------------------------


def test_account_id_filter_matches_entries_with_a_movement_on_it(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="1000")
    savings = _create_account(client, name="Savings", balance="0")
    other = _create_account(client, name="Other", balance="500")
    dining = _create_category(client, name="Dining")

    on_wallet = _create_expense_entry(client, wallet, dining, "50", "Lunch")
    on_other = _create_expense_entry(client, other, dining, "30", "Snack")
    transfer = _create_transfer_entry(client, wallet, savings, "200", "Move")

    filtered = client.get(f"/api/v1/entries?account_id={wallet['id']}").json()
    ids = {e["id"] for e in filtered}
    # Wallet appears in the expense entry AND the transfer's transfer_out side.
    assert ids == {on_wallet["id"], transfer["id"]}
    assert on_other["id"] not in ids

    # savings appears only in the transfer (transfer_in side).
    savings_filtered = client.get(f"/api/v1/entries?account_id={savings['id']}").json()
    assert {e["id"] for e in savings_filtered} == {transfer["id"]}


def test_account_id_filter_does_not_duplicate_multi_movement_entry(client) -> None:
    # A transfer entry has TWO movements. If wallet is on both sides a naive JOIN
    # would return the entry twice — EXISTS must return it exactly once.
    wallet = _create_account(client, name="Wallet", balance="1000")
    # Self-transfer is not meaningful; instead make an entry with two movements
    # touching the same account: a transfer between two of the account's roles is
    # not possible, so use an expense with a second (zero-impact) same-account
    # movement is also not possible. Use a transfer where wallet is the out side
    # and verify the count is 1; then add another entry to be sure.
    savings = _create_account(client, name="Savings", balance="0")
    transfer = _create_transfer_entry(client, wallet, savings, "100", "Move")

    # Give the transfer entry a *second* wallet movement directly at the DB layer
    # to force the multi-movement-on-same-account case.
    from app.models.entry import AccountMovement
    from decimal import Decimal

    session = client.session_factory()  # type: ignore[attr-defined]
    try:
        session.add(
            AccountMovement(
                entry_id=transfer["id"],
                account_id=wallet["id"],
                movement_type="transfer_out",
                amount=Decimal("1"),
                currency="CNY",
                converted_cny_amount=Decimal("1"),
            )
        )
        session.commit()
    finally:
        session.close()

    filtered = client.get(f"/api/v1/entries?account_id={wallet['id']}").json()
    matching = [e for e in filtered if e["id"] == transfer["id"]]
    assert len(matching) == 1  # not duplicated despite two wallet movements
    # And the entry still carries BOTH wallet movements (set preserved, not trimmed).
    wallet_movs = [
        m for m in matching[0]["account_movements"] if m["account_id"] == wallet["id"]
    ]
    assert len(wallet_movs) == 2


def test_account_id_filter_is_status_agnostic_includes_voided(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="1000")
    dining = _create_category(client, name="Dining")
    entry = _create_expense_entry(client, wallet, dining, "50", "Lunch")

    void_response = client.post(f"/api/v1/entries/{entry['id']}/void")
    assert void_response.status_code == 200
    assert void_response.json()["status"] == "voided"

    filtered = client.get(f"/api/v1/entries?account_id={wallet['id']}").json()
    assert [e["id"] for e in filtered] == [entry["id"]]
    assert filtered[0]["status"] == "voided"


def test_account_id_filter_combines_with_paging(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="10000")
    other = _create_account(client, name="Other", balance="1000")
    dining = _create_category(client, name="Dining")
    wallet_entries = [
        _create_expense_entry(client, wallet, dining, "10", f"W{i}", date=f"2026-06-0{i + 1}")
        for i in range(3)
    ]
    _create_expense_entry(client, other, dining, "10", "OTHER", date="2026-06-09")

    # Filter to wallet, then take the newest one.
    page = client.get(f"/api/v1/entries?account_id={wallet['id']}&limit=1").json()
    assert len(page) == 1
    assert page[0]["id"] == wallet_entries[2]["id"]  # W2 is newest wallet entry


# ---------------------------------------------------------------------------
# cash-flow-items account_id filter
# ---------------------------------------------------------------------------


def test_cash_flow_account_id_filter(client) -> None:
    wallet = _create_account(client, name="Wallet", balance="0")
    other = _create_account(client, name="Other", balance="0")

    def _cash_flow(account_id, title):
        response = client.post(
            "/api/v1/cash-flow-items",
            json={
                "title": title,
                "direction": "outflow",
                "cash_flow_type": "one_time",
                "amount": "100",
                "currency": "CNY",
                "expected_date": "2026-06-01",
                "account_id": account_id,
            },
        )
        assert response.status_code == 201, response.text
        return response.json()

    on_wallet = _cash_flow(wallet["id"], "W")
    on_other = _cash_flow(other["id"], "O")

    filtered = client.get(f"/api/v1/cash-flow-items?account_id={wallet['id']}").json()
    ids = {item["id"] for item in filtered}
    assert on_wallet["id"] in ids
    assert on_other["id"] not in ids
