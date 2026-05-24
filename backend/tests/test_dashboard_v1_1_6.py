from datetime import date, timedelta
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


def _create_credit_account(client, name, currency="CNY", liability="0"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "credit",
            "currency": currency,
            "current_liability": liability,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_category(client, name="Salary", category_type="income"):
    response = client.post(
        "/api/v1/categories", json={"name": name, "type": category_type}
    )
    assert response.status_code == 201
    return response.json()


def _create_cash_flow_outflow(client, account, category, amount, expected_date, currency="CNY"):
    response = client.post(
        "/api/v1/cash-flow-items",
        json={
            "title": "Outflow",
            "direction": "outflow",
            "cash_flow_type": "one_time",
            "amount": amount,
            "currency": currency,
            "expected_date": expected_date.isoformat(),
            "account_id": account["id"],
            "category_id": category["id"],
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_dashboard_includes_investment_in_net_worth(client) -> None:
    _create_account(client, "Wallet", "balance", "CNY", "1000")
    _create_account(client, "Funds", "investment", "CNY", "500")
    _create_credit_account(client, "Card", "CNY", "300")

    summary = client.get("/api/v1/dashboard/summary").json()

    assert Decimal(summary["balance_total_cny"]) == Decimal("1000")
    assert Decimal(summary["investment_total_cny"]) == Decimal("500")
    assert Decimal(summary["credit_liability_total_cny"]) == Decimal("300")
    # 1000 + 500 - 300 = 1200
    assert Decimal(summary["net_worth_cny"]) == Decimal("1200")


def test_dashboard_disposable_30d_excludes_investment(client) -> None:
    wallet = _create_account(client, "Wallet", "balance", "CNY", "1000")
    _create_account(client, "Funds", "investment", "CNY", "500")
    category = _create_category(client, "Rent", "expense")
    _create_cash_flow_outflow(
        client,
        wallet,
        category,
        "200",
        date.today() + timedelta(days=5),
    )

    summary = client.get("/api/v1/dashboard/summary").json()

    disposable = {row["currency"]: Decimal(row["amount"]) for row in summary["disposable_30d_by_currency"]}
    # Wallet 1000 - 200 outflow = 800; investment 500 NOT included.
    assert disposable["CNY"] == Decimal("800")


def test_dashboard_by_currency_split(client) -> None:
    # Need a USD->CNY rate so convert_to_cny succeeds for the USD account.
    client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": "7",
            "date": date.today().isoformat(),
            "source": "manual",
        },
    )
    _create_account(client, "USDWallet", "balance", "USD", "100")
    _create_account(client, "CNYWallet", "balance", "CNY", "200")

    summary = client.get("/api/v1/dashboard/summary").json()

    disposable = {row["currency"]: Decimal(row["amount"]) for row in summary["disposable_30d_by_currency"]}
    assert disposable["CNY"] == Decimal("200")
    assert disposable["USD"] == Decimal("100")
    assert summary["investment_total_by_currency"] == []


def test_dashboard_today_pnl_empty_when_no_adjustments(client) -> None:
    summary = client.get("/api/v1/dashboard/summary").json()
    assert summary["today_pnl_by_currency"] == []
