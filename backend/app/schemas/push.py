from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class PushDeviceCreate(BaseModel):
    device_id: str = Field(min_length=1, max_length=120)
    platform: str = Field(pattern="^(ios|macos)$")
    apns_token: str = Field(min_length=1, max_length=512)
    app_version: Optional[str] = Field(default=None, max_length=64)


class PushDeviceRead(BaseModel):
    id: str
    device_id: str
    platform: str
    apns_token: str
    app_version: Optional[str] = None
    installed_at: datetime
    last_seen_at: datetime
    enabled: bool

    model_config = ConfigDict(from_attributes=True)
