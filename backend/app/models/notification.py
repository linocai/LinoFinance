from datetime import date as DateType, datetime
from typing import Any, Dict, Optional

from sqlalchemy import JSON, Date, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class NotificationRule(IDTimestampMixin, Base):
    __tablename__ = "notification_rules"

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    rule_type: Mapped[str] = mapped_column(String(64), nullable=False)
    channel: Mapped[str] = mapped_column(String(32), default="in_app", nullable=False)
    trigger_payload: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="active", nullable=False)
    next_trigger_date: Mapped[Optional[DateType]] = mapped_column(Date)
    last_triggered_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    note: Mapped[Optional[str]] = mapped_column(Text)
