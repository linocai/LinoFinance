from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import format_decimal


class SubscriptionRuleCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    account_id: Optional[str] = None
    category_id: Optional[str] = None
    billing_interval: str = Field(pattern="^(weekly|monthly|yearly)$")
    billing_day: Optional[int] = Field(default=None, ge=1, le=31)
    start_date: DateType
    end_date: Optional[DateType] = None
    next_charge_date: Optional[DateType] = None
    status: str = Field(default="active", pattern="^(active|paused|cancelled)$")
    note: Optional[str] = None


class SubscriptionRuleRead(BaseModel):
    id: str
    title: str
    amount: Decimal
    currency: str
    account_id: Optional[str] = None
    category_id: Optional[str] = None
    billing_interval: str
    billing_day: Optional[int] = None
    start_date: DateType
    end_date: Optional[DateType] = None
    next_charge_date: DateType
    status: str
    generated_cash_flow_count: int
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("amount")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)

