"""void legacy draft financial entries

Revision ID: 202606120001
Revises: 202606100002
Create Date: 2026-06-12

v1.4.0 removes the ``draft`` entry status entirely (the create API now only
accepts ``confirmed``; the ``/entries/{id}/confirm`` route is gone). Draft
entries never affected balances, reports, or reimbursement claims, so there is
nothing to reverse — but any leftover ``status='draft'`` rows would become
unreachable dead state. This data migration parks them in ``voided`` so the
table only holds reachable statuses.

``financial_entries.status`` is a free ``String(32)`` with no DB-level CHECK
constraint (the allowed values are enforced only at the schema layer), so this
is a pure data update with no schema change. Production currently has 0 draft
rows; the migration is a safety net and a no-op when none exist.

Idempotent: re-running upgrades simply matches 0 rows once the drafts are gone.
Downgrade is intentionally a no-op — voided drafts are indistinguishable from
genuinely voided entries, and resurrecting them would be wrong.
"""
from alembic import op
import sqlalchemy as sa

revision = "202606120001"
down_revision = "202606100002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text(
            "UPDATE financial_entries SET status = 'voided' WHERE status = 'draft'"
        )
    )


def downgrade() -> None:
    # No-op: voided legacy drafts cannot be safely distinguished from real
    # voided entries, so there is nothing to revert.
    pass
