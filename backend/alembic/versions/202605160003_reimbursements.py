"""Add reimbursement claims.

Revision ID: 202605160003
Revises: 202605160002
Create Date: 2026-05-16
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "202605160003"
down_revision: Union[str, None] = "202605160002"
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
    op.add_column("entry_category_lines", sa.Column("reimbursement_payer", sa.String(length=120), nullable=True))
    op.add_column("entry_category_lines", sa.Column("reimbursement_expected_date", sa.Date(), nullable=True))
    op.add_column("entry_category_lines", sa.Column("reimbursement_status", sa.String(length=32), nullable=True))

    op.create_table(
        "reimbursement_claims",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("linked_entry_id", sa.String(length=36), nullable=False),
        sa.Column("linked_entry_line_id", sa.String(length=36), nullable=True),
        sa.Column("amount", sa.Numeric(18, 2), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("exchange_rate_id", sa.String(length=36), nullable=True),
        sa.Column("converted_cny_amount", sa.Numeric(18, 2), nullable=True),
        sa.Column("payer", sa.String(length=120), nullable=False),
        sa.Column("expected_date", sa.Date(), nullable=False),
        sa.Column("actual_received_date", sa.Date(), nullable=True),
        sa.Column("received_account_id", sa.String(length=36), nullable=True),
        sa.Column("received_entry_id", sa.String(length=36), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="reimbursable"),
        sa.Column("cash_flow_item_id", sa.String(length=36), nullable=True),
        sa.Column("invoice_attachment_ids", sa.JSON(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *timestamp_columns(),
        sa.ForeignKeyConstraint(["cash_flow_item_id"], ["cash_flow_items.id"]),
        sa.ForeignKeyConstraint(["exchange_rate_id"], ["currency_rates.id"]),
        sa.ForeignKeyConstraint(["linked_entry_id"], ["financial_entries.id"]),
        sa.ForeignKeyConstraint(["linked_entry_line_id"], ["entry_category_lines.id"]),
        sa.ForeignKeyConstraint(["received_account_id"], ["accounts.id"]),
        sa.ForeignKeyConstraint(["received_entry_id"], ["financial_entries.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_reimbursement_claims_status", "reimbursement_claims", ["status"])
    op.create_index("ix_reimbursement_claims_expected_date", "reimbursement_claims", ["expected_date"])
    op.create_index("ix_reimbursement_claims_linked_entry", "reimbursement_claims", ["linked_entry_id"])


def downgrade() -> None:
    op.drop_index("ix_reimbursement_claims_linked_entry", table_name="reimbursement_claims")
    op.drop_index("ix_reimbursement_claims_expected_date", table_name="reimbursement_claims")
    op.drop_index("ix_reimbursement_claims_status", table_name="reimbursement_claims")
    op.drop_table("reimbursement_claims")
    op.drop_column("entry_category_lines", "reimbursement_status")
    op.drop_column("entry_category_lines", "reimbursement_expected_date")
    op.drop_column("entry_category_lines", "reimbursement_payer")

