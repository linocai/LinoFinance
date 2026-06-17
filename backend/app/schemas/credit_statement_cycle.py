from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import format_decimal


class CreditStatementCycleCreate(BaseModel):
    credit_account_id: str
    cycle_start_date: DateType
    cycle_end_date: DateType
    statement_date: DateType
    due_date: DateType
    currency: str = Field(min_length=3, max_length=3)
    statement_amount: Decimal = Field(default=Decimal("0"), ge=0)
    minimum_payment: Decimal = Field(default=Decimal("0"), ge=0)
    paid_amount: Decimal = Field(default=Decimal("0"), ge=0)
    status: str = Field(
        default="open",
        pattern="^(open|statement_generated|partially_paid|paid|overdue|closed)$",
    )
    linked_cash_flow_item_id: Optional[str] = None
    note: Optional[str] = None

    def normalized_dump(self) -> dict:
        data = self.model_dump()
        data["currency"] = data["currency"].upper()
        return data


class CreditStatementCycleUpdate(BaseModel):
    """Partial update for a credit statement cycle (v2.3.0 P1).

    All fields are optional; ``model_fields_set`` is the sentinel that
    distinguishes "field absent" (leave unchanged) from a supplied value.
    ``currency``/``credit_account_id`` are intentionally absent — currency
    is pinned to the account and the cycle cannot be reassigned. ``note`` is
    the only optional column that may be explicitly cleared via ``null``.
    """

    cycle_start_date: Optional[DateType] = None
    cycle_end_date: Optional[DateType] = None
    statement_date: Optional[DateType] = None
    due_date: Optional[DateType] = None
    statement_amount: Optional[Decimal] = Field(default=None, ge=0)
    minimum_payment: Optional[Decimal] = Field(default=None, ge=0)
    paid_amount: Optional[Decimal] = Field(default=None, ge=0)
    note: Optional[str] = None


class CreditStatementCycleRead(BaseModel):
    id: str
    credit_account_id: str
    cycle_start_date: DateType
    cycle_end_date: DateType
    statement_date: DateType
    due_date: DateType
    currency: str
    statement_amount: Decimal
    minimum_payment: Decimal
    paid_amount: Decimal
    remaining_amount: Decimal
    status: str
    linked_cash_flow_item_id: Optional[str] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @classmethod
    def from_model(cls, cycle):
        return cls(
            id=cycle.id,
            credit_account_id=cycle.credit_account_id,
            cycle_start_date=cycle.cycle_start_date,
            cycle_end_date=cycle.cycle_end_date,
            statement_date=cycle.statement_date,
            due_date=cycle.due_date,
            currency=cycle.currency,
            statement_amount=cycle.statement_amount,
            minimum_payment=cycle.minimum_payment,
            paid_amount=cycle.paid_amount,
            remaining_amount=cycle.statement_amount - cycle.paid_amount,
            status=cycle.status,
            linked_cash_flow_item_id=cycle.linked_cash_flow_item_id,
            note=cycle.note,
        )

    @field_serializer("statement_amount", "minimum_payment", "paid_amount", "remaining_amount")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)

