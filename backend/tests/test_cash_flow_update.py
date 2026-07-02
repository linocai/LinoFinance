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


# ---------------------------------------------------------------------------
# v2.4.0 #2 — system-linked cash flow edit guard (D1=甲, PROJECT_PLAN §5.3)
# ---------------------------------------------------------------------------

_SYSTEM_LINKED_MESSAGE = (
    "系统联动现金流不可直接编辑，请修改其背后的账单周期 / 分期 / 报销源；"
    "订阅项仅可补账户/分类以便结算"
)


def _create_credit_account(client, name="Chase Credit", currency="USD"):
    response = client.post(
        "/api/v1/accounts",
        json={"name": name, "type": "credit", "currency": currency},
    )
    assert response.status_code == 201, response.json()
    return response.json()


def _create_statement_cycle(client, credit_account_id, currency="USD"):
    response = client.post(
        "/api/v1/credit-statement-cycles",
        json={
            "credit_account_id": credit_account_id,
            "cycle_start_date": "2026-05-01",
            "cycle_end_date": "2026-05-31",
            "statement_date": "2026-06-01",
            "due_date": "2026-06-20",
            "currency": currency,
        },
    )
    assert response.status_code == 201, response.json()
    return response.json()


def _find_cash_flow(client, predicate):
    items = client.get("/api/v1/cash-flow-items?include_cancelled=true").json()
    return next(item for item in items if predicate(item))


def _create_subscription_cash_flow(client, with_account=False):
    """Create a subscription rule and return its generated cash flow item.

    ``with_account=False`` leaves the generated item's account/category null, so
    the ``completeAndSettle`` "fill account then settle" flow can be exercised.
    """
    body = {
        "title": "Streaming",
        "amount": "30",
        "currency": "CNY",
        "billing_interval": "monthly",
        "billing_day": 5,
        "start_date": "2026-06-05",
    }
    if with_account:
        account = _create_account(client, name="Checking", balance="100")
        category = _create_category(client, name="Streaming", category_type="expense")
        body["account_id"] = account["id"]
        body["category_id"] = category["id"]
    rule = client.post("/api/v1/subscription-rules", json=body).json()
    item = _find_cash_flow(
        client, lambda it: it.get("linked_subscription_rule_id") == rule["id"]
    )
    return rule, item


def test_update_non_linked_item_still_succeeds(client) -> None:
    # happy① — a plain (non-system-linked) item still edits freely.
    item = _create_cash_flow(client)

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"title": "改名", "amount": "50"},
    )

    assert response.status_code == 200, response.json()
    body = response.json()
    assert body["title"] == "改名"
    assert body["amount"] == "50"


def test_subscription_linked_item_allows_account_category_patch_then_settle(client) -> None:
    # happy② — subscription-linked item accepts {account_id, category_id} and can
    # then be settled through the normal settle path.
    _, item = _create_subscription_cash_flow(client, with_account=False)
    assert item["linked_subscription_rule_id"] is not None
    assert item["account_id"] is None

    account = _create_account(client, name="Checking", balance="100")
    category = _create_category(client, name="Streaming", category_type="expense")

    patch_response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"account_id": account["id"], "category_id": category["id"]},
    )
    assert patch_response.status_code == 200, patch_response.json()
    patched = patch_response.json()
    assert patched["account_id"] == account["id"]
    assert patched["category_id"] == category["id"]

    settle_response = client.post(
        f"/api/v1/cash-flow-items/{item['id']}/settle",
        json={
            "entry": {
                "title": "Streaming charge",
                "date": "2026-06-05",
                "category_lines": [
                    {
                        "category_id": category["id"],
                        "direction": "expense",
                        "amount": "30",
                        "currency": "CNY",
                    }
                ],
                "account_movements": [
                    {
                        "account_id": account["id"],
                        "movement_type": "balance_out",
                        "amount": "30",
                        "currency": "CNY",
                    }
                ],
            }
        },
    )
    assert settle_response.status_code == 200, settle_response.json()
    assert settle_response.json()["cash_flow_item"]["status"] == "settled"
    assert client.get(f"/api/v1/accounts/{account['id']}").json()[
        "current_balance"
    ] == "70.00"


def test_subscription_linked_item_rejects_amount_patch(client) -> None:
    # failure① — subscription-linked item rejects any field beyond
    # {account_id, category_id} (here: title + amount).
    _, item = _create_subscription_cash_flow(client, with_account=False)

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"title": "hacked", "amount": "999"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == _SYSTEM_LINKED_MESSAGE


