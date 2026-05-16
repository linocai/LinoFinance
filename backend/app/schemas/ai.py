from decimal import Decimal
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field, field_serializer

from app.schemas.entry import format_decimal


class AIActionProposal(BaseModel):
    action_type: str = Field(min_length=1, max_length=80)
    payload: Dict[str, Any]
    explanation: Optional[str] = None
    confidence: Optional[Decimal] = Field(default=None, ge=0, le=1)


class AIPlanCreate(BaseModel):
    source_text: str = Field(min_length=1)
    actions: List[AIActionProposal] = Field(default_factory=list)
    explanation: Optional[str] = None
    confidence: Optional[Decimal] = Field(default=None, ge=0, le=1)
    raw_response: Optional[Dict[str, Any]] = None


class AIPlanApprove(BaseModel):
    note: Optional[str] = None


class AIPlanReject(BaseModel):
    note: Optional[str] = None


class AIPlanExecute(BaseModel):
    strong_confirm: Optional[str] = None


class AIActionRead(BaseModel):
    id: str
    plan_id: str
    execution_order: int
    action_type: str
    status: str
    risk_level: str
    requires_confirmation: bool
    payload: Dict[str, Any]
    explanation: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    rollback_payload: Optional[Dict[str, Any]] = None
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    error_message: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class AIActionExecutionRead(BaseModel):
    id: str
    action_id: str
    status: str
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    before_snapshot: Optional[Dict[str, Any]] = None
    after_snapshot: Optional[Dict[str, Any]] = None
    rollback_snapshot: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class AIPlanRead(BaseModel):
    id: str
    source_text: str
    provider: str
    model: Optional[str] = None
    status: str
    risk_level: str
    auto_confirm_eligible: bool
    confidence: Optional[Decimal] = None
    explanation: Optional[str] = None
    raw_response: Optional[Dict[str, Any]] = None
    actions: List[AIActionRead]

    @field_serializer("confidence")
    def serialize_decimal(self, value: Optional[Decimal]) -> Optional[str]:
        return None if value is None else format_decimal(value)


class AIConfigRead(BaseModel):
    provider: str
    model: Optional[str] = None
    base_url_configured: bool
    api_key_configured: bool
    auto_confirm_limit_cny: Decimal

    @field_serializer("auto_confirm_limit_cny")
    def serialize_limit(self, value: Decimal) -> str:
        return format_decimal(value)
