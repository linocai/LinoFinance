from decimal import Decimal

from pydantic import BaseModel, field_serializer

from app.schemas.entry import format_decimal


class DashboardSummary(BaseModel):
    base_currency: str
    balance_total_cny: Decimal
    credit_liability_total_cny: Decimal
    net_worth_cny: Decimal
    draft_entry_count: int
    confirmed_entry_count: int
    voided_entry_count: int

    @field_serializer("balance_total_cny", "credit_liability_total_cny", "net_worth_cny")
    def serialize_decimal(self, value: Decimal) -> str:
        return format_decimal(value)

