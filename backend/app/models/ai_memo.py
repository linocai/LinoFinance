from datetime import date as DateType
from decimal import Decimal
from typing import Any, Dict

from sqlalchemy import Date, Integer, JSON, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class AIMemo(IDTimestampMixin, Base):
    __tablename__ = "ai_memos"

    period_start: Mapped[DateType] = mapped_column(Date, nullable=False)
    period_end: Mapped[DateType] = mapped_column(Date, nullable=False)
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    stats_json: Mapped[Dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    prompt_token: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    completion_token: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    generator: Mapped[str] = mapped_column(String(120), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="draft", nullable=False)
    confidence: Mapped[Decimal] = mapped_column(Numeric(5, 4), default=0, nullable=False)
