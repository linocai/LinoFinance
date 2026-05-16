from decimal import Decimal
from typing import Optional

from sqlalchemy import Boolean, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class Account(IDTimestampMixin, Base):
    __tablename__ = "accounts"

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    type: Mapped[str] = mapped_column(String(32), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    current_balance: Mapped[Decimal] = mapped_column(Numeric(18, 2), default=0, nullable=False)
    current_liability: Mapped[Decimal] = mapped_column(
        Numeric(18, 2),
        default=0,
        nullable=False,
    )
    include_in_net_worth: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="active", nullable=False)
    display_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    credit_limit: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    statement_day: Mapped[Optional[int]] = mapped_column(Integer)
    due_day: Mapped[Optional[int]] = mapped_column(Integer)
    minimum_payment: Mapped[Optional[Decimal]] = mapped_column(Numeric(18, 2))
    notes: Mapped[Optional[str]] = mapped_column(Text)
