from datetime import date as DateType
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer


def format_decimal(value: Decimal) -> str:
    text = format(value.normalize(), "f")
    if "." not in text:
        return text
    return text.rstrip("0").rstrip(".")


class EntryCategoryLineCreate(BaseModel):
    category_id: str
    direction: str = Field(pattern="^(expense|income)$")
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    reimbursable_flag: bool = False
    reimbursement_payer: Optional[str] = Field(default=None, max_length=120)
    reimbursement_expected_date: Optional[DateType] = None
    # v2.1.0 P2: reimbursement collapsed to three states; the only status a
    # reimbursable line may pre-set at creation is "pending" (待回款). Omit to
    # let create_claims_for_entry default the claim to pending.
    reimbursement_status: Optional[str] = Field(
        default=None,
        pattern="^pending$",
    )
    note: Optional[str] = None


class AccountMovementCreate(BaseModel):
    account_id: str
    statement_cycle_id: Optional[str] = None
    movement_type: str = Field(
        pattern="^(balance_in|balance_out|credit_charge|credit_repayment|transfer_in|transfer_out)$"
    )
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    note: Optional[str] = None


class EntryCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    entry_type: str = Field(
        default="single",
        pattern="^(single|daily_summary|multi_day_summary|monthly_adjustment|estimate|transfer)$",
    )
    date: DateType
    start_date: Optional[DateType] = None
    end_date: Optional[DateType] = None
    status: str = Field(default="confirmed", pattern="^confirmed$")
    note: Optional[str] = None
    created_by: str = Field(default="user", pattern="^(user|ai|system)$")
    category_lines: List[EntryCategoryLineCreate] = Field(default_factory=list)
    account_movements: List[AccountMovementCreate] = Field(default_factory=list)


class EntryCategoryLineRead(BaseModel):
    id: str
    entry_id: str
    category_id: str
    direction: str
    amount: Decimal
    currency: str
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    reimbursable_flag: bool
    reimbursement_payer: Optional[str] = None
    reimbursement_expected_date: Optional[DateType] = None
    reimbursement_status: Optional[str] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("amount", "converted_cny_amount")
    def serialize_decimal(self, value: Optional[Decimal]) -> Optional[str]:
        return None if value is None else format_decimal(value)


class AccountMovementRead(BaseModel):
    id: str
    entry_id: str
    account_id: str
    statement_cycle_id: Optional[str] = None
    movement_type: str
    amount: Decimal
    currency: str
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("amount", "converted_cny_amount")
    def serialize_decimal(self, value: Optional[Decimal]) -> Optional[str]:
        return None if value is None else format_decimal(value)


class EntryRead(BaseModel):
    id: str
    title: str
    entry_type: str
    date: DateType
    start_date: Optional[DateType] = None
    end_date: Optional[DateType] = None
    status: str
    note: Optional[str] = None
    created_by: str
    category_lines: List[EntryCategoryLineRead]
    account_movements: List[AccountMovementRead]

    @classmethod
    def from_models(cls, entry, lines, movements):
        return cls(
            id=entry.id,
            title=entry.title,
            entry_type=entry.entry_type,
            date=entry.date,
            start_date=entry.start_date,
            end_date=entry.end_date,
            status=entry.status,
            note=entry.note,
            created_by=entry.created_by,
            category_lines=[EntryCategoryLineRead.model_validate(line) for line in lines],
            account_movements=[AccountMovementRead.model_validate(movement) for movement in movements],
        )
