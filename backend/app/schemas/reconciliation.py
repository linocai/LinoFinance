from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ReconciliationAccountRead(BaseModel):
    account_id: str
    account_name: str
    account_type: str
    currency: str
    expected_amount: Decimal
    current_amount: Decimal
    delta_amount: Decimal
    needs_adjustment: bool


class ReconciliationAccountsResponse(BaseModel):
    threshold: Decimal
    items: List[ReconciliationAccountRead]


class AccountAdjustmentCreate(BaseModel):
    account_id: str
    actual_amount: Optional[Decimal] = None
    reason: str = Field(default="reconciliation", max_length=120)
    note: Optional[str] = None
    created_by: str = Field(default="system", max_length=120)


class AccountAdjustmentRead(BaseModel):
    id: str
    account_id: str
    reason: str
    delta_amount: Decimal
    currency: str
    balance_before: Decimal
    balance_after: Decimal
    source: str
    note: Optional[str] = None
    created_by: str

    model_config = ConfigDict(from_attributes=True)
