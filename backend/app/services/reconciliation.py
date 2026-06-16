from decimal import Decimal
from typing import Dict, Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.audit_log import AuditLog
from app.models.entry import AccountMovement
from app.models.reconciliation import AccountAdjustment
from app.schemas.reconciliation import (
    AccountAdjustmentCreate,
    ReconciliationAccountRead,
    ReconciliationAccountsResponse,
)
from app.services.ledger import (
    LedgerNotFoundError,
    LedgerValidationError,
    quantize_money,
    sum_open_statement_total,
)

RECONCILIATION_THRESHOLD = Decimal("0.01")


def list_account_reconciliation(db: Session) -> ReconciliationAccountsResponse:
    items = [
        _reconciliation_row(db, account)
        for account in db.execute(select(Account).order_by(Account.display_order, Account.name)).scalars()
    ]
    return ReconciliationAccountsResponse(threshold=RECONCILIATION_THRESHOLD, items=items)


def create_adjustment(db: Session, payload: AccountAdjustmentCreate) -> AccountAdjustment:
    account = db.get(Account, payload.account_id)
    if account is None:
        raise LedgerNotFoundError("Account not found")

    # v2.2.0 P1 (D1=甲): credit ``current_liability`` is a derived value
    # (``Σcycle``), so the legacy "set the field to an observed actual amount"
    # path would immediately violate the single source of truth and be
    # overwritten on the next movement. Credit corrections must go through the
    # cycle / recompute path instead, so直接对账信用账户余额走旧机制一律拒绝.
    if account.type == "credit":
        raise LedgerValidationError(
            "Credit accounts cannot be reconciled by setting an actual liability; "
            "their liability is derived from statement cycles — correct the cycles "
            "or use credit recompute instead"
        )

    expected_before = _expected_amount(db, account)
    current_before = _current_amount(account)
    observed_amount = quantize_money(payload.actual_amount or current_before)
    delta = quantize_money(observed_amount - expected_before)
    if delta == 0:
        raise LedgerValidationError("No reconciliation delta to adjust")

    adjustment = AccountAdjustment(
        account_id=account.id,
        reason=payload.reason,
        delta_amount=delta,
        currency=account.currency,
        balance_before=current_before,
        balance_after=observed_amount,
        source="reconciliation",
        note=payload.note,
        created_by=payload.created_by,
    )
    db.add(adjustment)
    # Credit accounts are rejected above; only balance/investment reach here.
    account.current_balance = observed_amount
    db.flush()
    db.add(
        AuditLog(
            actor=payload.created_by,
            action_type="account_adjustment.create",
            target_type="account",
            target_id=account.id,
            before_snapshot={
                "expected_amount": str(expected_before),
                "current_amount": str(current_before),
                "delta_amount": str(current_before - expected_before),
                "currency": account.currency,
            },
            after_snapshot={
                "expected_amount": str(expected_before + delta),
                "current_amount": str(observed_amount),
                "delta_amount": "0.00",
                "currency": account.currency,
                "adjustment_id": adjustment.id,
                "reason": payload.reason,
            },
            note=payload.note,
        )
    )
    db.commit()
    db.refresh(adjustment)
    return adjustment


def _reconciliation_row(db: Session, account: Account) -> ReconciliationAccountRead:
    expected = _expected_amount(db, account)
    current = _current_amount(account)
    delta = quantize_money(current - expected)
    return ReconciliationAccountRead(
        account_id=account.id,
        account_name=account.name,
        account_type=account.type,
        currency=account.currency,
        expected_amount=expected,
        current_amount=current,
        delta_amount=delta,
        needs_adjustment=abs(delta) > RECONCILIATION_THRESHOLD,
    )


def _expected_amount(db: Session, account: Account) -> Decimal:
    if account.type == "credit":
        # v2.2.0 P1: credit liability has a single source of truth —
        # ``Σ(non-voided cycle: statement_amount − paid_amount)``. The stored
        # ``current_liability`` is a cache of exactly this, so expected and
        # current can never disagree (no more恒等-but-drifting double truth).
        return _credit_cycle_total(db, account.id)
    movements = _movement_totals(db, account.id)
    adjustments = _adjustment_total(db, account.id)
    return quantize_money(
        movements["balance_in"]
        + movements["transfer_in"]
        - movements["balance_out"]
        - movements["transfer_out"]
        - movements["credit_repayment"]
        + adjustments
    )


def _movement_totals(db: Session, account_id: str) -> Dict[str, Decimal]:
    totals = {
        "balance_in": Decimal("0"),
        "balance_out": Decimal("0"),
        "transfer_in": Decimal("0"),
        "transfer_out": Decimal("0"),
        "credit_charge": Decimal("0"),
        "credit_repayment": Decimal("0"),
    }
    rows: Iterable[AccountMovement] = db.execute(
        select(AccountMovement).where(AccountMovement.account_id == account_id)
    ).scalars()
    for movement in rows:
        if movement.movement_type in totals:
            totals[movement.movement_type] = quantize_money(
                totals[movement.movement_type] + movement.amount
            )
    return totals


def _adjustment_total(db: Session, account_id: str) -> Decimal:
    total = Decimal("0")
    rows: Iterable[AccountAdjustment] = db.execute(
        select(AccountAdjustment).where(AccountAdjustment.account_id == account_id)
    ).scalars()
    for adjustment in rows:
        total = quantize_money(total + adjustment.delta_amount)
    return total


def _credit_cycle_total(db: Session, account_id: str) -> Decimal:
    # Single source of truth shared with the ledger recompute writer (v2.2.0 P1).
    return sum_open_statement_total(db, account_id)


def _current_amount(account: Account) -> Decimal:
    if account.type == "credit":
        return quantize_money(account.current_liability)
    return quantize_money(account.current_balance)
