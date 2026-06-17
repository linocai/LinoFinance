"""one-off data fix: correct 白条 August statement to real amount (user-confirmed 2026-06-16)

User-confirmed: 白条 8月账单 real outstanding should be 4031.18 (system had 389.74). July is
already correct and must NOT be touched. So: set the single unpaid 389.74 白条 cycle (= August)
→ 4031.18, sync its repayment cash flow, recompute 白条 current_liability = Σ未还cycle.

GUARDED ONE-OFF (PostgreSQL prod only): corrects one row in the single production DB (Postgres).
NO-OP on any non-Postgres dialect (SQLite test/dev), so `alembic upgrade head` stays green
everywhere (CI / migration-chain tests). On Postgres it matches exactly one unpaid 389.74 cycle;
any other count raises and aborts (deploy fails, pre-migration backup intact, nothing changed) —
fail-closed for the real prod application. Already applied to prod; never re-runs there.

Revision ID: 202606160003
Revises: 202606160002
Create Date: 2026-06-16
"""
from decimal import Decimal

import sqlalchemy as sa
from alembic import op

revision = "202606160003"
down_revision = "202606160002"
branch_labels = None
depends_on = None

OLD_AUGUST = Decimal("389.74")
NEW_AUGUST = Decimal("4031.18")


def upgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name != "postgresql":
        # One-off production (Postgres) data fix; no-op on SQLite test/dev DBs so the
        # `alembic upgrade head` migration-chain stays green. Prod already applied this.
        return

    accs = conn.execute(
        sa.text("SELECT id FROM accounts WHERE type = 'credit' AND name LIKE :n"),
        {"n": "%白条%"},
    ).fetchall()
    if len(accs) != 1:
        raise RuntimeError(f"fix_baitiao: expected exactly 1 白条 credit account, got {len(accs)}")
    acc_id = accs[0][0]

    aug = conn.execute(
        sa.text(
            "SELECT id, linked_cash_flow_item_id FROM credit_statement_cycles "
            "WHERE credit_account_id = :a AND statement_amount = :amt "
            "AND status NOT IN ('paid', 'closed', 'voided')"
        ),
        {"a": acc_id, "amt": OLD_AUGUST},
    ).fetchall()
    if len(aug) != 1:
        raise RuntimeError(f"fix_baitiao: expected exactly 1 unpaid 389.74 白条 cycle, got {len(aug)}")
    cycle_id, cf_id = aug[0]

    conn.execute(
        sa.text("UPDATE credit_statement_cycles SET statement_amount = :amt WHERE id = :id"),
        {"amt": NEW_AUGUST, "id": cycle_id},
    )
    if cf_id:
        conn.execute(
            sa.text(
                "UPDATE cash_flow_items SET amount = :amt, converted_cny_amount = :amt "
                "WHERE id = :id AND status NOT IN ('settled', 'cancelled')"
            ),
            {"amt": NEW_AUGUST, "id": cf_id},
        )

    # recompute 白条 liability = Σ(non-voided cycle: statement - paid); no hardcoded total
    # assertion (July's correct value is whatever it already is and must stay untouched).
    total = conn.execute(
        sa.text(
            "SELECT COALESCE(SUM(statement_amount - paid_amount), 0) FROM credit_statement_cycles "
            "WHERE credit_account_id = :a AND status NOT IN ('paid', 'closed', 'voided')"
        ),
        {"a": acc_id},
    ).scalar()
    total = Decimal(str(total))
    conn.execute(
        sa.text("UPDATE accounts SET current_liability = :t WHERE id = :a"),
        {"t": total, "a": acc_id},
    )
    print(f"fix_baitiao: 白条 August 389.74 -> 4031.18; new current_liability = {total}")


def downgrade() -> None:
    # No-op on non-Postgres (test/dev) so downgrade chains pass. On prod this is an
    # irreversible data fix; roll back via the pre-migration backup.
    if op.get_bind().dialect.name == "postgresql":
        raise RuntimeError(
            "202606160003 is a one-off data correction; restore the pre-migration backup to revert."
        )
