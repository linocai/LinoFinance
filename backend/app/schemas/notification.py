from datetime import date as DateType, datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, ConfigDict, Field


class NotificationRuleCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    rule_type: str = Field(
        pattern="^(credit_repayment|cash_flow|reimbursement|subscription|anomaly)$"
    )
    channel: str = Field(default="in_app", pattern="^(in_app|system|email)$")
    trigger_payload: Dict[str, Any] = Field(default_factory=dict)
    status: str = Field(default="active", pattern="^(active|paused|cancelled)$")
    next_trigger_date: Optional[DateType] = None
    note: Optional[str] = None


class NotificationRuleRead(BaseModel):
    id: str
    title: str
    rule_type: str
    channel: str
    trigger_payload: Dict[str, Any]
    status: str
    next_trigger_date: Optional[DateType] = None
    last_triggered_at: Optional[datetime] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
