"""Add attachments, reconciliation adjustments, AI memos, and push devices.

Revision ID: 202605200001
Revises: 202605160005
Create Date: 2026-05-20 10:00:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "202605200001"
down_revision: Union[str, None] = "202605160005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "attachments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("owner_type", sa.String(length=64), nullable=False),
        sa.Column("owner_id", sa.String(length=36), nullable=False),
        sa.Column("filename", sa.String(length=255), nullable=False),
        sa.Column("content_type", sa.String(length=120), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("storage_key", sa.String(length=512), nullable=False),
        sa.Column("checksum_sha256", sa.String(length=64), nullable=False),
        sa.Column("uploaded_by", sa.String(length=120), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("storage_key"),
    )
    op.create_index("ix_attachments_owner", "attachments", ["owner_type", "owner_id"])
    op.create_index("ix_attachments_checksum", "attachments", ["checksum_sha256"])

    op.create_table(
        "account_adjustments",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("reason", sa.String(length=120), nullable=False),
        sa.Column("delta_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("balance_before", sa.Numeric(18, 2), nullable=False),
        sa.Column("balance_after", sa.Numeric(18, 2), nullable=False),
        sa.Column("source", sa.String(length=32), server_default="reconciliation", nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_by", sa.String(length=120), server_default="system", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_account_adjustments_account", "account_adjustments", ["account_id"])
    op.create_index("ix_account_adjustments_source", "account_adjustments", ["source"])

    op.create_table(
        "ai_memos",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("stats_json", sa.JSON(), nullable=False),
        sa.Column("prompt_token", sa.Integer(), server_default="0", nullable=False),
        sa.Column("completion_token", sa.Integer(), server_default="0", nullable=False),
        sa.Column("generator", sa.String(length=120), nullable=False),
        sa.Column("status", sa.String(length=32), server_default="draft", nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_memos_period", "ai_memos", ["period_start", "period_end"])
    op.create_index("ix_ai_memos_status", "ai_memos", ["status"])

    op.create_table(
        "push_devices",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("device_id", sa.String(length=120), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("apns_token", sa.String(length=512), nullable=False),
        sa.Column("app_version", sa.String(length=64), nullable=True),
        sa.Column("installed_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("platform", "apns_token", name="uq_push_devices_platform_token"),
    )
    op.create_index("ix_push_devices_device", "push_devices", ["device_id"])
    op.create_index("ix_push_devices_enabled", "push_devices", ["enabled"])

    if op.get_context().dialect.name == "postgresql":
        op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
        op.create_index(
            "ix_accounts_name_trgm",
            "accounts",
            ["name"],
            postgresql_using="gin",
            postgresql_ops={"name": "gin_trgm_ops"},
        )
        op.create_index(
            "ix_financial_entries_title_trgm",
            "financial_entries",
            ["title"],
            postgresql_using="gin",
            postgresql_ops={"title": "gin_trgm_ops"},
        )


def downgrade() -> None:
    if op.get_context().dialect.name == "postgresql":
        op.drop_index("ix_financial_entries_title_trgm", table_name="financial_entries")
        op.drop_index("ix_accounts_name_trgm", table_name="accounts")

    op.drop_index("ix_push_devices_enabled", table_name="push_devices")
    op.drop_index("ix_push_devices_device", table_name="push_devices")
    op.drop_table("push_devices")
    op.drop_index("ix_ai_memos_status", table_name="ai_memos")
    op.drop_index("ix_ai_memos_period", table_name="ai_memos")
    op.drop_table("ai_memos")
    op.drop_index("ix_account_adjustments_source", table_name="account_adjustments")
    op.drop_index("ix_account_adjustments_account", table_name="account_adjustments")
    op.drop_table("account_adjustments")
    op.drop_index("ix_attachments_checksum", table_name="attachments")
    op.drop_index("ix_attachments_owner", table_name="attachments")
    op.drop_table("attachments")
