from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.entry import EntryCreate, EntryRead
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[EntryRead])
def list_entries(
    account_id: Optional[str] = Query(default=None),
    limit: Optional[int] = Query(default=None, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
) -> List[EntryRead]:
    # v2.4.0 #3: optional account_id EXISTS filter + offset/limit paging. No
    # params = true full scan, byte-for-byte equal to the pre-v2.4.0 behaviour.
    return ledger.list_entries(db, account_id=account_id, limit=limit, offset=offset)


@router.post("", response_model=EntryRead, status_code=status.HTTP_201_CREATED)
def create_entry(payload: EntryCreate, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return ledger.create_entry(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{entry_id}", response_model=EntryRead)
def get_entry(entry_id: str, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return ledger.get_entry(db, entry_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{entry_id}/void", response_model=EntryRead)
def void_entry(entry_id: str, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return ledger.void_entry(db, entry_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

