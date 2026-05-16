"""Add cash flow items.

Revision ID: 202605160002
Revises: 202605160001
Create Date: 2026-05-16
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "202605160002"
down_revision: Union[str, None] = "202605160001"
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
        "cash_flow_items",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("direction", sa.String(length=32), nullable=False),
        sa.Column("cash_flow_type", sa.String(length=32), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("exchange_rate_id", sa.String(length=36), nullable=True),
        sa.Column("converted_cny_amount", sa.Numeric(18, 2), nullable=True),
        sa.Column("expected_date", sa.Date(), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=True),
        sa.Column("category_id", sa.String(length=36), nullable=True),
        sa.Column("recurrence_rule", sa.String(length=200), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="expected"),
        sa.Column("linked_entry_id", sa.String(length=36), nullable=True),
        sa.Column("linked_reimbursement_id", sa.String(length=36), nullable=True),
        sa.Column("linked_installment_plan_id", sa.String(length=36), nullable=True),
        sa.Column("linked_statement_cycle_id", sa.String(length=36), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"]),
        sa.ForeignKeyConstraint(["category_id"], ["categories.id"]),
        sa.ForeignKeyConstraint(["exchange_rate_id"], ["currency_rates.id"]),
        sa.ForeignKeyConstraint(["linked_entry_id"], ["financial_entries.id"]),
        sa.ForeignKeyConstraint(["linked_statement_cycle_id"], ["credit_statement_cycles.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_cash_flow_items_expected_date_status", "cash_flow_items", ["expected_date", "status"])
    op.create_index("ix_cash_flow_items_type_status", "cash_flow_items", ["cash_flow_type", "status"])
    op.create_index("ix_cash_flow_items_account", "cash_flow_items", ["account_id"])


def downgrade() -> None:
    op.drop_index("ix_cash_flow_items_account", table_name="cash_flow_items")
    op.drop_index("ix_cash_flow_items_type_status", table_name="cash_flow_items")
    op.drop_index("ix_cash_flow_items_expected_date_status", table_name="cash_flow_items")
    op.drop_table("cash_flow_items")

