from functools import lru_cache
from decimal import Decimal
from typing import Optional

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


@lru_cache
def get_settings() -> Settings:
    return Settings()
