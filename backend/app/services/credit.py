from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.credit_statement_cycle import CreditStatementCycle
from app.schemas.credit_statement_cycle import (
    CreditStatementCycleCreate,
    CreditStatementCycleRead,
    CreditStatementCycleUpdate,
)
from app.services.ledger import (
    LedgerNotFoundError,
    LedgerValidationError,
    quantize_money,
    recompute_credit_liability,
    sync_credit_statement_cash_flow,
)


def create_statement_cycle(
    db: Session,
    payload: CreditStatementCycleCreate,
) -> CreditStatementCycleRead:
    account = _get_credit_account(db, payload.credit_account_id)
    data = payload.normalized_dump()
    _validate_cycle_payload(account, data)
    _validate_no_cycle_overlap(db, data)

    cycle = CreditStatementCycle(**data)
    cycle.statement_amount = quantize_money(cycle.statement_amount)
    cycle.minimum_payment = quantize_money(cycle.minimum_payment)
    cycle.paid_amount = quantize_money(cycle.paid_amount)
    _refresh_cycle_status(cycle)

    db.add(cycle)
    db.flush()
    if cycle.statement_amount > 0:
        sync_credit_statement_cash_flow(db, cycle)
    # ``current_liability`` is derived from cycles (v2.2.0 P1): a non-zero opening
    # statement immediately raises the account's liability via the single source
    # of truth, so an opening balance is *expressed as a cycle* and can never
    # drift away from ``Σcycle``.
    recompute_credit_liability(db, account)
    db.commit()
    db.refresh(cycle)
    result = CreditStatementCycleRead.from_model(cycle)
    if cycle.status == "statement_generated":
        try:
            from app.services import push_dispatch

            push_dispatch.dispatch_credit_statement_generated(db, cycle.id)
        except Exception:
            pass
    return result


def list_statement_cycles(
    db: Session,
    credit_account_id: Optional[str] = None,
) -> List[CreditStatementCycleRead]:
    statement = select(CreditStatementCycle)
    if credit_account_id is not None:
        statement = statement.where(CreditStatementCycle.credit_account_id == credit_account_id)
    cycles = db.execute(
        statement.order_by(CreditStatementCycle.statement_date.desc(), CreditStatementCycle.due_date.desc())
    ).scalars()
    return [CreditStatementCycleRead.from_model(cycle) for cycle in cycles]


def get_statement_cycle(db: Session, cycle_id: str) -> CreditStatementCycleRead:
    cycle = db.get(CreditStatementCycle, cycle_id)
    if cycle is None:
        raise LedgerNotFoundError("Credit statement cycle not found")
    return CreditStatementCycleRead.from_model(cycle)


def update_statement_cycle(
    db: Session,
    cycle_id: str,
    payload: CreditStatementCycleUpdate,
) -> CreditStatementCycleRead:
    """Patch a credit statement cycle (v2.3.0 P1).

    ``model_fields_set`` distinguishes "field absent" (leave unchanged) from a
    supplied value. Editing a ``voided`` cycle is rejected (use create instead).
    After mutation the linked repayment cash flow is re-synced and the account's
    ``current_liability`` is re-derived from ``Σcycle`` — preserving the core
    invariant ``current_liability ≡ Σ(non-voided cycle: statement − paid)``.
    """
    cycle = _get_cycle_or_raise(db, cycle_id)
    if cycle.status == "voided":
        raise LedgerValidationError("Voided statement cycles cannot be edited")
    account = _get_credit_account(db, cycle.credit_account_id)

    provided = payload.model_fields_set
    if "cycle_start_date" in provided:
        cycle.cycle_start_date = payload.cycle_start_date
    if "cycle_end_date" in provided:
        cycle.cycle_end_date = payload.cycle_end_date
    if "statement_date" in provided:
        cycle.statement_date = payload.statement_date
    if "due_date" in provided:
        cycle.due_date = payload.due_date
    if "statement_amount" in provided:
        cycle.statement_amount = quantize_money(payload.statement_amount)
    if "minimum_payment" in provided:
        cycle.minimum_payment = quantize_money(payload.minimum_payment)
    if "paid_amount" in provided:
        cycle.paid_amount = quantize_money(payload.paid_amount)
    if "note" in provided:
        cycle.note = payload.note

    data = {
        "currency": cycle.currency,
        "cycle_start_date": cycle.cycle_start_date,
        "cycle_end_date": cycle.cycle_end_date,
        "statement_date": cycle.statement_date,
        "due_date": cycle.due_date,
        "statement_amount": cycle.statement_amount,
        "paid_amount": cycle.paid_amount,
        "credit_account_id": cycle.credit_account_id,
    }
    _validate_cycle_payload(account, data)
    _validate_no_cycle_overlap(db, data, exclude_cycle_id=cycle.id)

    _refresh_cycle_status(cycle)
    return _finalize_cycle_mutation(db, cycle, account)


