from decimal import Decimal
from typing import Any, Dict, Optional

from sqlalchemy import JSON, Boolean, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class AIPlan(IDTimestampMixin, Base):
    __tablename__ = "ai_plans"

    source_text: Mapped[str] = mapped_column(Text, nullable=False)
    provider: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[Optional[str]] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(32), default="requires_confirmation", nullable=False)
    risk_level: Mapped[str] = mapped_column(String(32), default="medium", nullable=False)
    auto_confirm_eligible: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    confidence: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 4))
    explanation: Mapped[Optional[str]] = mapped_column(Text)
    raw_response: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)


class AIAction(IDTimestampMixin, Base):
    __tablename__ = "ai_actions"

    plan_id: Mapped[str] = mapped_column(ForeignKey("ai_plans.id"), nullable=False)
    execution_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    action_type: Mapped[str] = mapped_column(String(80), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="pending", nullable=False)
    risk_level: Mapped[str] = mapped_column(String(32), default="medium", nullable=False)
    requires_confirmation: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    payload: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False)
    explanation: Mapped[Optional[str]] = mapped_column(Text)
    result: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    rollback_payload: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    target_type: Mapped[Optional[str]] = mapped_column(String(120))
    target_id: Mapped[Optional[str]] = mapped_column(String(36))
    error_message: Mapped[Optional[str]] = mapped_column(Text)


class AIActionExecution(IDTimestampMixin, Base):
    __tablename__ = "ai_action_executions"

    action_id: Mapped[str] = mapped_column(ForeignKey("ai_actions.id"), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    target_type: Mapped[Optional[str]] = mapped_column(String(120))
    target_id: Mapped[Optional[str]] = mapped_column(String(36))
    before_snapshot: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    after_snapshot: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    rollback_snapshot: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON)
    error_message: Mapped[Optional[str]] = mapped_column(Text)
