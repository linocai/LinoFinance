"""PATCH /api/v1/cash-flow-items/{id} (v1.1.7)."""

from __future__ import annotations


def _create_account(client, name="Wallet", currency="CNY", balance="0"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "balance",
            "currency": currency,
            "current_balance": balance,
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_category(client, name="Misc", category_type="expense"):
    response = client.post(
        "/api/v1/categories",
        json={"name": name, "type": category_type},
    )
    assert response.status_code == 201
    return response.json()


def _create_usd_rate(client, date="2026-06-01", rate="7.1"):
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
    assert response.status_code == 201
    return response.json()


def _create_cash_flow(client, **overrides):
    payload = {
        "title": "测试现金流",
        "direction": "outflow",
        "cash_flow_type": "one_time",
        "amount": "100",
        "currency": "CNY",
        "expected_date": "2026-06-01",
    }
    payload.update(overrides)
    response = client.post("/api/v1/cash-flow-items", json=payload)
    assert response.status_code == 201, response.json()
    return response.json()


def test_update_cash_flow_title_and_amount(client) -> None:
    item = _create_cash_flow(client)

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"title": "新名", "amount": "123.45"},
    )

    assert response.status_code == 200, response.json()
    body = response.json()
    assert body["title"] == "新名"
    assert body["amount"] == "123.45"
    assert body["converted_cny_amount"] == "123.45"
    assert body["status"] == "expected"


def test_update_cash_flow_link_account_and_category(client) -> None:
    item = _create_cash_flow(client)
    account = _create_account(client, balance="500")
    category = _create_category(client)

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"account_id": account["id"], "category_id": category["id"]},
    )

    assert response.status_code == 200, response.json()
    body = response.json()
    assert body["account_id"] == account["id"]
    assert body["category_id"] == category["id"]


def test_update_cash_flow_unlink_account(client) -> None:
    account = _create_account(client, balance="500")
    category = _create_category(client)
    item = _create_cash_flow(
        client,
        account_id=account["id"],
        category_id=category["id"],
    )
    assert item["account_id"] == account["id"]

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"account_id": None},
    )

    assert response.status_code == 200, response.json()
    body = response.json()
    assert body["account_id"] is None
    # Category must remain — only account was sent as explicit null.
    assert body["category_id"] == category["id"]


def test_update_cash_flow_rejects_settled_row(client) -> None:
    account = _create_account(client, balance="500")
    category = _create_category(client, name="Salary", category_type="income")
    item = _create_cash_flow(
        client,
        title="工资",
        direction="inflow",
        cash_flow_type="salary",
        amount="1000",
        account_id=account["id"],
        category_id=category["id"],
        status="confirmed",
    )

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "工资到账",
                "entry_type": "single",
                "date": "2026-06-01",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "income",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_in",
                        "amount": "1000",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )
    assert settle_response.status_code == 200

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"title": "x"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == (
        "Settled or cancelled cash flow items cannot be edited"
    )


def test_update_cash_flow_rejects_non_cny_without_rate(client) -> None:
    item = _create_cash_flow(client)

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"currency": "USD", "amount": "50"},
    )

    assert response.status_code == 400
    assert "exchange_rate_id is required" in response.json()["detail"]


def test_update_cash_flow_currency_with_rate_succeeds(client) -> None:
    item = _create_cash_flow(client)
    rate = _create_usd_rate(client, date="2026-06-01", rate="7.1")

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={
            "currency": "USD",
            "amount": "50",
            "exchange_rate_id": rate["id"],
        },
    )

    assert response.status_code == 200, response.json()
    body = response.json()
    assert body["currency"] == "USD"
    assert body["amount"] == "50"
    assert body["exchange_rate_id"] == rate["id"]
    # 50 USD * 7.1 = 355.00
    assert body["converted_cny_amount"] == "355"
