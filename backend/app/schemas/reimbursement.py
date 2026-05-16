from datetime import date as DateType
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import EntryCreate, EntryRead, format_decimal


REIMBURSEMENT_STATUS_PATTERN = (
    "^(reimbursable|invoice_pending|submitted|approved|waiting_received|"
    "received|partial_received|rejected|abandoned)$"
)


class ReimbursementClaimCreate(BaseModel):
    linked_entry_id: str
    linked_entry_line_id: Optional[str] = None
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    payer: str = Field(default="company", min_length=1, max_length=120)
    expected_date: DateType
    status: str = Field(default="reimbursable", pattern=REIMBURSEMENT_STATUS_PATTERN)
    invoice_attachment_ids: Optional[List[str]] = None
    note: Optional[str] = None


class ReimbursementReceive(BaseModel):
    actual_received_date: DateType
    received_account_id: str
    entry: EntryCreate


class ReimbursementClaimRead(BaseModel):
    id: str
    linked_entry_id: str
    linked_entry_line_id: Optional[str] = None
    amount: Decimal
    currency: str
    exchange_rate_id: Optional[str] = None
    converted_cny_amount: Optional[Decimal] = None
    payer: str
    expected_date: DateType
    actual_received_date: Optional[DateType] = None
    received_account_id: Optional[str] = None
    received_entry_id: Optional[str] = None
    status: str
    cash_flow_item_id: Optional[str] = None
    invoice_attachment_ids: Optional[List[str]] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_serializer("amount", "converted_cny_amount")
    def serialize_decimal(self, value: Optional[Decimal]) -> Optional[str]:
        return None if value is None else format_decimal(value)


class ReimbursementReceiveRead(BaseModel):
    reimbursement_claim: ReimbursementClaimRead
    entry: EntryRead

