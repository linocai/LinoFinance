from typing import Any, Dict, Optional

from sqlalchemy import JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class AuditLog(IDTimestampMixin, Base):
    __tablename__ = "audit_logs"

    actor: Mapped[str] = mapped_column(String(32), nullable=False)
    action_type: Mapped[str] = mapped_column(String(120), nullable=False)
    target_type: Mapped[str] = mapped_column(String(120), nullable=False)
    target_id: Mapped[str] = mapped_column(String(36), nullable=False)
    before_snapshot: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    after_snapshot: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    note: Mapped[Optional[str]] = mapped_column(Text)
