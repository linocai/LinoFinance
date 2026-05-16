"""Add AI plans, actions, and notification rules.

Revision ID: 202605160005
Revises: 202605160004
Create Date: 2026-05-16 15:30:00.000000
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "202605160005"
down_revision: Union[str, None] = "202605160004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "ai_plans",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("source_text", sa.Text(), nullable=False),
        sa.Column("provider", sa.String(length=64), nullable=False),
        sa.Column("model", sa.String(length=120), nullable=True),
        sa.Column("status", sa.String(length=32), server_default="requires_confirmation", nullable=False),
        sa.Column("risk_level", sa.String(length=32), server_default="medium", nullable=False),
        sa.Column("auto_confirm_eligible", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=True),
        sa.Column("explanation", sa.Text(), nullable=True),
        sa.Column("raw_response", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_plans_status_risk", "ai_plans", ["status", "risk_level"])

    op.create_table(
        "ai_actions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("plan_id", sa.String(length=36), nullable=False),
        sa.Column("execution_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("action_type", sa.String(length=80), nullable=False),
        sa.Column("status", sa.String(length=32), server_default="pending", nullable=False),
        sa.Column("risk_level", sa.String(length=32), server_default="medium", nullable=False),
        sa.Column("requires_confirmation", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("explanation", sa.Text(), nullable=True),
        sa.Column("result", sa.JSON(), nullable=True),
        sa.Column("rollback_payload", sa.JSON(), nullable=True),
        sa.Column("target_type", sa.String(length=120), nullable=True),
        sa.Column("target_id", sa.String(length=36), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["plan_id"], ["ai_plans.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_actions_plan_order", "ai_actions", ["plan_id", "execution_order"])
    op.create_index("ix_ai_actions_status", "ai_actions", ["status"])

    op.create_table(
        "ai_action_executions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("action_id", sa.String(length=36), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("target_type", sa.String(length=120), nullable=True),
        sa.Column("target_id", sa.String(length=36), nullable=True),
        sa.Column("before_snapshot", sa.JSON(), nullable=True),
        sa.Column("after_snapshot", sa.JSON(), nullable=True),
        sa.Column("rollback_snapshot", sa.JSON(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["action_id"], ["ai_actions.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_action_executions_action", "ai_action_executions", ["action_id"])

    op.create_table(
        "notification_rules",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("rule_type", sa.String(length=64), nullable=False),
        sa.Column("channel", sa.String(length=32), server_default="in_app", nullable=False),
        sa.Column("trigger_payload", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(length=32), server_default="active", nullable=False),
        sa.Column("next_trigger_date", sa.Date(), nullable=True),
        sa.Column("last_triggered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_notification_rules_type_status", "notification_rules", ["rule_type", "status"])
    op.create_index("ix_notification_rules_next", "notification_rules", ["next_trigger_date"])


def downgrade() -> None:
    op.drop_index("ix_notification_rules_next", table_name="notification_rules")
    op.drop_index("ix_notification_rules_type_status", table_name="notification_rules")
    op.drop_table("notification_rules")
    op.drop_index("ix_ai_action_executions_action", table_name="ai_action_executions")
    op.drop_table("ai_action_executions")
    op.drop_index("ix_ai_actions_status", table_name="ai_actions")
    op.drop_index("ix_ai_actions_plan_order", table_name="ai_actions")
    op.drop_table("ai_actions")
    op.drop_index("ix_ai_plans_status_risk", table_name="ai_plans")
    op.drop_table("ai_plans")
