from decimal import Decimal
from functools import lru_cache
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "LinoFinance API"
    app_version: str = "2.1.0"
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
    storage_root: str = ".local/storage"
    attachment_file_max_bytes: int = 10 * 1024 * 1024
    attachment_max_bytes: int = 25 * 1024 * 1024
    search_result_limit: int = Field(default=50, ge=1, le=200)
    ai_memo_max_tokens: int = Field(default=2000, ge=256)
    ai_provider: str = "openai_compatible"
    ai_api_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    ai_request_timeout_seconds: int = 30
    ai_auto_confirm_limit_cny: Decimal = Decimal("1000")
    apns_topic: Optional[str] = None
    apns_key_id: Optional[str] = None
    apns_team_id: Optional[str] = None
    apns_key_path: Optional[str] = None
    apns_use_sandbox: bool = True
    apns_dry_run: bool = False
    session_lifetime_days: int = Field(default=365, ge=1)
    apple_signin_audiences: list[str] = [
        "com.lino.linofinance.ios",
        "com.lino.linofinance",
    ]
    apple_dev_shortcut: bool = False
    # Business timezone used to resolve "today" anchors and to bucket UTC-naive
    # `created_at` timestamps to a calendar date (audit §3.4/§3.5, D6). Defaults
    # to Shanghai; override via `LINOFINANCE_APP_TIMEZONE`.
    app_timezone: str = "Asia/Shanghai"
    # Comma-separated Apple `sub` values that may self-activate even when the
    # users table is non-empty (single-user gate escape hatch — e.g. migrating
    # to a new Apple ID). Empty by default.
    apple_sub_allowlist: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="LINOFINANCE_",
        extra="ignore",
    )

    @property
    def normalized_environment(self) -> str:
        return self.environment.strip().lower()

    @property
    def apple_sub_allowlist_set(self) -> set[str]:
        return {s.strip() for s in self.apple_sub_allowlist.split(",") if s.strip()}

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
        if self.is_production and self.apple_dev_shortcut:
            raise RuntimeError(
                "LINOFINANCE_APPLE_DEV_SHORTCUT must not be enabled in production; "
                "it bypasses Apple identity_token verification."
            )


@lru_cache
def get_settings() -> Settings:
    return Settings()
