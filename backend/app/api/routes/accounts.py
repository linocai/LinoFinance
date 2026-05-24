from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.account import Account
from app.schemas.account import AccountCreate, AccountRead
from app.schemas.investment import DailyPnLCreate, DailyPnLRead
from app.services.investment import record_daily_pnl
from app.services.ledger import (
    LedgerNotFoundError,
    LedgerValidationError,
    normalize_currency,
)

router = APIRouter()


@router.get("", response_model=List[AccountRead])
def list_accounts(db: Session = Depends(get_db)) -> List[Account]:
    result = db.execute(select(Account).order_by(Account.display_order, Account.name))
    return list(result.scalars().all())


@router.post("", response_model=AccountRead, status_code=status.HTTP_201_CREATED)
def create_account(payload: AccountCreate, db: Session = Depends(get_db)) -> Account:
    try:
        data = payload.model_dump()
        data["currency"] = normalize_currency(data["currency"])
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    account = Account(**data)
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


@router.get("/{account_id}", response_model=AccountRead)
def get_account(account_id: str, db: Session = Depends(get_db)) -> Account:
    account = db.get(Account, account_id)
    if account is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
    return account


@router.post(
    "/{account_id}/daily-pnl",
    response_model=DailyPnLRead,
    status_code=status.HTTP_201_CREATED,
)
def post_daily_pnl(
    account_id: str,
    payload: DailyPnLCreate,
    db: Session = Depends(get_db),
) -> DailyPnLRead:
    try:
        return record_daily_pnl(db, account_id, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except LedgerValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc
