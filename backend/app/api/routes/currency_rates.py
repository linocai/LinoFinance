from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.cash_flow import CashFlowItem
from app.models.currency_rate import CurrencyRate
from app.models.entry import AccountMovement, EntryCategoryLine
from app.models.reimbursement import ReimbursementClaim
from app.schemas.currency_rate import (
    CurrencyRateCreate,
    CurrencyRateRead,
    CurrencyRateUpdate,
)
from app.services.ledger import LedgerValidationError, normalize_currency

router = APIRouter()


def _is_rate_referenced(db: Session, currency_rate_id: str) -> bool:
    """True if any ledger record pins this rate (history must not be rewritten).

    Covers all four FK references to ``currency_rates.id``: entry category
    lines, account movements, cash flow items, and reimbursement claims.
    """
    for model in (
        EntryCategoryLine,
        AccountMovement,
        CashFlowItem,
        ReimbursementClaim,
    ):
        exists = db.execute(
            select(func.count())
            .select_from(model)
            .where(model.exchange_rate_id == currency_rate_id)
        ).scalar_one()
        if exists:
            return True
    return False


@router.get("", response_model=List[CurrencyRateRead])
def list_currency_rates(db: Session = Depends(get_db)) -> List[CurrencyRate]:
    result = db.execute(
        select(CurrencyRate).order_by(
            CurrencyRate.date.desc(),
            CurrencyRate.from_currency,
            CurrencyRate.to_currency,
        )
    )
    return list(result.scalars().all())


@router.post("", response_model=CurrencyRateRead, status_code=status.HTTP_201_CREATED)
def create_currency_rate(
    payload: CurrencyRateCreate,
    db: Session = Depends(get_db),
) -> CurrencyRate:
    data = payload.normalized_dump()
    try:
        from_currency = normalize_currency(data["from_currency"])
        to_currency = normalize_currency(data["to_currency"])
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    if to_currency != "CNY" or from_currency == to_currency:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="V1 currency rates must convert a non-CNY currency to CNY",
        )
    data["from_currency"] = from_currency
    data["to_currency"] = to_currency
    currency_rate = CurrencyRate(**data)
    db.add(currency_rate)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "A currency rate for this from/to/date already exists; "
                "edit it or pick a different date."
            ),
        ) from exc
    db.refresh(currency_rate)
    return currency_rate


@router.get("/{currency_rate_id}", response_model=CurrencyRateRead)
def get_currency_rate(currency_rate_id: str, db: Session = Depends(get_db)) -> CurrencyRate:
    currency_rate = db.get(CurrencyRate, currency_rate_id)
    if currency_rate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Currency rate not found")
    return currency_rate


@router.patch("/{currency_rate_id}", response_model=CurrencyRateRead)
def update_currency_rate(
    currency_rate_id: str,
    payload: CurrencyRateUpdate,
    db: Session = Depends(get_db),
) -> CurrencyRate:
    currency_rate = db.get(CurrencyRate, currency_rate_id)
    if currency_rate is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Currency rate not found"
        )
    # Only an unreferenced rate may be corrected; once any ledger record pins
    # it the historical conversion is frozen (V1 "history is never rewritten").
    if _is_rate_referenced(db, currency_rate_id):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Currency rate is referenced by existing ledger records and "
                "cannot be edited; create a new rate instead."
            ),
        )
    currency_rate.rate = payload.rate
    db.commit()
    db.refresh(currency_rate)
    return currency_rate
