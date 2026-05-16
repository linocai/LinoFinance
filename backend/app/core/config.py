from decimal import Decimal
from functools import lru_cache
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "LinoFinance API"
    app_version: str = "0.1.0"
    environment: str = "local"
    api_v1_prefix: str = "/api/v1"
    database_url: str = (
        "postgresql+psycopg://linofinance:linofinance@localhost:5432/linofinance"
    )
    api_host: str = "127.0.0.1"
    api_port: int = 8000
    api_auth_token: Optional[str] = None
    api_rate_limit_enabled: bool = False
    api_rate_limit_per_minute: int = Field(default=120, ge=1)
    trusted_proxy_headers: bool = False
    cors_allowed_origins: list[str] = []
    public_docs_enabled: bool = True
    log_level: str = "INFO"
    backup_dir: str = ".backups"
    ai_provider: str = "openai_compatible"
    ai_api_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    ai_request_timeout_seconds: int = 30
    ai_auto_confirm_limit_cny: Decimal = Decimal("1000")

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="LINOFINANCE_",
        extra="ignore",
    )

    @property
    def normalized_environment(self) -> str:
        return self.environment.strip().lower()

    @property
    def is_production(self) -> bool:
        return self.normalized_environment in {"prod", "production"}

    @property
    def auth_required(self) -> bool:
        return bool(self.api_auth_token) or self.is_production

    @property
    def rate_limit_active(self) -> bool:
        return self.api_rate_limit_enabled or self.is_production

    def validate_runtime(self) -> None:
        if self.is_production and not self.api_auth_token:
            raise RuntimeError(
                "LINOFINANCE_API_AUTH_TOKEN is required when LINOFINANCE_ENVIRONMENT "
                "is production."
            )


@lru_cache
def get_settings() -> Settings:
    return Settings()
