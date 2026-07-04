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
    # v2.2.0 P1 (D1=甲): credit ``current_liability`` is derived from statement
    # cycles, not a free opening number. To stand up an account with an opening
    # liability the test expresses it as an opening statement cycle whose
    # ``statement_amount`` equals the desired liability — exactly the new single
    # source of truth (``current_liability ≡ Σcycle``).
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": "credit",
            "currency": currency,
        },
    )
    assert response.status_code == 201, response.text
    account = response.json()
    if Decimal(liability) != 0:
        cycle = client.post(
            "/api/v1/credit-statement-cycles",
            json={
                "credit_account_id": account["id"],
                "cycle_start_date": "2026-05-01",
                "cycle_end_date": "2026-05-31",
                "statement_date": "2026-06-01",
                "due_date": "2026-06-20",
                "currency": currency,
                "statement_amount": liability,
            },
        )
        assert cycle.status_code == 201, cycle.text
        account = client.get(f"/api/v1/accounts/{account['id']}").json()
    return account


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


def _by_ccy(rows):
    return {row["currency"]: Decimal(row["amount"]) for row in rows}


def _usd_rate(client, rate="7"):
    response = client.post(
        "/api/v1/currency-rates",
        json={
            "from_currency": "USD",
            "to_currency": "CNY",
            "rate": rate,
            # Fixed date on/before the hardcoded statement-cycle dates (statement
            # 2026-06-01) so the USD credit cycle's CNY conversion always finds a
            # rate ≤ cycle date — was date.today(), which drifted past the cycle
            # dates once the wall clock moved beyond them → cycle create 400.
            "date": "2026-05-01",
            "source": "manual",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_dashboard_net_worth_by_currency_mixed_accounts(client) -> None:
    # v1.4.0 P2: per-currency net-worth breakdown in original currency.
    _usd_rate(client)
    # CNY: balance 1000, investment 500, credit 300  -> net 1200
    _create_account(client, "CNYWallet", "balance", "CNY", "1000")
    _create_account(client, "CNYFunds", "investment", "CNY", "500")
    _create_credit_account(client, "CNYCard", "CNY", "300")
    # USD: balance 100, investment 40, credit 30      -> net 110
    _create_account(client, "USDWallet", "balance", "USD", "100")
    _create_account(client, "USDFunds", "investment", "USD", "40")
    _create_credit_account(client, "USDCard", "USD", "30")

    summary = client.get("/api/v1/dashboard/summary").json()

    balance = _by_ccy(summary["balance_total_by_currency"])
    credit = _by_ccy(summary["credit_liability_by_currency"])
    net = _by_ccy(summary["net_worth_by_currency"])

    assert balance == {"CNY": Decimal("1000"), "USD": Decimal("100")}
    assert credit == {"CNY": Decimal("300"), "USD": Decimal("30")}
    # net = balance + investment - credit, per currency, no FX conversion.
    assert net == {"CNY": Decimal("1200"), "USD": Decimal("110")}


def test_dashboard_net_worth_by_currency_cny_only(client) -> None:
    # No USD account: USD must not appear, CNY is always present.
    _create_account(client, "CNYWallet", "balance", "CNY", "800")
    _create_credit_account(client, "CNYCard", "CNY", "200")

    summary = client.get("/api/v1/dashboard/summary").json()

    balance = _by_ccy(summary["balance_total_by_currency"])
    credit = _by_ccy(summary["credit_liability_by_currency"])
    net = _by_ccy(summary["net_worth_by_currency"])

    assert balance == {"CNY": Decimal("800")}
    assert credit == {"CNY": Decimal("200")}
    assert net == {"CNY": Decimal("600")}
    assert "USD" not in balance and "USD" not in credit and "USD" not in net


def test_dashboard_net_worth_by_currency_omits_zero_usd_net(client) -> None:
    # USD balance exactly offsets USD credit -> USD net is 0, so the USD net row
    # is omitted (`_pack_with_cny_floor` "non-zero only"); CNY stays present.
    # USD balance still appears (it is non-zero) and so does USD credit.
    _usd_rate(client)
    _create_account(client, "CNYWallet", "balance", "CNY", "1000")
    _create_account(client, "USDWallet", "balance", "USD", "50")
    _create_credit_account(client, "USDCard", "USD", "50")

    summary = client.get("/api/v1/dashboard/summary").json()

    balance = _by_ccy(summary["balance_total_by_currency"])
    credit = _by_ccy(summary["credit_liability_by_currency"])
    net = _by_ccy(summary["net_worth_by_currency"])

    # Non-zero USD balance/credit still surface.
    assert balance == {"CNY": Decimal("1000"), "USD": Decimal("50")}
    assert credit == {"CNY": Decimal("0"), "USD": Decimal("50")}
    # USD net = 50 - 50 = 0 -> omitted; CNY net = 1000 always present.
    assert net == {"CNY": Decimal("1000")}
    assert "USD" not in net
