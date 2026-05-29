from __future__ import annotations

from typing import TYPE_CHECKING, Optional
from uuid import uuid4

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models.mixins import IDTimestampMixin

if TYPE_CHECKING:
    from app.models.auth_session import AuthSession


class User(IDTimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(40),
        primary_key=True,
        default=lambda: uuid4().hex,
    )
    apple_user_id: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    display_name: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    disabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    auth_sessions: Mapped[list["AuthSession"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
