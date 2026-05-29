from fastapi import APIRouter

from app.core.config import get_settings
from app.schemas.health import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(
        status="ok",
        app=settings.app_name,
        version=settings.app_version,
        environment=settings.environment,
        auth_required=settings.auth_required,
        auth_modes=["admin", "user"],
        rate_limit_enabled=settings.rate_limit_active,
        apns_use_sandbox=settings.apns_use_sandbox,
        apns_dry_run=settings.apns_dry_run,
    )
