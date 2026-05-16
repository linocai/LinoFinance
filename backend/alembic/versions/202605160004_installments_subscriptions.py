"""Add installments and subscriptions.

Revision ID: 202605160004
Revises: 202605160003
Create Date: 2026-05-16
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "202605160004"
down_revision: Union[str, None] = "202605160003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def timestamp_columns() -> list:
    return [
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
    ]


def upgrade() -> None:
    op.create_table(
        "installment_plans",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("linked_entry_id", sa.String(length=36), nullable=False),
        sa.Column("credit_account_id", sa.String(length=36), nullable=False),
        sa.Column("total_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("number_of_payments", sa.Integer(), nullable=False),
        sa.Column("payment_amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("fee_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("interest_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["credit_account_id"], ["accounts.id"]),
        sa.ForeignKeyConstraint(["linked_entry_id"], ["financial_entries.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_installment_plans_status", "installment_plans", ["status"])
    op.create_index("ix_installment_plans_credit_account", "installment_plans", ["credit_account_id"])

    op.create_table(
        "subscription_rules",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=True),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("billing_interval", sa.String(length=32), nullable=False),
        sa.Column("billing_day", sa.Integer(), nullable=True),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("next_charge_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"]),
        sa.ForeignKeyConstraint(["category_id"], ["categories.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_subscription_rules_status_next", "subscription_rules", ["status", "next_charge_date"])

    op.add_column("cash_flow_items", sa.Column("linked_subscription_rule_id", sa.String(length=36), nullable=True))
    op.create_foreign_key(
        "fk_cash_flow_items_subscription_rule",
        "cash_flow_items",
        "subscription_rules",
        ["linked_subscription_rule_id"],
        ["id"],
    )
    op.create_index(
        "ix_cash_flow_items_subscription_rule",
        "cash_flow_items",
        ["linked_subscription_rule_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_cash_flow_items_subscription_rule", table_name="cash_flow_items")
    op.drop_constraint("fk_cash_flow_items_subscription_rule", "cash_flow_items", type_="foreignkey")
    op.drop_column("cash_flow_items", "linked_subscription_rule_id")
    op.drop_index("ix_subscription_rules_status_next", table_name="subscription_rules")
    op.drop_table("subscription_rules")
    op.drop_index("ix_installment_plans_credit_account", table_name="installment_plans")
    op.drop_index("ix_installment_plans_status", table_name="installment_plans")
    op.drop_table("installment_plans")

