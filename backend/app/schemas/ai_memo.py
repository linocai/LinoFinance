from datetime import date as DateType
from decimal import Decimal
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class AIMemoRead(BaseModel):
    id: str
    period_start: DateType
    period_end: DateType
    summary: str
    stats_json: Dict[str, Any]
    prompt_token: int
    completion_token: int
    generator: str
    status: str
    confidence: Decimal

    model_config = ConfigDict(from_attributes=True)


class AIMemoListResponse(BaseModel):
    items: List[AIMemoRead]


class AIMemoGenerateRequest(BaseModel):
    period_start: DateType
    period_end: DateType
    status: str = Field(default="draft", pattern="^(draft|published|archived)$")


class AIMemoPatch(BaseModel):
    summary: Optional[str] = None
    status: Optional[str] = Field(default=None, pattern="^(draft|published|archived)$")
