from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.reconciliation import (
    AccountAdjustmentCreate,
    AccountAdjustmentRead,
    CreditRecomputeResponse,
    ReconciliationAccountsResponse,
    ReconciliationCheckResponse,
)
from app.services import reconciliation
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("/accounts", response_model=ReconciliationAccountsResponse)
def list_accounts(db: Session = Depends(get_db)) -> ReconciliationAccountsResponse:
    return reconciliation.list_account_reconciliation(db)


@router.get("/check", response_model=ReconciliationCheckResponse)
def check(db: Session = Depends(get_db)) -> ReconciliationCheckResponse:
    """v2.2.0 P2 — read-only multi-dimension consistency/conflict detector."""
    return reconciliation.run_consistency_check(db)


@router.post(
    "/recompute-credit/{account_id}", response_model=CreditRecomputeResponse
)
def recompute_credit(
    account_id: str,
    db: Session = Depends(get_db),
) -> CreditRecomputeResponse:
    """Re-derive a credit account's liability to ``Σcycle`` (R1 内部纠错)."""
    try:
        return reconciliation.recompute_credit_account(db, account_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


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
