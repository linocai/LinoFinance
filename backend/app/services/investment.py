from datetime import date as DateType
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.audit_log import AuditLog
from app.models.reconciliation import AccountAdjustment
from app.schemas.investment import DailyPnLCreate, DailyPnLRead
from app.services.ledger import (
    LedgerNotFoundError,
    LedgerValidationError,
    quantize_money,
)

DAILY_PNL_SOURCE = "investment_daily"
DAILY_PNL_REASON = "daily_pnl"
DAILY_PNL_ACTION = "account.daily_pnl"


def record_daily_pnl(
    db: Session, account_id: str, payload: DailyPnLCreate
) -> DailyPnLRead:
    account = db.get(Account, account_id)
    if account is None:
        raise LedgerNotFoundError("Account not found")
    if account.type != "investment":
        raise LedgerValidationError(
            "Daily P&L is only allowed on investment accounts"
        )
    if account.status != "active":
        raise LedgerValidationError(
            "Daily P&L is not allowed on inactive accounts"
        )

    as_of_date = payload.as_of_date or DateType.today()
    if as_of_date > DateType.today():
        raise LedgerValidationError("Daily P&L date cannot be in the future")

    balance_before = quantize_money(account.current_balance or Decimal("0"))
    balance_after = quantize_money(payload.new_balance)
    delta = quantize_money(balance_after - balance_before)

    adjustment = AccountAdjustment(
        account_id=account.id,
        reason=DAILY_PNL_REASON,
        delta_amount=delta,
        currency=account.currency,
        balance_before=balance_before,
        balance_after=balance_after,
        source=DAILY_PNL_SOURCE,
        note=payload.note,
        created_by="user",
    )
    db.add(adjustment)
    account.current_balance = balance_after
    db.flush()
    db.add(
        AuditLog(
            actor="user",
            action_type=DAILY_PNL_ACTION,
            target_type="account",
            target_id=account.id,
            before_snapshot={"current_balance": str(balance_before)},
            after_snapshot={
                "current_balance": str(balance_after),
                "delta": str(delta),
                "as_of_date": as_of_date.isoformat(),
            },
            note=payload.note,
        )
    )
    db.commit()
    db.refresh(adjustment)

    return DailyPnLRead(
        adjustment_id=adjustment.id,
        account_id=account.id,
        currency=account.currency,
        balance_before=balance_before,
        balance_after=balance_after,
        delta_amount=delta,
        as_of_date=as_of_date,
        source=DAILY_PNL_SOURCE,
    )
