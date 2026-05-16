from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class FinancialEntry(IDTimestampMixin, Base):
    __tablename__ = "financial_entries"

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    entry_type: Mapped[str] = mapped_column(String(32), nullable=False)
    date: Mapped[DateType] = mapped_column(Date, nullable=False)
    start_date: Mapped[Optional[DateType]] = mapped_column(Date)
    end_date: Mapped[Optional[DateType]] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(32), default="draft", nullable=False)
    note: Mapped[Optional[str]] = mapped_column(Text)
    created_by: Mapped[str] = mapped_column(String(32), default="user", nullable=False)


class EntryCategoryLine(IDTimestampMixin, Base):
    __tablename__ = "entry_category_lines"

    entry_id: Mapped[str] = mapped_column(ForeignKey("financial_entries.id"), nullable=False)
    category_id: Mapped[str] = mapped_column(ForeignKey("categories.id"), nullable=False)
    direction: Mapped[str] = mapped_column(String(32), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    exchange_rate_id: Mapped[Optional[str]] = mapped_column(ForeignKey("currency_rates.id"))
    converted_cny_amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    reimbursable_flag: Mapped[bool] = mapped_column(default=False, nullable=False)
    note: Mapped[Optional[str]] = mapped_column(Text)


class AccountMovement(IDTimestampMixin, Base):
    __tablename__ = "account_movements"

    entry_id: Mapped[str] = mapped_column(ForeignKey("financial_entries.id"), nullable=False)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), nullable=False)
    statement_cycle_id: Mapped[Optional[str]] = mapped_column(
        ForeignKey("credit_statement_cycles.id"),
    )
    movement_type: Mapped[str] = mapped_column(String(32), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    exchange_rate_id: Mapped[Optional[str]] = mapped_column(ForeignKey("currency_rates.id"))
    converted_cny_amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    note: Mapped[Optional[str]] = mapped_column(Text)