def test_statement_cycle_linked_item_rejects_account_patch(client) -> None:
    # failure② — cycle-linked repayment cash flow: even an {account_id}-only patch
    # is rejected (it would be overwritten by the next source-side sync).
    _create_usd_rate(client, date="2026-05-01", rate="6.8")
    credit_account = _create_credit_account(client)
    cycle = _create_statement_cycle(client, credit_account["id"])
    category = _create_category(client, name="Flight", category_type="expense")

    charge = client.post(
        "/api/v1/entries",
        json={
            "title": "Flight",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "100",
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "100",
                    "currency": "USD",
                }
            ],
        },
    )
    assert charge.status_code == 201, charge.json()

    linked = _find_cash_flow(
        client, lambda it: it.get("linked_statement_cycle_id") == cycle["id"]
    )
    other_account = _create_account(client, name="Other USD", currency="USD")

    response = client.patch(
        f"/api/v1/cash-flow-items/{linked['id']}",
        json={"account_id": other_account["id"]},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == _SYSTEM_LINKED_MESSAGE


def test_installment_linked_item_rejects_account_patch(client) -> None:
    # failure② (installment variant) — installment-linked cash flow rejects an
    # {account_id}-only patch.
    _create_usd_rate(client, date="2026-05-01", rate="6.8")
    credit_account = _create_credit_account(client)
    _create_statement_cycle(client, credit_account["id"])
    category = _create_category(client, name="Laptop", category_type="expense")
    entry = client.post(
        "/api/v1/entries",
        json={
            "title": "Laptop",
            "date": "2026-05-16",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "1200",
                    "currency": "USD",
                }
            ],
            "account_movements": [
                {
                    "account_id": credit_account["id"],
                    "movement_type": "credit_charge",
                    "amount": "1200",
                    "currency": "USD",
                }
            ],
        },
    ).json()

    plan = client.post(
        "/api/v1/installment-plans",
        json={
            "linked_entry_id": entry["id"],
            "credit_account_id": credit_account["id"],
            "total_amount": "1200",
            "currency": "USD",
            "number_of_payments": 3,
            "start_date": "2026-06-15",
        },
    ).json()

    linked = _find_cash_flow(
        client, lambda it: it.get("linked_installment_plan_id") == plan["id"]
    )
    other_account = _create_account(client, name="Other USD", currency="USD")

    response = client.patch(
        f"/api/v1/cash-flow-items/{linked['id']}",
        json={"account_id": other_account["id"]},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == _SYSTEM_LINKED_MESSAGE


def test_reimbursement_linked_item_rejects_account_patch(client) -> None:
    # failure② (reimbursement variant) — reimbursement-linked receivable rejects
    # an {account_id}-only patch.
    account = _create_account(client, name="Wallet", balance="500")
    category = _create_category(client, name="Travel", category_type="expense")
    client.post(
        "/api/v1/entries",
        json={
            "title": "Client trip",
            "date": "2026-06-01",
            "status": "confirmed",
            "category_lines": [
                {
                    "category_id": category["id"],
                    "direction": "expense",
                    "amount": "200",
                    "currency": "CNY",
                    "reimbursable_flag": True,
                    "reimbursement_expected_date": "2026-06-30",
                }
            ],
            "account_movements": [
                {
                    "account_id": account["id"],
                    "movement_type": "balance_out",
                    "amount": "200",
                    "currency": "CNY",
                }
            ],
        },
    )

    linked = _find_cash_flow(
        client, lambda it: it.get("linked_reimbursement_id") is not None
    )
    other_account = _create_account(client, name="Other", balance="0")

    response = client.patch(
        f"/api/v1/cash-flow-items/{linked['id']}",
        json={"account_id": other_account["id"]},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == _SYSTEM_LINKED_MESSAGE


def test_settled_or_cancelled_still_rejected_before_link_guard(client) -> None:
    # failure③ — the settled/cancelled lock still fires (and takes precedence
    # over the link guard), keeping the v1.1.7 contract.
    item = _create_cash_flow(client)
    cancel = client.post(f"/api/v1/cash-flow-items/{item['id']}/cancel")
    assert cancel.status_code == 200

    response = client.patch(
        f"/api/v1/cash-flow-items/{item['id']}",
        json={"title": "x"},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == (
        "Settled or cancelled cash flow items cannot be edited"
    )
