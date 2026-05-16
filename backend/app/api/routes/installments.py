from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.installment import InstallmentPlanCreate, InstallmentPlanRead
from app.services import installment
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[InstallmentPlanRead])
def list_installment_plans(db: Session = Depends(get_db)) -> List[InstallmentPlanRead]:
    return installment.list_installment_plans(db)


@router.post("", response_model=InstallmentPlanRead, status_code=status.HTTP_201_CREATED)
def create_installment_plan(
    payload: InstallmentPlanCreate,
    db: Session = Depends(get_db),
) -> InstallmentPlanRead:
    try:
        return installment.create_installment_plan(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{plan_id}", response_model=InstallmentPlanRead)
def get_installment_plan(plan_id: str, db: Session = Depends(get_db)) -> InstallmentPlanRead:
    try:
        return installment.get_installment_plan(db, plan_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{plan_id}/cancel", response_model=InstallmentPlanRead)
def cancel_installment_plan(plan_id: str, db: Session = Depends(get_db)) -> InstallmentPlanRead:
    return _mutate_plan(db, installment.cancel_installment_plan, plan_id)


@router.post("/{plan_id}/mark-paid-off", response_model=InstallmentPlanRead)
def mark_installment_paid_off(plan_id: str, db: Session = Depends(get_db)) -> InstallmentPlanRead:
    return _mutate_plan(db, installment.mark_installment_plan_paid_off, plan_id)


@router.post("/{plan_id}/mark-early-paid-off", response_model=InstallmentPlanRead)
def mark_installment_early_paid_off(plan_id: str, db: Session = Depends(get_db)) -> InstallmentPlanRead:
    try:
        return installment.mark_installment_plan_paid_off(db, plan_id, early=True)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _mutate_plan(db: Session, operation, plan_id: str) -> InstallmentPlanRead:
    try:
        return operation(db, plan_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

