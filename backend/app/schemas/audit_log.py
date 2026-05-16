from typing import Any, Dict, Optional

from pydantic import BaseModel, ConfigDict


class AuditLogRead(BaseModel):
    id: str
    actor: str
    action_type: str
    target_type: str
    target_id: str
    before_snapshot: Optional[Dict[str, Any]] = None
    after_snapshot: Optional[Dict[str, Any]] = None
    note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
