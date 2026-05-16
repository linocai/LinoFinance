from datetime import date as DateType
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class SubscriptionRule(IDTimestampMixin, Base):
    __tablename__ = "subscription_rules"

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    account_id: Mapped[Optional[str]] = mapped_column(ForeignKey("accounts.id"))
    category_id: Mapped[Optional[str]] = mapped_column(ForeignKey("categories.id"))
    billing_interval: Mapped[str] = mapped_column(String(32), nullable=False)
    billing_day: Mapped[Optional[int]] = mapped_column(Integer)
    start_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[DateType]] = mapped_column(Date)
    next_charge_date: Mapped[DateType] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="active", nullable=False)
    note: Mapped[Optional[str]] = mapped_column(Text)

