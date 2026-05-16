from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class InstallmentPlan(IDTimestampMixin, Base):
    __tablename__ = "installment_plans"

    linked_entry_id: Mapped[str] = mapped_column(ForeignKey("financial_entries.id"), nullable=False)
    credit_account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), nullable=False)
    total_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    number_of_payments: Mapped[int] = mapped_column(Integer, nullable=False)
    payment_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    fee_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    interest_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    start_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    end_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="active", nullable=False)
    note: Mapped[Optional[str]] = mapped_column(Text)

