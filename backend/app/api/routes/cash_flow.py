from datetime import date as DateType
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.cash_flow import CashFlowItemCreate, CashFlowItemRead, CashFlowSettle, CashFlowSettleRead
from app.services import cash_flow
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[CashFlowItemRead])
def list_cash_flow_items(
    status: Optional[str] = Query(default=None),
    date_from: Optional[DateType] = Query(default=None),
    date_to: Optional[DateType] = Query(default=None),
    db: Session = Depends(get_db),
) -> List[CashFlowItemRead]:
    return cash_flow.list_cash_flow_items(db, status=status, date_from=date_from, date_to=date_to)


@router.post("", response_model=CashFlowItemRead, status_code=status.HTTP_201_CREATED)
def create_cash_flow_item(
    payload: CashFlowItemCreate,
    db: Session = Depends(get_db),
) -> CashFlowItemRead:
    try:
        return cash_flow.create_cash_flow_item(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{item_id}", response_model=CashFlowItemRead)
def get_cash_flow_item(item_id: str, db: Session = Depends(get_db)) -> CashFlowItemRead:
    try:
        return cash_flow.get_cash_flow_item(db, item_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{item_id}/confirm", response_model=CashFlowItemRead)
def confirm_cash_flow_item(item_id: str, db: Session = Depends(get_db)) -> CashFlowItemRead:
    try:
        return cash_flow.confirm_cash_flow_item(db, item_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{item_id}/cancel", response_model=CashFlowItemRead)
def cancel_cash_flow_item(item_id: str, db: Session = Depends(get_db)) -> CashFlowItemRead:
    try:
        return cash_flow.cancel_cash_flow_item(db, item_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{item_id}/settle", response_model=CashFlowSettleRead)
def settle_cash_flow_item(
    item_id: str,
    payload: CashFlowSettle,
    db: Session = Depends(get_db),
) -> CashFlowSettleRead:
    try:
        return cash_flow.settle_cash_flow_item(db, item_id, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

