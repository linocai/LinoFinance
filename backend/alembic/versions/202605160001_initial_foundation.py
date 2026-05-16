"""Initial foundation tables.

Revision ID: 202605160001
Revises:
Create Date: 2026-05-16
"""
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "202605160001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def timestamp_columns() -> list:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        "currency_rates",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("from_currency", sa.String(length=3), nullable=False),
        sa.Column("to_currency", sa.String(length=3), nullable=False),
        sa.Column("rate", sa.Numeric(18, 8), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_currency_rates_pair_date",
        "currency_rates",
        ["from_currency", "to_currency", "date"],
    )

    op.create_table(
        "accounts",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("current_balance", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("current_liability", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("include_in_net_worth", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="active"),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("credit_limit", sa.Numeric(18, 2), nullable=True),
        sa.Column("statement_day", sa.Integer(), nullable=True),
        sa.Column("due_day", sa.Integer(), nullable=True),
        sa.Column("minimum_payment", sa.Numeric(18, 2), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_accounts_type_status", "accounts", ["type", "status"])

    op.create_table(
        "categories",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("parent_id", sa.String(length=36), nullable=True),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("display_order", sa.Integer(), nullable=False, server_default="0"),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["parent_id"], ["categories.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_categories_type_active", "categories", ["type", "is_active"])

    op.create_table(
        "financial_entries",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("entry_type", sa.String(length=32), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=True),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("created_by", sa.String(length=32), nullable=False, server_default="user"),
        *timestamp_columns(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_financial_entries_date_status", "financial_entries", ["date", "status"])

    op.create_table(
        "credit_statement_cycles",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("credit_account_id", sa.String(length=36), nullable=False),
        sa.Column("cycle_start_date", sa.Date(), nullable=False),
        sa.Column("cycle_end_date", sa.Date(), nullable=False),
        sa.Column("statement_date", sa.Date(), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("statement_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("minimum_payment", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("paid_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="open"),
        sa.Column("linked_cash_flow_item_id", sa.String(length=36), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["credit_account_id"], ["accounts.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_credit_statement_cycles_account_dates",
        "credit_statement_cycles",
        ["credit_account_id", "cycle_start_date", "cycle_end_date"],
    )

    op.create_table(
        "entry_category_lines",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("entry_id", sa.String(length=36), nullable=False),
        sa.Column("category_id", sa.String(length=36), nullable=False),
        sa.Column("direction", sa.String(length=32), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("exchange_rate_id", sa.String(length=36), nullable=True),
        sa.Column("converted_cny_amount", sa.Numeric(18, 2), nullable=True),
        sa.Column("reimbursable_flag", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["category_id"], ["categories.id"]),
        sa.ForeignKeyConstraint(["entry_id"], ["financial_entries.id"]),
        sa.ForeignKeyConstraint(["exchange_rate_id"], ["currency_rates.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_entry_category_lines_entry", "entry_category_lines", ["entry_id"])

    op.create_table(
        "account_movements",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("entry_id", sa.String(length=36), nullable=False),
        sa.Column("account_id", sa.String(length=36), nullable=False),
        sa.Column("statement_cycle_id", sa.String(length=36), nullable=True),
        sa.Column("movement_type", sa.String(length=32), nullable=False),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("exchange_rate_id", sa.String(length=36), nullable=True),
        sa.Column("converted_cny_amount", sa.Numeric(18, 2), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["account_id"], ["accounts.id"]),
        sa.ForeignKeyConstraint(["entry_id"], ["financial_entries.id"]),
        sa.ForeignKeyConstraint(["exchange_rate_id"], ["currency_rates.id"]),
        sa.ForeignKeyConstraint(["statement_cycle_id"], ["credit_statement_cycles.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_account_movements_entry", "account_movements", ["entry_id"])
    op.create_index("ix_account_movements_account", "account_movements", ["account_id"])

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("actor", sa.String(length=32), nullable=False),
        sa.Column("action_type", sa.String(length=120), nullable=False),
        sa.Column("target_type", sa.String(length=120), nullable=False),
        sa.Column("target_id", sa.String(length=36), nullable=False),
        sa.Column("before_snapshot", sa.JSON(), nullable=True),
        sa.Column("after_snapshot", sa.JSON(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_audit_logs_target", "audit_logs", ["target_type", "target_id"])

    currency_rates = sa.table(
        "currency_rates",
        sa.column("id", sa.String),
        sa.column("from_currency", sa.String),
        sa.column("to_currency", sa.String),
        sa.column("rate", sa.Numeric),
        sa.column("date", sa.Date),
        sa.column("source", sa.String),
        sa.column("note", sa.Text),
        sa.column("created_at", sa.DateTime),
        sa.column("updated_at", sa.DateTime),
    )
    now = datetime.now(timezone.utc)
    op.bulk_insert(
        currency_rates,
        [
            {
                "id": "00000000-0000-0000-0000-000000000680",
                "from_currency": "USD",
                "to_currency": "CNY",
                "rate": Decimal("6.8"),
                "date": date(2026, 5, 16),
                "source": "manual",
                "note": "Initial manual USD/CNY rate confirmed for V1.",
                "created_at": now,
                "updated_at": now,
            }
        ],
    )


def downgrade() -> None:
    op.drop_index("ix_audit_logs_target", table_name="audit_logs")
    op.drop_table("audit_logs")
    op.drop_index("ix_account_movements_account", table_name="account_movements")
    op.drop_index("ix_account_movements_entry", table_name="account_movements")
    op.drop_table("account_movements")
    op.drop_index("ix_entry_category_lines_entry", table_name="entry_category_lines")
    op.drop_table("entry_category_lines")
    op.drop_index("ix_credit_statement_cycles_account_dates", table_name="credit_statement_cycles")
    op.drop_table("credit_statement_cycles")
    op.drop_index("ix_financial_entries_date_status", table_name="financial_entries")
    op.drop_table("financial_entries")
    op.drop_index("ix_categories_type_active", table_name="categories")
    op.drop_table("categories")
    op.drop_index("ix_accounts_type_status", table_name="accounts")
    op.drop_table("accounts")
    op.drop_index("ix_currency_rates_pair_date", table_name="currency_rates")
    op.drop_table("currency_rates")

