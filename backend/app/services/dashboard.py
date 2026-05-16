from datetime import date
from decimal import Decimal
from typing import Dict

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.entry import FinancialEntry
from app.schemas.dashboard import DashboardSummary
from app.services.ledger import convert_to_cny, quantize_money


def get_dashboard_summary(db: Session) -> DashboardSummary:
    balance_total_cny = Decimal("0")
    credit_liability_total_cny = Decimal("0")
    today = date.today()

    accounts = db.execute(
        select(Account).where(Account.status == "active", Account.include_in_net_worth.is_(True))
    ).scalars()
    for account in accounts:
        if account.type == "balance":
            converted, _ = convert_to_cny(db, account.current_balance, account.currency, today)
            balance_total_cny += converted
        elif account.type == "credit":
            converted, _ = convert_to_cny(db, account.current_liability, account.currency, today)
            credit_liability_total_cny += converted

    entry_counts = _entry_counts_by_status(db)

    return DashboardSummary(
        base_currency="CNY",
        balance_total_cny=quantize_money(balance_total_cny),
        credit_liability_total_cny=quantize_money(credit_liability_total_cny),
        net_worth_cny=quantize_money(balance_total_cny - credit_liability_total_cny),
        draft_entry_count=entry_counts.get("draft", 0),
        confirmed_entry_count=entry_counts.get("confirmed", 0),
        voided_entry_count=entry_counts.get("voided", 0),
    )


def _entry_counts_by_status(db: Session) -> Dict[str, int]:
    rows = db.execute(
        select(FinancialEntry.status, func.count(FinancialEntry.id)).group_by(FinancialEntry.status)
    )
    return {status: count for status, count in rows}

