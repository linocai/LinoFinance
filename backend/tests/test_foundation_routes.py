def test_create_and_fetch_account(client) -> None:
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": "Chase Checking",
            "type": "balance",
            "currency": "usd",
        },
    )

    assert response.status_code == 201
    account = response.json()
    assert account["name"] == "Chase Checking"
    assert account["currency"] == "USD"

    fetch_response = client.get(f"/api/v1/accounts/{account['id']}")
    assert fetch_response.status_code == 200
    assert fetch_response.json()["id"] == account["id"]


def test_create_investment_account(client) -> None:
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": "Test Fund",
            "type": "investment",
            "currency": "cny",
            "current_balance": "1000.50",
        },
    )

    assert response.status_code == 201
    account = response.json()
    assert account["type"] == "investment"
    assert account["currency"] == "CNY"
    assert account["current_balance"] == "1000.50"
    assert account["current_liability"] == "0.00"

    fetch_response = client.get(f"/api/v1/accounts/{account['id']}")
    assert fetch_response.status_code == 200
    assert fetch_response.json()["type"] == "investment"


def test_create_category(client) -> None:
    response = client.post(
        "/api/v1/categories",
        json={
            "name": "Dining",
            "type": "expense",
        },
    )

    assert response.status_code == 201
    category = response.json()
    assert category["name"] == "Dining"
    assert category["type"] == "expense"


def test_create_currency_rate(client) -> None:
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "usd",
            "to_currency": "cny",
            "rate": "6.8",
            "date": "2026-05-16",
            "source": "manual",
        },
    )

    assert response.status_code == 201
    rate = response.json()
    assert rate["from_currency"] == "USD"
    assert rate["to_currency"] == "CNY"
    assert rate["rate"] == "6.8"

