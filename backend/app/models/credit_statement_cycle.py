from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class CreditStatementCycle(IDTimestampMixin, Base):
    __tablename__ = "credit_statement_cycles"

    credit_account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), nullable=False)
    cycle_start_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    cycle_end_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    statement_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    due_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    statement_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    minimum_payment: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    paid_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="open", nullable=False)
    linked_cash_flow_item_id: Mapped[Optional[str]] = mapped_column(String(36))
    note: Mapped[Optional[str]] = mapped_column(Text)
