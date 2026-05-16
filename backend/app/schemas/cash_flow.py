from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import EntryCreate, EntryRead, format_decimal


class CashFlowItemCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    direction: str = Field(pattern="^(inflow|outflow|transfer)$")
    cash_flow_type: str = Field(
        pattern="^(salary|rent_income|reimbursement|subscription|credit_repayment|installment|one_time|other)$"
    )
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    expected_date: DateType
    account_id: Optional[str] = None
    category_id: Optional[str] = None
    recurrence_rule: Optional[str] = Field(default=None, max_length=200)
    status: str = Field(default="expected", pattern="^(expected|confirmed)$")
    linked_reimbursement_id: Optional[str] = None
    linked_installment_plan_id: Optional[str] = None
    linked_subscription_rule_id: Optional[str] = None
    linked_statement_cycle_id: Optional[str] = None
    note: Optional[str] = None


class CashFlowSettle(BaseModel):
    entry: EntryCreate


class CashFlowItemRead(BaseModel):
    id: str
    title: str
    direction: str
    cash_flow_type: str
    amount: Decimal
    currency: str
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    expected_date: DateType
    account_id: Optional[str] = None
    category_id: Optional[str] = None
    recurrence_rule: Optional[str] = None
    status: str
    linked_entry_id: Optional[str] = None
    linked_reimbursement_id: Optional[str] = None
    linked_installment_plan_id: Optional[str] = None
    linked_subscription_rule_id: Optional[str] = None
    linked_statement_cycle_id: Optional[str] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("amount", "converted_cny_amount")
    def serialize_decimal(self, value: Optional[Decimal]) -> Optional[str]:
        return None if value is None else format_decimal(value)


class CashFlowSettleRead(BaseModel):
    cash_flow_item: CashFlowItemRead
    entry: EntryRead
