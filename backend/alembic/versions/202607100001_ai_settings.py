"""ai_settings

v3.0.0 P3 (D0): runtime AI provider configuration table (single row). Holds the
base_url / api_key / model the user enters in-app so the AI config lives in the
database (DB > env priority) instead of only in server env variables.

Pure table creation, no PostgreSQL-specific logic, so no dialect guard is needed
for the local-SQLite / production-Postgres split.

Idempotency guard: the test suite (and any tool that builds the schema via
``Base.metadata.create_all`` and then runs ``alembic upgrade head`` from an
earlier stamped revision — which every migration-chain test does) will have
already created ``ai_settings`` before this migration runs. Guarding on
``has_table`` keeps the migration a no-op in that path while still creating the
table on a real production DB that only ever runs alembic.

Revision ID: 202607100001
Revises: 202606160003
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "202607100001"
down_revision = "202606160003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if sa.inspect(op.get_bind()).has_table("ai_settings"):
        return
    op.create_table(
        "ai_settings",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("base_url", sa.String(length=500), nullable=True),
        sa.Column("api_key", sa.Text(), nullable=True),
        sa.Column("model", sa.String(length=120), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    if sa.inspect(op.get_bind()).has_table("ai_settings"):
        op.drop_table("ai_settings")
