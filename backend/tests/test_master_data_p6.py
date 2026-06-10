"""P6 master-data management (audit 2.5).

Covers the three new PATCH endpoints (accounts / categories / currency-rates),
the currency-rate composite unique constraint (409 on conflict), and the
"history is never rewritten" guard on rate edits.
"""


def _make_account(client, account_type="balance", **overrides):
    payload = {
        "name": "Wallet",
        "type": account_type,
        "currency": "CNY",
        "current_balance": "1000",
    }
    payload.update(overrides)
    response = client.post("/api/v1/accounts", json=payload)
    assert response.status_code == 201
    return response.json()


def _make_category(client, **overrides):
    payload = {"name": "Dining", "type": "expense"}
    payload.update(overrides)
    response = client.post("/api/v1/categories", json=payload)
    assert response.status_code == 201
    return response.json()


def _make_rate(client, date="2026-05-16", rate="6.8", from_currency="USD"):
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": from_currency,
            "to_currency": "CNY",
            "rate": rate,
            "date": date,
            "source": "manual",
        },
    )
    assert response.status_code == 201
    return response.json()


# --------------------------------------------------------------------------
# PATCH /accounts/{id}
# --------------------------------------------------------------------------


def test_patch_account_updates_editable_fields(client) -> None:
    account = _make_account(client, account_type="credit", currency="USD")

    response = client.patch(
        f"/api/v1/accounts/{account['id']}",
        json={
            "name": "Renamed Card",
            "include_in_net_worth": False,
            "status": "archived",
            "display_order": 5,
            "credit_limit": "5000",
            "statement_day": 10,
            "due_day": 25,
            "minimum_payment": "100",
            "notes": "primary card",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Renamed Card"
    assert body["include_in_net_worth"] is False
    assert body["status"] == "archived"
    assert body["display_order"] == 5
    assert body["credit_limit"] == "5000.00"
    assert body["statement_day"] == 10
    assert body["due_day"] == 25
    assert body["minimum_payment"] == "100.00"
    assert body["notes"] == "primary card"
    # Unspecified immutable fields are untouched.
    assert body["type"] == "credit"
    assert body["currency"] == "USD"


def test_patch_account_partial_leaves_other_fields_untouched(client) -> None:
    account = _make_account(client, name="Original", display_order=3)

    response = client.patch(
        f"/api/v1/accounts/{account['id']}",
        json={"name": "Only Name"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Only Name"
    assert body["display_order"] == 3


def test_patch_account_can_clear_nullable_field(client) -> None:
    account = _make_account(client, account_type="credit", credit_limit="9000")
    assert account["credit_limit"] == "9000.00"

    response = client.patch(
        f"/api/v1/accounts/{account['id']}",
        json={"credit_limit": None},
    )

    assert response.status_code == 200
    assert response.json()["credit_limit"] is None


def test_patch_account_rejects_immutable_fields(client) -> None:
    account = _make_account(client)

    for field, value in (
        ("type", "credit"),
        ("currency", "USD"),
        ("current_balance", "999"),
        ("current_liability", "50"),
    ):
        response = client.patch(
            f"/api/v1/accounts/{account['id']}",
            json={field: value},
        )
        assert response.status_code == 422, field

    # Balance is unchanged after the rejected attempts.
    assert client.get(f"/api/v1/accounts/{account['id']}").json()[
        "current_balance"
    ] == "1000.00"


def test_patch_account_not_found(client) -> None:
    response = client.patch("/api/v1/accounts/does-not-exist", json={"name": "x"})
    assert response.status_code == 404


# --------------------------------------------------------------------------
# PATCH /categories/{id}
# --------------------------------------------------------------------------


def test_patch_category_updates_editable_fields(client) -> None:
    category = _make_category(client)

    response = client.patch(
        f"/api/v1/categories/{category['id']}",
        json={"name": "Groceries", "is_active": False, "display_order": 7},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Groceries"
    assert body["is_active"] is False
    assert body["display_order"] == 7
    assert body["type"] == "expense"


def test_patch_category_rejects_immutable_fields(client) -> None:
    parent = _make_category(client, name="Parent")
    category = _make_category(client, name="Child", parent_id=parent["id"])

    for field, value in (("type", "income"), ("parent_id", None)):
        response = client.patch(
            f"/api/v1/categories/{category['id']}",
            json={field: value},
        )
        assert response.status_code == 422, field

    refreshed = client.get(f"/api/v1/categories/{category['id']}").json()
    assert refreshed["type"] == "expense"
    assert refreshed["parent_id"] == parent["id"]


def test_patch_category_not_found(client) -> None:
    response = client.patch("/api/v1/categories/nope", json={"name": "x"})
    assert response.status_code == 404


# --------------------------------------------------------------------------
# Currency-rate unique constraint + PATCH
# --------------------------------------------------------------------------


def test_create_duplicate_currency_rate_conflicts(client) -> None:
    _make_rate(client, date="2026-05-16")
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "6.9",
            "date": "2026-05-16",
            "source": "manual",
        },
    )
    assert response.status_code == 409


def test_patch_unreferenced_currency_rate_succeeds(client) -> None:
    rate = _make_rate(client, rate="6.8")

    response = client.patch(
        f"/api/v1/currency-rates/{rate['id']}",
        json={"rate": "7.1"},
    )

    assert response.status_code == 200
    assert response.json()["rate"] == "7.1"


def test_patch_currency_rate_rejects_immutable_fields(client) -> None:
    rate = _make_rate(client)

    for field, value in (
        ("from_currency", "EUR"),
        ("to_currency", "USD"),
        ("date", "2026-05-17"),
        ("source", "api"),
    ):
        response = client.patch(
            f"/api/v1/currency-rates/{rate['id']}",
            json={"rate": "7.0", field: value},
        )
        assert response.status_code == 422, field


def test_patch_referenced_currency_rate_conflicts(client) -> None:
    """A rate pinned by a confirmed entry cannot be edited (409)."""
    rate = _make_rate(client, rate="6.8")
    usd_account = _make_account(client, name="USD Wallet", currency="USD")
    category = _make_category(client, name="USD Dining")

    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "USD expense",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "10",
                    "currency": "USD",
                    "exchange_rate_id": rate["id"],
                }
            ],
            "account_movements": [
                {
                    "account_id": usd_account["id"],
                    "movement_type": "balance_out",
                    "amount": "10",
                    "currency": "USD",
                    "exchange_rate_id": rate["id"],
                }
            ],
        },
    )
    assert entry.status_code == 201

    response = client.patch(
        f"/api/v1/currency-rates/{rate['id']}",
        json={"rate": "7.0"},
    )
    assert response.status_code == 409
    # The rate value is untouched.
    assert client.get(f"/api/v1/currency-rates/{rate['id']}").json()["rate"] == "6.8"


def test_patch_currency_rate_not_found(client) -> None:
    response = client.patch("/api/v1/currency-rates/nope", json={"rate": "7.0"})
    assert response.status_code == 404
