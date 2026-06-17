from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.credit_statement_cycle import (
    CreditStatementCycleCreate,
    CreditStatementCycleRead,
    CreditStatementCycleUpdate,
)
from app.services import credit
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[CreditStatementCycleRead])
def list_statement_cycles(
    credit_account_id: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
) -> List[CreditStatementCycleRead]:
    return credit.list_statement_cycles(db, credit_account_id=credit_account_id)


@router.post("", response_model=CreditStatementCycleRead, status_code=status.HTTP_201_CREATED)
def create_statement_cycle(
    payload: CreditStatementCycleCreate,
    db: Session = Depends(get_db),
) -> CreditStatementCycleRead:
    try:
        return credit.create_statement_cycle(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{cycle_id}", response_model=CreditStatementCycleRead)
def get_statement_cycle(cycle_id: str, db: Session = Depends(get_db)) -> CreditStatementCycleRead:
    try:
        return credit.get_statement_cycle(db, cycle_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.patch("/{cycle_id}", response_model=CreditStatementCycleRead)
def update_statement_cycle(
    cycle_id: str,
    payload: CreditStatementCycleUpdate,
    db: Session = Depends(get_db),
) -> CreditStatementCycleRead:
    try:
        return credit.update_statement_cycle(db, cycle_id, payload)
    except LedgerNotFoundError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{cycle_id}/mark-paid", response_model=CreditStatementCycleRead)
def mark_cycle_paid(cycle_id: str, db: Session = Depends(get_db)) -> CreditStatementCycleRead:
    try:
        return credit.mark_cycle_paid(db, cycle_id)
    except LedgerNotFoundError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{cycle_id}/void", response_model=CreditStatementCycleRead)
def void_cycle(cycle_id: str, db: Session = Depends(get_db)) -> CreditStatementCycleRead:
    try:
        return credit.void_cycle(db, cycle_id)
    except LedgerNotFoundError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

