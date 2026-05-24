from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, field_serializer

from app.schemas.entry import format_decimal


class DailyPnLCreate(BaseModel):
    new_balance: Decimal
    as_of_date: Optional[DateType] = None
    note: Optional[str] = None


class DailyPnLRead(BaseModel):
    adjustment_id: str
    account_id: str
    currency: str
    balance_before: Decimal
    balance_after: Decimal
    delta_amount: Decimal
    as_of_date: DateType
    source: str

    @field_serializer("balance_before", "balance_after", "delta_amount")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)
