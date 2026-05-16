from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import format_decimal


class InstallmentPlanCreate(BaseModel):
    linked_entry_id: str
    credit_account_id: str
    total_amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    number_of_payments: int = Field(gt=0)
    payment_amount: Optional[Decimal] = Field(default=None, gt=0)
    fee_amount: Decimal = Field(default=Decimal("0"), ge=0)
    interest_amount: Decimal = Field(default=Decimal("0"), ge=0)
    start_date: DateType
    status: str = Field(default="active", pattern="^(active|paid_off|early_paid_off|cancelled)$")
    note: Optional[str] = None


class InstallmentPlanRead(BaseModel):
    id: str
    linked_entry_id: str
    credit_account_id: str
    total_amount: Decimal
    currency: str
    number_of_payments: int
    payment_amount: Decimal
    fee_amount: Decimal
    interest_amount: Decimal
    start_date: DateType
    end_date: DateType
    status: str
    generated_cash_flow_count: int
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("total_amount", "payment_amount", "fee_amount", "interest_amount")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)

