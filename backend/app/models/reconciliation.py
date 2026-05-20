from decimal import Decimal
from typing import Optional

from sqlalchemy import ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class AccountAdjustment(IDTimestampMixin, Base):
    __tablename__ = "account_adjustments"

    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), nullable=False)
    reason: Mapped[str] = mapped_column(String(120), nullable=False)
    delta_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    balance_before: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    balance_after: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    source: Mapped[str] = mapped_column(String(32), default="reconciliation", nullable=False)
    note: Mapped[Optional[str]] = mapped_column(Text)
    created_by: Mapped[str] = mapped_column(String(120), default="system", nullable=False)
