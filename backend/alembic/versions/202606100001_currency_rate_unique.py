"""currency_rate unique (from, to, date) + dedup

Revision ID: 202606100001
Revises: 202605270001
Create Date: 2026-06-10

Adds a unique constraint on ``currency_rates(from_currency, to_currency,
date)`` (audit 2.5). Before adding it, removes pre-existing duplicate rows
for the same key, keeping the most recent ``created_at`` (ties broken by
``id``). SQLite goes through ``batch_alter_table`` so the local runner can
recreate the table with the constraint.
"""
from alembic import op
import sqlalchemy as sa

revision = "202606100001"
down_revision = "202605270001"
branch_labels = None
depends_on = None

UQ_NAME = "currency_rates_from_to_date_uq"


def _dedup_currency_rates() -> None:
    """Delete duplicate (from, to, date) rows, keeping latest created_at."""
    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT id, from_currency, to_currency, date, created_at "
            "FROM currency_rates"
        )
    ).fetchall()

    # Group by the composite key; keep the row with the greatest
    # (created_at, id) so the result is deterministic across dialects.
    keepers: dict = {}
    for row in rows:
        key = (row.from_currency, row.to_currency, row.date)
        rank = (row.created_at, row.id)
        current = keepers.get(key)
        if current is None or rank > current[1]:
            keepers[key] = (row.id, rank)

    keep_ids = {value[0] for value in keepers.values()}
    delete_ids = [row.id for row in rows if row.id not in keep_ids]
    for stale_id in delete_ids:
        bind.execute(
            sa.text("DELETE FROM currency_rates WHERE id = :id"),
            {"id": stale_id},
        )


def upgrade() -> None:
    _dedup_currency_rates()
    if op.get_bind().dialect.name == "sqlite":
        # SQLite cannot ALTER ADD CONSTRAINT; copy-and-move recreates the
        # table with the new unique constraint (local dev / test runner).
        with op.batch_alter_table("currency_rates", recreate="always") as batch_op:
            batch_op.create_unique_constraint(
                UQ_NAME, ["from_currency", "to_currency", "date"]
            )
    else:
        op.create_unique_constraint(
            UQ_NAME, "currency_rates", ["from_currency", "to_currency", "date"]
        )


def downgrade() -> None:
    if op.get_bind().dialect.name == "sqlite":
        with op.batch_alter_table("currency_rates", recreate="always") as batch_op:
            batch_op.drop_constraint(UQ_NAME, type_="unique")
    else:
        op.drop_constraint(UQ_NAME, "currency_rates", type_="unique")
