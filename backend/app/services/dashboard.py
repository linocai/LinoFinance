from datetime import date, timedelta
from decimal import Decimal
from typing import Dict, List

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.timeutils import app_today, utc_to_app_date
from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.entry import FinancialEntry
from app.models.reconciliation import AccountAdjustment
from app.schemas.dashboard import CurrencyAmount, DashboardSummary
from app.services.ledger import convert_to_cny, quantize_money

ACTIVE_CASH_FLOW_STATUSES = {"expected", "confirmed", "partial"}
DAILY_PNL_SOURCE = "investment_daily"


def get_dashboard_summary(db: Session) -> DashboardSummary:
    today = app_today()

    balance_total_cny = Decimal("0")
    credit_liability_total_cny = Decimal("0")
    investment_total_cny = Decimal("0")

    by_ccy_balance: Dict[str, Decimal] = {}
    by_ccy_invest: Dict[str, Decimal] = {}

    accounts = db.execute(
        select(Account).where(
            Account.status == "active",
            Account.include_in_net_worth.is_(True),
        )
    ).scalars()
    for account in accounts:
        if account.type == "credit":
            converted, _ = convert_to_cny(
                db, account.current_liability, account.currency, today
            )
            credit_liability_total_cny += converted
        elif account.type == "investment":
            converted, _ = convert_to_cny(
                db, account.current_balance, account.currency, today
            )
            investment_total_cny += converted
            by_ccy_invest[account.currency] = (
                by_ccy_invest.get(account.currency, Decimal("0"))
                + account.current_balance
            )
        else:  # balance and any future non-credit type
            converted, _ = convert_to_cny(
                db, account.current_balance, account.currency, today
            )
            balance_total_cny += converted
            by_ccy_balance[account.currency] = (
                by_ccy_balance.get(account.currency, Decimal("0"))
                + account.current_balance
            )

    today_pnl = _today_pnl_by_currency(db, today)
    cash_flow_30d = _cash_flow_30d_by_currency(db, today)
    disposable = _disposable_30d_by_currency(by_ccy_balance, cash_flow_30d)
    investment_by_ccy = _pack_investment_by_currency(by_ccy_invest)

    entry_counts = _entry_counts_by_status(db)

    return DashboardSummary(
        base_currency="CNY",
        balance_total_cny=quantize_money(balance_total_cny),
        credit_liability_total_cny=quantize_money(credit_liability_total_cny),
        net_worth_cny=quantize_money(
            balance_total_cny + investment_total_cny - credit_liability_total_cny
        ),
        draft_entry_count=entry_counts.get("draft", 0),
        confirmed_entry_count=entry_counts.get("confirmed", 0),
        voided_entry_count=entry_counts.get("voided", 0),
        investment_total_cny=quantize_money(investment_total_cny),
        investment_total_by_currency=investment_by_ccy,
        today_pnl_by_currency=today_pnl,
        disposable_30d_by_currency=disposable,
        cash_flow_30d_by_currency=cash_flow_30d,
    )


def _entry_counts_by_status(db: Session) -> Dict[str, int]:
    rows = db.execute(
        select(FinancialEntry.status, func.count(FinancialEntry.id)).group_by(
            FinancialEntry.status
        )
    )
    return {status: count for status, count in rows}


def _pack_investment_by_currency(
    totals: Dict[str, Decimal],
) -> List[CurrencyAmount]:
    return [
        CurrencyAmount(currency=ccy, amount=quantize_money(amount))
        for ccy, amount in sorted(totals.items())
        if amount != 0
    ]


def _today_pnl_by_currency(db: Session, today: date) -> List[CurrencyAmount]:
    # Aggregate daily-pnl adjustments whose adjustment date equals today.
    # We pull all rows with source='investment_daily' for active investment
    # accounts, then bucket created_at to the business-timezone calendar date on
    # the Python side (audit §3.4) — portable across SQLite (test runner) and
    # PostgreSQL (prod), and correct across the UTC day boundary.
    rows = db.execute(
        select(AccountAdjustment, Account)
        .join(Account, AccountAdjustment.account_id == Account.id)
        .where(
            AccountAdjustment.source == DAILY_PNL_SOURCE,
            Account.type == "investment",
        )
    ).all()

    totals_today: Dict[str, Decimal] = {}
    seen_currencies: set = set()
    for adjustment, _account in rows:
        created_date = (
            utc_to_app_date(adjustment.created_at) if adjustment.created_at else None
        )
        if created_date != today:
            continue
        seen_currencies.add(adjustment.currency)
        totals_today[adjustment.currency] = (
            totals_today.get(adjustment.currency, Decimal("0"))
            + adjustment.delta_amount
        )

    # Include any currency that had at least one daily-pnl row today, even if
    # the net delta is exactly 0 — the user should see "0 today" not nothing.
    return [
        CurrencyAmount(
            currency=ccy,
            amount=quantize_money(totals_today.get(ccy, Decimal("0"))),
        )
        for ccy in sorted(seen_currencies)
    ]


def _cash_flow_30d_by_currency(db: Session, today: date) -> List[CurrencyAmount]:
    window_end = today + timedelta(days=30)
    totals: Dict[str, Decimal] = {"CNY": Decimal("0")}

    statement = select(CashFlowItem).where(
        CashFlowItem.status.in_(ACTIVE_CASH_FLOW_STATUSES),
        CashFlowItem.expected_date >= today,
        CashFlowItem.expected_date < window_end,
    )
    for item in db.execute(statement).scalars():
        amount = item.amount or Decimal("0")
        signed = amount if item.direction == "inflow" else -amount
        totals[item.currency] = totals.get(item.currency, Decimal("0")) + signed

    return _pack_with_cny_floor(totals)


def _disposable_30d_by_currency(
    balance_by_ccy: Dict[str, Decimal],
    cash_flow_30d: List[CurrencyAmount],
) -> List[CurrencyAmount]:
    cash_flow_by_ccy = {row.currency: row.amount for row in cash_flow_30d}
    currencies = set(balance_by_ccy.keys()) | set(cash_flow_by_ccy.keys()) | {"CNY"}
    totals: Dict[str, Decimal] = {}
    for ccy in currencies:
        totals[ccy] = balance_by_ccy.get(ccy, Decimal("0")) + cash_flow_by_ccy.get(
            ccy, Decimal("0")
        )
    return _pack_with_cny_floor(totals)


def _pack_with_cny_floor(totals: Dict[str, Decimal]) -> List[CurrencyAmount]:
    """Always include CNY; include other currencies only when non-zero."""
    result: List[CurrencyAmount] = []
    for ccy in sorted(totals.keys()):
        amount = totals[ccy]
        if ccy == "CNY" or amount != 0:
            result.append(
                CurrencyAmount(currency=ccy, amount=quantize_money(amount))
            )
    if not any(row.currency == "CNY" for row in result):
        result.insert(0, CurrencyAmount(currency="CNY", amount=quantize_money(Decimal("0"))))
    return result
