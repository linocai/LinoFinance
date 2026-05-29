"""auth_users_sessions

Revision ID: 202605270001
Revises: 202605200001
Create Date: 2026-05-27
"""
from alembic import op
import sqlalchemy as sa

revision = "202605270001"
down_revision = "202605200001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=40), primary_key=True),
        sa.Column("apple_user_id", sa.String(length=255), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=True),
        sa.Column("email_verified", sa.Boolean(), nullable=False,
                  server_default=sa.text("false")),
        sa.Column("display_name", sa.String(length=120), nullable=True),
        sa.Column("is_admin", sa.Boolean(), nullable=False,
                  server_default=sa.text("false")),
        sa.Column("disabled", sa.Boolean(), nullable=False,
                  server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("apple_user_id", name="users_apple_user_id_uq"),
    )

    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.String(length=40), primary_key=True),
        sa.Column("user_id", sa.String(length=40), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("device_label", sa.String(length=120), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("issued_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"],
            ondelete="CASCADE", name="auth_sessions_user_id_fk",
        ),
        sa.UniqueConstraint("token_hash", name="auth_sessions_token_hash_uq"),
    )
    op.create_index(
        "auth_sessions_user_id_idx", "auth_sessions", ["user_id"],
    )
    # Partial indexes are PostgreSQL-only; SQLite (local dev / tests) skips it.
    if op.get_bind().dialect.name == "postgresql":
        op.create_index(
            "auth_sessions_active_idx", "auth_sessions", ["user_id"],
            postgresql_where=sa.text("revoked_at IS NULL"),
        )


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.drop_index("auth_sessions_active_idx", table_name="auth_sessions")
    op.drop_index("auth_sessions_user_id_idx", table_name="auth_sessions")
    op.drop_table("auth_sessions")
    op.drop_table("users")
