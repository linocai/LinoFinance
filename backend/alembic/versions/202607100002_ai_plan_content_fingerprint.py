"""ai_plan content_fingerprint (idempotency key)

v3.1.0 P1 (hands-free bookkeeping safety floor): add
``ai_plans.content_fingerprint`` (sha256 hex, 64 chars, NULLABLE) plus a
NON-unique index. The short-window dedup semantics (same fingerprint within a
~120s window returns the existing plan instead of minting a new one) live in the
query, not a uniqueness constraint — the same content across separate windows is
a legitimately distinct plan, and every historical row is NULL. Root-causes the
v3.0.0 review's 重要-3 (resubmit-then-reject orphan plan double-execute).

Pure add-column + add-index, no PostgreSQL-specific logic, so no dialect guard is
needed for the local-SQLite / production-Postgres split.

Idempotency guard: the migration-chain tests build the schema via
``Base.metadata.create_all`` (which — because the model already declares the
column with ``index=True`` — creates both the column AND
``ix_ai_plans_content_fingerprint``) and then run ``alembic upgrade head`` from an
earlier stamped revision. Guarding on ``get_columns`` / ``get_indexes`` keeps this
migration a no-op in that path while still adding the column + index on a real
production DB that only ever runs alembic.

Revision ID: 202607100002
Revises: 202607100001
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "202607100002"
down_revision = "202607100001"
branch_labels = None
depends_on = None

_INDEX_NAME = "ix_ai_plans_content_fingerprint"


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    columns = {c["name"] for c in inspector.get_columns("ai_plans")}
    if "content_fingerprint" not in columns:
        op.add_column(
            "ai_plans",
            sa.Column("content_fingerprint", sa.String(length=64), nullable=True),
        )
    indexes = {ix["name"] for ix in inspector.get_indexes("ai_plans")}
    if _INDEX_NAME not in indexes:
        op.create_index(_INDEX_NAME, "ai_plans", ["content_fingerprint"])


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    indexes = {ix["name"] for ix in inspector.get_indexes("ai_plans")}
    if _INDEX_NAME in indexes:
        op.drop_index(_INDEX_NAME, table_name="ai_plans")
    columns = {c["name"] for c in inspector.get_columns("ai_plans")}
    if "content_fingerprint" in columns:
        op.drop_column("ai_plans", "content_fingerprint")
