def create_account(client, name, account_type, currency="CNY", balance="0"):
    response = client.post(
        "/api/v1/accounts",
        json={
            "name": name,
            "type": account_type,
            "currency": currency,
            "current_balance": balance,
        },
    )
    assert response.status_code == 201
    return response.json()


def create_category(client, name, category_type="expense"):
    response = client.post("/api/v1/categories", json={"name": name, "type": category_type})
    assert response.status_code == 201
    return response.json()


def create_confirmed_expense(
    client,
    account_id,
    category_id,
    amount="200",
    reimbursable=False,
):
    line = {
        "category_id": category_id,
        "direction": "expense",
        "amount": amount,
        "currency": "CNY",
        "reimbursable_flag": reimbursable,
    }
    if reimbursable:
        line["reimbursement_payer"] = "Company"
        line["reimbursement_expected_date"] = "2026-05-25"

    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Dinner",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [line],
            "account_movements": [
                {
                    "account_id": account_id,
                    "movement_type": "balance_out",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 201
    return response.json()


def create_confirmed_income(client, account_id, category_id, amount="500"):
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Salary",
            "date": "2026-05-10",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category_id,
                    "direction": "income",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": account_id,
                    "movement_type": "balance_in",
                    "amount": amount,
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_monthly_category_and_reimbursement_reports(client) -> None:
    checking = create_account(client, "Checking", "balance", balance="1000")
    food = create_category(client, "Food")
    salary = create_category(client, "Salary", "income")
    create_confirmed_expense(client, checking["id"], food["id"], reimbursable=True)
    create_confirmed_income(client, checking["id"], salary["id"])

    monthly = client.get(
        "/api/v1/reports/monthly-overview",
        params={"date_from": "2026-05-01", "date_to": "2026-05-31"},
    )
    assert monthly.status_code == 200
    monthly_body = monthly.json()
    assert monthly_body["income_cny"] == "500"
    assert monthly_body["expense_cny"] == "200"
    assert monthly_body["expected_reimbursement_cny"] == "200"
    assert monthly_body["personal_net_expense_cny"] == "0"
    assert monthly_body["future_inflow_cny"] == "200"

    category_report = client.get(
        "/api/v1/reports/category-expenses",
        params={"date_from": "2026-05-01", "date_to": "2026-05-31"},
    )
    assert category_report.status_code == 200
    category_body = category_report.json()
    assert category_body["total_expense_cny"] == "200"
    assert category_body["rows"][0]["category_name"] == "Food"
    assert category_body["rows"][0]["currencies"] == [
        {"currency": "CNY", "amount": "200", "converted_cny_amount": "200"}
    ]

    reimbursement = client.get(
        "/api/v1/reports/reimbursements",
        params={
            "date_from": "2026-05-01",
            "date_to": "2026-05-31",
            "view": "expected_net",
        },
    )
    assert reimbursement.status_code == 200
    reimbursement_body = reimbursement.json()
    assert reimbursement_body["gross_reimbursable_expense_cny"] == "200"
    assert reimbursement_body["expected_offset_cny"] == "200"
    assert reimbursement_body["selected_net_expense_cny"] == "0"


def test_reimbursement_reports_anchor_all_views_on_original_expense_date(client) -> None:
    # P5 / audit 2.2: all five reimbursement views (and the monthly-overview
    # offsets) anchor on the ORIGINAL expense date. Here the expense is in May
    # but the cash is received in June. Pre-fix, the June report subtracted a
    # `received` offset against a zero gross and produced a spurious -200 net;
    # now the entire claim lives in the May window and June shows no offset.
    checking = create_account(client, "Checking", "balance", balance="1000")
    travel = create_category(client, "Travel")
    reimbursement_income = create_category(client, "Reimbursement Income", "income")

    expense = client.post(
        "/api/v1/entries",
        json={
            "title": "May client trip",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": travel["id"],
                    "direction": "expense",
                    "amount": "200",
                    "currency": "CNY",
                    "reimbursable_flag": True,
                    "reimbursement_payer": "Company",
                    "reimbursement_expected_date": "2026-06-10",
                    "reimbursement_status": "pending",
                }
            ],
            "account_movements": [
                {
                    "account_id": checking["id"],
                    "movement_type": "balance_out",
                    "amount": "200",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert expense.status_code == 201
    claim = client.get("/api/v1/reimbursement-claims").json()[0]

    receive_response = client.post(
        f"/api/v1/reimbursement-claims/{claim['id']}/mark-received",
        json={
            "actual_received_date": "2026-06-11",
            "received_account_id": checking["id"],
            "entry": {
                "title": "Company reimbursement",
                "date": "2026-06-11",
                "category_lines": [
                    {
                        "category_id": reimbursement_income["id"],
                        "direction": "income",
                        "amount": "200",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": checking["id"],
                        "movement_type": "balance_in",
                        "amount": "200",
                        "currency": "CNY",
                    }
                ],
            },
        },
    )
    assert receive_response.status_code == 200

    # May window: the original expense (5/16) anchors gross AND every offset —
    # including `received`, even though the cash landed on 6/11.
    may_report = client.get(
        "/api/v1/reports/reimbursements",
        params={
            "date_from": "2026-05-01",
            "date_to": "2026-05-31",
            "view": "received_net",
        },
    ).json()
    assert may_report["gross_reimbursable_expense_cny"] == "200"
    assert may_report["expected_offset_cny"] == "200"
    assert may_report["approved_offset_cny"] == "200"
    assert may_report["received_offset_cny"] == "200"
    assert may_report["received_net_expense_cny"] == "0"

    # June window: the original expense is out of range, so the whole claim is
    # excluded — no spurious negative net from a dangling `received` offset.
    june_report = client.get(
        "/api/v1/reports/reimbursements",
        params={
            "date_from": "2026-06-01",
            "date_to": "2026-06-30",
            "view": "received_net",
        },
    ).json()
    assert june_report["gross_reimbursable_expense_cny"] == "0"
    assert june_report["expected_offset_cny"] == "0"
    assert june_report["approved_offset_cny"] == "0"
    assert june_report["received_offset_cny"] == "0"
    assert june_report["received_net_expense_cny"] == "0"

    # Monthly overview offsets follow the same original-date anchor. Entry totals
    # (income/expense) still follow each entry's own date.
    may_overview = client.get(
        "/api/v1/reports/monthly-overview",
        params={"date_from": "2026-05-01", "date_to": "2026-05-31"},
    ).json()
    assert may_overview["income_cny"] == "0"
    assert may_overview["expense_cny"] == "200"
    assert may_overview["expected_reimbursement_cny"] == "200"
    assert may_overview["approved_reimbursement_cny"] == "200"
    assert may_overview["received_reimbursement_cny"] == "200"
    # personal_net_expense_cny keeps its full-expense口径 (expense - expected).
    assert may_overview["personal_net_expense_cny"] == "0"

    june_overview = client.get(
        "/api/v1/reports/monthly-overview",
        params={"date_from": "2026-06-01", "date_to": "2026-06-30"},
    ).json()
    assert june_overview["income_cny"] == "200"
    assert june_overview["expense_cny"] == "0"
    assert june_overview["expected_reimbursement_cny"] == "0"
    assert june_overview["received_reimbursement_cny"] == "0"


def test_reimbursement_report_legacy_view_is_rejected(client) -> None:
    # v2.1.0 P2: the view parameter is collapsed to three values; legacy values
    # (pre_reimbursement / approved_net) are rejected with 422.
    for legacy_view in ("pre_reimbursement", "approved_net"):
        response = client.get(
            "/api/v1/reports/reimbursements",
            params={
                "date_from": "2026-05-01",
                "date_to": "2026-05-31",
                "view": legacy_view,
            },
        )
        assert response.status_code == 422, legacy_view

    for new_view in ("expected_net", "received_net", "personal_net"):
        response = client.get(
            "/api/v1/reports/reimbursements",
            params={
                "date_from": "2026-05-01",
                "date_to": "2026-05-31",
                "view": new_view,
            },
        )
        assert response.status_code == 200, new_view


def test_cash_flow_pressure_and_subscription_report(client) -> None:
    checking = create_account(client, "Checking", "balance", balance="1000")
    streaming = create_category(client, "Streaming")

    response = client.post(
        "/api/v1/subscription-rules",
        json={
            "title": "Streaming",
            "amount": "30",
            "currency": "CNY",
            "account_id": checking["id"],
            "category_id": streaming["id"],
            "billing_interval": "monthly",
            "billing_day": 5,
            "start_date": "2026-06-05",
        },
    )
    assert response.status_code == 201

    pressure = client.get(
        "/api/v1/reports/cash-flow-pressure",
        params={"anchor_date": "2026-06-01"},
    )
    assert pressure.status_code == 200
    windows = pressure.json()["windows"]
    assert windows[0]["days"] == 7
    assert windows[0]["expected_outflow_cny"] == "30"
    assert windows[1]["expected_outflow_cny"] == "30"

    subscriptions = client.get(
        "/api/v1/reports/subscriptions",
        params={"as_of": "2026-06-05"},
    )
    assert subscriptions.status_code == 200
    body = subscriptions.json()
    assert body["active_subscription_count"] == 1
    assert body["monthly_total_cny"] == "30"
    assert body["annual_total_cny"] == "360"
    assert body["upcoming_30_days_cny"] == "30"


def test_credit_liability_trend_report(client) -> None:
    credit = create_account(client, "CNY Credit", "credit")
    food = create_category(client, "Food")
    cycle = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit["id"],
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": "CNY",
        },
    )
    assert cycle.status_code == 201
    response = client.post(
        "/api/v1/entries",
        json={
            "title": "Camera",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": food["id"],
                    "direction": "expense",
                    "amount": "400",
                    "currency": "CNY",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit["id"],
                    "movement_type": "credit_charge",
                    "amount": "400",
                    "currency": "CNY",
                }
            ],
        },
    )
    assert response.status_code == 201

    trend = client.get(
        "/api/v1/reports/credit-liability-trend",
        params={"date_from": "2026-06-01", "date_to": "2026-06-30"},
    )
    assert trend.status_code == 200
    body = trend.json()
    assert body["total_remaining_cny"] == "400"
    assert body["rows"][0]["account_name"] == "CNY Credit"
    assert body["rows"][0]["remaining_amount"] == "400"


def test_csv_exports_include_core_ledger_data(client) -> None:
    checking = create_account(client, "Checking", "balance", balance="1000")
    food = create_category(client, "Food")
    create_confirmed_expense(client, checking["id"], food["id"], amount="88")

    datasets = client.get("/api/v1/exports/csv")
    assert datasets.status_code == 200
    dataset_names = {dataset["name"] for dataset in datasets.json()["datasets"]}
    assert {"entries", "entry_category_lines", "account_movements", "audit_logs"}.issubset(
        dataset_names
    )

    entries_csv = client.get("/api/v1/exports/csv/entries")
    assert entries_csv.status_code == 200
    assert entries_csv.headers["content-type"].startswith("text/csv")
    assert "title,entry_type,date" in entries_csv.text
    assert "Dinner" in entries_csv.text

    movements_csv = client.get("/api/v1/exports/csv/account_movements")
    assert movements_csv.status_code == 200
    assert "amount,currency,exchange_rate_id,converted_cny_amount" in movements_csv.text
    assert ",88,CNY,,88," in movements_csv.text

    unsupported = client.get("/api/v1/exports/csv/unknown")
    assert unsupported.status_code == 400
