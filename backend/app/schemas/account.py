from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class AccountCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: str = Field(pattern="^(balance|credit)$")
    currency: str = Field(min_length=3, max_length=3)
    current_balance: Decimal = Decimal("0")
    current_liability: Decimal = Decimal("0")
    include_in_net_worth: bool = True
    status: str = "active"
    display_order: int = 0
    credit_limit: Optional[Decimal] = None
    statement_day: Optional[int] = Field(default=None, ge=1, le=31)
    due_day: Optional[int] = Field(default=None, ge=1, le=31)
    minimum_payment: Optional[Decimal] = None
    notes: Optional[str] = None

    def model_dump(self, *args, **kwargs):
        data = super().model_dump(*args, **kwargs)
        data["currency"] = data["currency"].upper()
        return data


class AccountRead(BaseModel):
    id: str
    name: str
    type: str
    currency: str
    current_balance: Decimal
    current_liability: Decimal
    include_in_net_worth: bool
    status: str
    display_order: int
    credit_limit: Optional[Decimal] = None
    statement_day: Optional[int] = None
    due_day: Optional[int] = None
    minimum_payment: Optional[Decimal] = None
    notes: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

