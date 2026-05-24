from datetime import date, timedelta
from decimal import Decimal


def _create_investment_account(client, name="Funds", currency="CNY", balance="1000"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "investment",
            "currency": currency,
            "current_balance": balance,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_balance_account(client, name="Wallet", currency="CNY", balance="0"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "balance",
            "currency": currency,
            "current_balance": balance,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_record_daily_pnl_increase(client) -> None:
    account = _create_investment_account(client, balance="1000")

    response = client.post(
        f"/api/v1/accounts/{account['id']}/daily-pnl",
        json={"new_balance": "1050"},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["account_id"] == account["id"]
    assert body["currency"] == "CNY"
    assert Decimal(body["balance_before"]) == Decimal("1000")
    assert Decimal(body["balance_after"]) == Decimal("1050")
    assert Decimal(body["delta_amount"]) == Decimal("50")
    assert body["source"] == "investment_daily"

    refreshed = client.get(f"/api/v1/accounts/{account['id']}").json()
    assert Decimal(refreshed["current_balance"]) == Decimal("1050")

    # The dashboard should now report a CNY today P&L of +50.
    summary = client.get("/api/v1/dashboard/summary").json()
    pnl = {row["currency"]: Decimal(row["amount"]) for row in summary["today_pnl_by_currency"]}
    assert pnl.get("CNY") == Decimal("50")


def test_record_daily_pnl_decrease(client) -> None:
    account = _create_investment_account(client, balance="1000")

    response = client.post(
        f"/api/v1/accounts/{account['id']}/daily-pnl",
        json={"new_balance": "900"},
    )
    assert response.status_code == 201
    body = response.json()
    assert Decimal(body["delta_amount"]) == Decimal("-100")
    refreshed = client.get(f"/api/v1/accounts/{account['id']}").json()
    assert Decimal(refreshed["current_balance"]) == Decimal("900")


def test_record_daily_pnl_zero_delta_allowed(client) -> None:
    account = _create_investment_account(client, balance="1000")

    response = client.post(
        f"/api/v1/accounts/{account['id']}/daily-pnl",
        json={"new_balance": "1000"},
    )
    assert response.status_code == 201
    body = response.json()
    assert Decimal(body["delta_amount"]) == Decimal("0")
    # A zero-delta adjustment still surfaces in the dashboard today P&L
    # (so the user sees "0 today" rather than nothing).
    summary = client.get("/api/v1/dashboard/summary").json()
    currencies = {row["currency"] for row in summary["today_pnl_by_currency"]}
    assert "CNY" in currencies


def test_record_daily_pnl_rejected_on_non_investment_account(client) -> None:
    account = _create_balance_account(client, balance="100")
    response = client.post(
        f"/api/v1/accounts/{account['id']}/daily-pnl",
        json={"new_balance": "200"},
    )
    assert response.status_code == 400
    assert "investment" in response.json()["detail"].lower()


def test_record_daily_pnl_rejected_for_future_date(client) -> None:
    account = _create_investment_account(client, balance="1000")
    future = (date.today() + timedelta(days=1)).isoformat()
    response = client.post(
        f"/api/v1/accounts/{account['id']}/daily-pnl",
        json={"new_balance": "1050", "as_of_date": future},
    )
    assert response.status_code == 400
    assert "future" in response.json()["detail"].lower()
