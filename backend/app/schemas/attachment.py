from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class AttachmentRead(BaseModel):
    id: str
    owner_type: str
    owner_id: str
    filename: str
    content_type: str
    size_bytes: int
    checksum_sha256: str
    storage_key: str
    uploaded_by: Optional[str] = None
    note: Optional[str] = None
    deleted_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AttachmentCreateMetadata(BaseModel):
    owner_type: str = Field(pattern="^(entry_category_line|reimbursement_claim|ai_action)$")
    owner_id: str = Field(min_length=1, max_length=36)
    uploaded_by: Optional[str] = Field(default=None, max_length=120)
    note: Optional[str] = None
