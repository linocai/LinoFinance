from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, JSON, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class ReimbursementClaim(IDTimestampMixin, Base):
    __tablename__ = "reimbursement_claims"

    linked_entry_id: Mapped[str] = mapped_column(ForeignKey("financial_entries.id"), nullable=False)
    linked_entry_line_id: Mapped[Optional[str]] = mapped_column(ForeignKey("entry_category_lines.id"))
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    exchange_rate_id: Mapped[Optional[str]] = mapped_column(ForeignKey("currency_rates.id"))
    converted_cny_amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    payer: Mapped[str] = mapped_column(String(120), nullable=False)
    expected_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    actual_received_date: Mapped[Optional[DateType]] = mapped_column(Date)
    received_account_id: Mapped[Optional[str]] = mapped_column(ForeignKey("accounts.id"))
    received_entry_id: Mapped[Optional[str]] = mapped_column(ForeignKey("financial_entries.id"))
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="reimbursable")
    cash_flow_item_id: Mapped[Optional[str]] = mapped_column(ForeignKey("cash_flow_items.id"))
    invoice_attachment_ids: Mapped[Optional[list]] = mapped_column(JSON)
    note: Mapped[Optional[str]] = mapped_column(Text)

