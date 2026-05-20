from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str
    app: str
    version: str
    environment: str
    auth_required: bool
    rate_limit_enabled: bool
    apns_use_sandbox: bool
    apns_dry_run: bool
