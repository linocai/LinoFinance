from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.ai_memo import AIMemoGenerateRequest, AIMemoListResponse, AIMemoPatch, AIMemoRead
from app.services import ai_memo
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=AIMemoListResponse)
def list_memos(
    period: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
) -> AIMemoListResponse:
    try:
        return AIMemoListResponse(items=ai_memo.list_memos(db, period))
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/generate", response_model=AIMemoRead, status_code=status.HTTP_201_CREATED)
def generate_memo(
    payload: AIMemoGenerateRequest,
    db: Session = Depends(get_db),
) -> AIMemoRead:
    try:
        return ai_memo.generate_memo(db, payload)
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.patch("/{memo_id}", response_model=AIMemoRead)
def patch_memo(
    memo_id: str,
    payload: AIMemoPatch,
    db: Session = Depends(get_db),
) -> AIMemoRead:
    try:
        return ai_memo.patch_memo(db, memo_id, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.delete("/{memo_id}", status_code=status.HTTP_204_NO_CONTENT)
def archive_memo(memo_id: str, db: Session = Depends(get_db)) -> None:
    try:
        ai_memo.archive_memo(db, memo_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
