from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.credit_statement_cycle import CreditStatementCycle
from app.schemas.credit_statement_cycle import CreditStatementCycleCreate, CreditStatementCycleRead
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money


def create_statement_cycle(
    db: Session,
    payload: CreditStatementCycleCreate,
) -> CreditStatementCycleRead:
    account = _get_credit_account(db, payload.credit_account_id)
    data = payload.normalized_dump()
    _validate_cycle_payload(account, data)

    cycle = CreditStatementCycle(**data)
    cycle.statement_amount = quantize_money(cycle.statement_amount)
    cycle.minimum_payment = quantize_money(cycle.minimum_payment)
    cycle.paid_amount = quantize_money(cycle.paid_amount)
    _refresh_cycle_status(cycle)

    db.add(cycle)
    db.commit()
    db.refresh(cycle)
    return CreditStatementCycleRead.from_model(cycle)


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


def _refresh_cycle_status(cycle: CreditStatementCycle) -> None:
    if cycle.statement_amount == 0 and cycle.paid_amount == 0:
        return
    if cycle.paid_amount >= cycle.statement_amount:
        cycle.status = "paid"
    elif cycle.paid_amount > 0:
        cycle.status = "partially_paid"

