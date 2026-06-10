from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer


def format_decimal(value: Decimal) -> str:
    text = format(value.normalize(), "f")
    if "." not in text:
        return text
    return text.rstrip("0").rstrip(".")


class CurrencyRateCreate(BaseModel):
    from_currency: str = Field(min_length=3, max_length=3)
    to_currency: str = Field(default="CNY", min_length=3, max_length=3)
    rate: Decimal = Field(gt=0)
    date: DateType
    source: str = Field(default="manual", pattern="^(manual|last_used|api)$")
    note: Optional[str] = None

    def normalized_dump(self) -> dict:
        data = self.model_dump()
        data["from_currency"] = data["from_currency"].upper()
        data["to_currency"] = data["to_currency"].upper()
        return data


class CurrencyRateUpdate(BaseModel):
    """Patch only the ``rate`` of a currency rate (audit 2.5).

    Allowed only when the rate is not yet referenced by any entry line,
    movement, cash flow item, or reimbursement claim (history is never
    rewritten). ``from_currency`` / ``to_currency`` / ``date`` are immutable.
    """

    model_config = ConfigDict(extra="forbid")

    rate: Decimal = Field(gt=0)


class CurrencyRateRead(BaseModel):
    id: str
    from_currency: str
    to_currency: str
    rate: Decimal
    date: DateType
    source: str
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("rate")
    def serialize_rate(self, value: Decimal) -> str:
        return format_decimal(value)
