from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.reimbursement import (
    ReimbursementClaimCreate,
    ReimbursementClaimRead,
    ReimbursementReceive,
    ReimbursementReceiveRead,
)
from app.services import reimbursement
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[ReimbursementClaimRead])
def list_reimbursement_claims(
    status_filter: Optional[str] = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
) -> List[ReimbursementClaimRead]:
    return reimbursement.list_reimbursement_claims(db, status=status_filter)


@router.post("", response_model=ReimbursementClaimRead, status_code=status.HTTP_201_CREATED)
def create_reimbursement_claim(
    payload: ReimbursementClaimCreate,
    db: Session = Depends(get_db),
) -> ReimbursementClaimRead:
    try:
        return reimbursement.create_reimbursement_claim(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{claim_id}", response_model=ReimbursementClaimRead)
def get_reimbursement_claim(claim_id: str, db: Session = Depends(get_db)) -> ReimbursementClaimRead:
    try:
        return reimbursement.get_reimbursement_claim(db, claim_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{claim_id}/submit", response_model=ReimbursementClaimRead)
def submit_reimbursement_claim(claim_id: str, db: Session = Depends(get_db)) -> ReimbursementClaimRead:
    return _mutate_claim(db, reimbursement.submit_claim, claim_id)


@router.post("/{claim_id}/approve", response_model=ReimbursementClaimRead)
def approve_reimbursement_claim(claim_id: str, db: Session = Depends(get_db)) -> ReimbursementClaimRead:
    return _mutate_claim(db, reimbursement.approve_claim, claim_id)


@router.post("/{claim_id}/reject", response_model=ReimbursementClaimRead)
def reject_reimbursement_claim(claim_id: str, db: Session = Depends(get_db)) -> ReimbursementClaimRead:
    return _mutate_claim(db, reimbursement.reject_claim, claim_id)


@router.post("/{claim_id}/abandon", response_model=ReimbursementClaimRead)
def abandon_reimbursement_claim(claim_id: str, db: Session = Depends(get_db)) -> ReimbursementClaimRead:
    return _mutate_claim(db, reimbursement.abandon_claim, claim_id)


@router.post("/{claim_id}/mark-received", response_model=ReimbursementReceiveRead)
def mark_reimbursement_received(
    claim_id: str,
    payload: ReimbursementReceive,
    db: Session = Depends(get_db),
) -> ReimbursementReceiveRead:
    try:
        return reimbursement.mark_claim_received(db, claim_id, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _mutate_claim(db: Session, operation, claim_id: str) -> ReimbursementClaimRead:
    try:
        return operation(db, claim_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

