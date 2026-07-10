from typing import Optional

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.mixins import IDTimestampMixin


class AISettings(IDTimestampMixin, Base):
    """Runtime AI provider configuration (v3.0.0 P3, D0).

    Single-row table (single user, single ledger): holds the base URL, API key,
    and model the user enters in-app. ``api_key`` is stored in plaintext — the
    same trust level as the existing ``LINOFINANCE_AI_*`` env variables — and is
    NEVER echoed back through the API (``GET /ai/config`` only returns a masked
    hint). Resolution order at request time is DB row (if present) > env.
    """

    __tablename__ = "ai_settings"

    base_url: Mapped[Optional[str]] = mapped_column(String(500))
    api_key: Mapped[Optional[str]] = mapped_column(Text)
    model: Mapped[Optional[str]] = mapped_column(String(120))
