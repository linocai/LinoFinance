from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.entry import EntryCreate, EntryRead
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[EntryRead])
def list_entries(db: Session = Depends(get_db)) -> List[EntryRead]:
    return ledger.list_entries(db)


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


@router.post("/{entry_id}/confirm", response_model=EntryRead)
def confirm_entry(entry_id: str, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return ledger.confirm_entry(db, entry_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/{entry_id}/void", response_model=EntryRead)
def void_entry(entry_id: str, db: Session = Depends(get_db)) -> EntryRead:
    try:
        return ledger.void_entry(db, entry_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

