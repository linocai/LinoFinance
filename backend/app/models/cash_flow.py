from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class CashFlowItem(IDTimestampMixin, Base):
    __tablename__ = "cash_flow_items"

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    direction: Mapped[str] = mapped_column(String(32), nullable=False)
    cash_flow_type: Mapped[str] = mapped_column(String(32), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    exchange_rate_id: Mapped[Optional[str]] = mapped_column(ForeignKey("currency_rates.id"))
    converted_cny_amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    expected_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    account_id: Mapped[Optional[str]] = mapped_column(ForeignKey("accounts.id"))
    category_id: Mapped[Optional[str]] = mapped_column(ForeignKey("categories.id"))
    recurrence_rule: Mapped[Optional[str]] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(String(32), default="expected", nullable=False)
    linked_entry_id: Mapped[Optional[str]] = mapped_column(ForeignKey("financial_entries.id"))
    linked_reimbursement_id: Mapped[Optional[str]] = mapped_column(String(36))
    linked_installment_plan_id: Mapped[Optional[str]] = mapped_column(String(36))
    linked_subscription_rule_id: Mapped[Optional[str]] = mapped_column(ForeignKey("subscription_rules.id"))
    linked_statement_cycle_id: Mapped[Optional[str]] = mapped_column(
        ForeignKey("credit_statement_cycles.id"),
    )
    note: Mapped[Optional[str]] = mapped_column(Text)
