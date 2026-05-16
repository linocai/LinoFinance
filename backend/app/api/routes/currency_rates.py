from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.currency_rate import CurrencyRate
from app.schemas.currency_rate import CurrencyRateCreate, CurrencyRateRead
from app.services.ledger import LedgerValidationError, normalize_currency

router = APIRouter()


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
    db.commit()
    db.refresh(currency_rate)
    return currency_rate


@router.get("/{currency_rate_id}", response_model=CurrencyRateRead)
def get_currency_rate(currency_rate_id: str, db: Session = Depends(get_db)) -> CurrencyRate:
    currency_rate = db.get(CurrencyRate, currency_rate_id)
    if currency_rate is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Currency rate not found")
    return currency_rate
