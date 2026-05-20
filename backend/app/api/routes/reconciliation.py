from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.reconciliation import (
    AccountAdjustmentCreate,
    AccountAdjustmentRead,
    ReconciliationAccountsResponse,
)
from app.services import reconciliation
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("/accounts", response_model=ReconciliationAccountsResponse)
def list_accounts(db: Session = Depends(get_db)) -> ReconciliationAccountsResponse:
    return reconciliation.list_account_reconciliation(db)


@router.post("/adjustments", response_model=AccountAdjustmentRead, status_code=status.HTTP_201_CREATED)
def create_adjustment(
    payload: AccountAdjustmentCreate,
    db: Session = Depends(get_db),
) -> AccountAdjustmentRead:
    try:
        return reconciliation.create_adjustment(db, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
