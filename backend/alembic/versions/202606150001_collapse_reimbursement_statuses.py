"""collapse reimbursement claim statuses to three states

Revision ID: 202606150001
Revises: 202606120001
Create Date: 2026-06-15

v2.1.0 P2 collapses the reimbursement claim status machine from nine
multi-person/enterprise states down to three single-user states:

    pending   (待回款) -- the receivable is still outstanding
    received  (已到账) -- the cash has landed (set via mark-received)
    abandoned (已放弃) -- the claim was given up / its source entry voided

This is a pure DATA migration. ``reimbursement_claims.status`` is a free
``String(32)`` with no DB-level CHECK constraint (allowed values are enforced
only at the schema layer), so no schema change is required — only the values of
existing rows are remapped:

    reimbursable / invoice_pending / submitted / approved / waiting_received
                                                              -> pending
    partial_received                                          -> received
    rejected                                                  -> abandoned
    received / abandoned                                       (left unchanged)

The remapping is single-direction (rejected/partial_received detail is lost),
which the user accepted (PROJECT_PLAN §5.7 D1). It is Postgres/SQLite-compatible
with no dialect branch. Idempotent: re-running matches 0 rows once values are
already collapsed. Downgrade is a no-op — the original fine-grained states
cannot be reconstructed and resurrecting them would be wrong.
"""
from alembic import op
import sqlalchemy as sa

revision = "202606150001"
down_revision = "202606120001"
branch_labels = None
depends_on = None


# old status value -> new three-state value
_STATUS_MAP = {
    "reimbursable": "pending",
    "invoice_pending": "pending",
    "submitted": "pending",
    "approved": "pending",
    "waiting_received": "pending",
    "partial_received": "received",
    "rejected": "abandoned",
}


def upgrade() -> None:
    bind = op.get_bind()
    for old_status, new_status in _STATUS_MAP.items():
        bind.execute(
            sa.text(
                "UPDATE reimbursement_claims SET status = :new "
                "WHERE status = :old"
            ),
            {"new": new_status, "old": old_status},
        )


def downgrade() -> None:
    # No-op: the original fine-grained statuses cannot be reconstructed from the
    # collapsed three-state values, so there is nothing to revert.
    pass