def mark_cycle_paid(db: Session, cycle_id: str) -> CreditStatementCycleRead:
    """Mark a cycle fully paid (v2.3.0 P1): ``paid := statement``, status
    ``paid``. This only mutates the cycle + recomputes liability (no
    ``credit_repayment`` movement), so it never double-decrements against the
    settle-via-cash-flow path. Already-voided cycles are rejected.
    """
    cycle = _get_cycle_or_raise(db, cycle_id)
    if cycle.status == "voided":
        raise LedgerValidationError("Voided statement cycles cannot be marked paid")
    account = _get_credit_account(db, cycle.credit_account_id)

    cycle.paid_amount = quantize_money(cycle.statement_amount)
    cycle.status = "paid"
    return _finalize_cycle_mutation(db, cycle, account)


def void_cycle(db: Session, cycle_id: str) -> CreditStatementCycleRead:
    """Void a cycle (v2.3.0 P1): status → ``voided`` (excluded from
    ``Σcycle``), the linked repayment cash flow is cancelled, and liability is
    re-derived. Idempotent: voiding an already-voided cycle returns it unchanged.
    """
    cycle = _get_cycle_or_raise(db, cycle_id)
    account = _get_credit_account(db, cycle.credit_account_id)
    if cycle.status == "voided":
        return CreditStatementCycleRead.from_model(cycle)

    cycle.status = "voided"
    linked = _get_linked_cash_flow(db, cycle)
    if linked is not None and linked.status not in {"settled", "cancelled"}:
        linked.status = "cancelled"
    recompute_credit_liability(db, account)
    db.commit()
    db.refresh(cycle)
    return CreditStatementCycleRead.from_model(cycle)


def _finalize_cycle_mutation(
    db: Session,
    cycle: CreditStatementCycle,
    account: Account,
) -> CreditStatementCycleRead:
    """Shared tail for cycle edit / mark-paid: re-sync the linked repayment
    cash flow then re-derive ``current_liability`` from ``Σcycle``.
    """
    sync_credit_statement_cash_flow(db, cycle)
    recompute_credit_liability(db, account)
    db.commit()
    db.refresh(cycle)
    return CreditStatementCycleRead.from_model(cycle)


def _get_cycle_or_raise(db: Session, cycle_id: str) -> CreditStatementCycle:
    cycle = db.get(CreditStatementCycle, cycle_id)
    if cycle is None:
        raise LedgerNotFoundError("Credit statement cycle not found")
    return cycle


def _get_linked_cash_flow(
    db: Session,
    cycle: CreditStatementCycle,
) -> Optional[CashFlowItem]:
    if cycle.linked_cash_flow_item_id is None:
        return None
    return db.get(CashFlowItem, cycle.linked_cash_flow_item_id)


def _get_credit_account(db: Session, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None:
        raise LedgerValidationError("Credit account not found")
    if account.type != "credit":
        raise LedgerValidationError("Statement cycles can only be created for credit accounts")
    return account


def _validate_cycle_payload(account: Account, data: dict) -> None:
    if data["currency"] != account.currency:
        raise LedgerValidationError("Statement cycle currency must match credit account currency")
    if data["cycle_start_date"] > data["cycle_end_date"]:
        raise LedgerValidationError("Cycle start date cannot be after cycle end date")
    if data["statement_date"] < data["cycle_end_date"]:
        raise LedgerValidationError("Statement date cannot be before cycle end date")
    if data["due_date"] < data["statement_date"]:
        raise LedgerValidationError("Due date cannot be before statement date")
    if data["paid_amount"] > data["statement_amount"]:
        raise LedgerValidationError("Paid amount cannot exceed statement amount")


def _validate_no_cycle_overlap(
    db: Session,
    data: dict,
    exclude_cycle_id: Optional[str] = None,
) -> None:
    """Reject a new cycle whose [start, end] interval overlaps an existing
    cycle for the same credit account (audit 2.6).

    Consumption auto-assignment (ledger picks `cycle_start_date desc limit 1`)
    silently mis-attributes charges when cycles overlap, so overlaps must be
    blocked at creation time. Two inclusive intervals overlap iff
    ``new_start <= other_end AND other_start <= new_end``. Voided cycles do not
    reserve their interval. ``exclude_cycle_id`` skips the cycle being edited so
    a cycle never reports as overlapping itself (v2.3.0 P1).
    """
    new_start = data["cycle_start_date"]
    new_end = data["cycle_end_date"]
    conditions = [
        CreditStatementCycle.credit_account_id == data["credit_account_id"],
        CreditStatementCycle.status != "voided",
        CreditStatementCycle.cycle_start_date <= new_end,
        CreditStatementCycle.cycle_end_date >= new_start,
    ]
    if exclude_cycle_id is not None:
        conditions.append(CreditStatementCycle.id != exclude_cycle_id)
    overlap = db.execute(
        select(CreditStatementCycle).where(*conditions)
    ).scalars().first()
    if overlap is not None:
        raise LedgerValidationError(
            "Statement cycle date range overlaps an existing cycle "
            f"({overlap.cycle_start_date} to {overlap.cycle_end_date}) "
            "for this credit account"
        )


def _refresh_cycle_status(cycle: CreditStatementCycle) -> None:
    if cycle.statement_amount == 0 and cycle.paid_amount == 0:
        return
    if cycle.paid_amount >= cycle.statement_amount:
        cycle.status = "paid"
    elif cycle.paid_amount > 0:
        cycle.status = "partially_paid"
    else:
        cycle.status = "statement_generated"
