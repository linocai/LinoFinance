from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class AppleSignInRequest(BaseModel):
    identity_token: str = Field(min_length=1)
    authorization_code: Optional[str] = Field(default=None)
    device_label: str = Field(min_length=1, max_length=120)
    platform: str = Field(min_length=1, max_length=16)
    app_version: Optional[str] = Field(default=None, max_length=32)
    first_name: Optional[str] = Field(default=None, max_length=120)
    last_name: Optional[str] = Field(default=None, max_length=120)


class AuthUser(BaseModel):
    id: str
    apple_user_id: str
    email: Optional[str] = None
    email_verified: bool
    display_name: Optional[str] = None
    is_admin: bool

    model_config = ConfigDict(from_attributes=True)


class AuthSessionRead(BaseModel):
    id: str
    device_label: str
    platform: str
    app_version: Optional[str] = None
    issued_at: datetime
    last_seen_at: datetime
    expires_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AuthSessionListItem(AuthSessionRead):
    is_current: bool


class AppleSignInResponse(BaseModel):
    session_token: str
    expires_at: datetime
    user: AuthUser


class AuthMeResponse(BaseModel):
    user: Optional[AuthUser] = None
    session: Optional[AuthSessionRead] = None
    admin: Optional[bool] = None


class AuthSessionListResponse(BaseModel):
    items: list[AuthSessionListItem]
