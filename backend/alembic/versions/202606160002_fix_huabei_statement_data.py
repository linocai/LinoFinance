"""one-off data fix: correct 花呗 statement cycles to real amounts + drop orphan repayment cash flow

User-confirmed (2026-06-16) manual correction of production data:
  - 花呗 had 3 unpaid cycles summing to 1439.61: 6-01 ¥995.06 + 7月 ¥283.22 + 8月 ¥161.33.
  - Real situation per user: 7月待还 1076.33 + 8月待还 161.33 = 1237.66 (no June bill).
  - So: VOID the 995.06 (June) cycle, set the 283.22 (July) cycle → 1076.33 (+ its repayment
    cash flow), keep 161.33 (August), recompute 花呗 current_liability = Σ未还cycle = 1237.66.
  - Also delete the cross-object orphan: the single settled cash flow with no linked entry.

FAIL-CLOSED: every match is asserted to hit exactly the expected row count; any mismatch raises
and aborts the migration (deploy fails, pre-migration backup intact, nothing changed). Guarded by
account name, so on any DB without this exact 花呗 data it raises rather than silently mis-acting —
acceptable because this migration is only ever meant to run against the one production DB. Local
test DBs use create_all (not alembic upgrade), so this never runs in CI/tests.

The proper fix (a 对账 correction tool so this never needs a hand migration) is in PROJECT_PLAN §6
backlog.

Revision ID: 202606160002
Revises: 202606160001
Create Date: 2026-06-16
"""
from decimal import Decimal

import sqlalchemy as sa
from alembic import op

revision = "202606160002"
down_revision = "202606160001"
branch_labels = None
depends_on = None

def _one(conn, sql, **params):
    rows = conn.execute(sa.text(sql), params).fetchall()
    return rows


def upgrade() -> None:
    conn = op.get_bind()

    # 1. locate the single 花呗 credit account ---------------------------------
    accs = _one(
        conn,
        "SELECT id FROM accounts WHERE type = 'credit' AND name LIKE :n",
        n="%花呗%",
    )
    if len(accs) != 1:
        raise RuntimeError(f"fix_huabei: expected exactly 1 花呗 credit account, got {len(accs)}")
    acc_id = accs[0][0]

    # 2. VOID the June 995.06 cycle -------------------------------------------
    june = _one(
        conn,
        "SELECT id FROM credit_statement_cycles "
        "WHERE credit_account_id = :a AND statement_amount = :amt AND status NOT IN ('paid', 'closed', 'voided')",
        a=acc_id, amt=Decimal("995.06"),
    )
    if len(june) != 1:
        raise RuntimeError(f"fix_huabei: expected exactly 1 unpaid 995.06 cycle, got {len(june)}")
    conn.execute(
        sa.text("UPDATE credit_statement_cycles SET status = 'voided' WHERE id = :id"),
        {"id": june[0][0]},
    )

    # 3. July 283.22 cycle -> 1076.33 (+ its linked repayment cash flow) -------
    july = _one(
        conn,
        "SELECT id, linked_cash_flow_item_id FROM credit_statement_cycles "
        "WHERE credit_account_id = :a AND statement_amount = :amt AND status NOT IN ('paid', 'closed', 'voided')",
        a=acc_id, amt=Decimal("283.22"),
    )
    if len(july) != 1:
        raise RuntimeError(f"fix_huabei: expected exactly 1 unpaid 283.22 cycle, got {len(july)}")
    july_id, july_cf_id = july[0]
    conn.execute(
        sa.text("UPDATE credit_statement_cycles SET statement_amount = :amt WHERE id = :id"),
        {"amt": Decimal("1076.33"), "id": july_id},
    )
    if july_cf_id:
        conn.execute(
            sa.text(
                "UPDATE cash_flow_items SET amount = :amt, converted_cny_amount = :amt "
                "WHERE id = :id AND status NOT IN ('settled', 'cancelled')"
            ),
            {"amt": Decimal("1076.33"), "id": july_cf_id},
        )

    # 4. delete the single cross-object orphan (settled cash flow, no entry) ---
    orphans = _one(
        conn,
        "SELECT id FROM cash_flow_items WHERE status = 'settled' AND linked_entry_id IS NULL",
    )
    if len(orphans) != 1:
        raise RuntimeError(f"fix_huabei: expected exactly 1 settled-no-entry orphan, got {len(orphans)}")
    conn.execute(
        sa.text("DELETE FROM cash_flow_items WHERE id = :id"),
        {"id": orphans[0][0]},
    )

    # 5. recompute 花呗 liability = Σ(non-voided cycle: statement - paid) -------
    total = conn.execute(
        sa.text(
            "SELECT COALESCE(SUM(statement_amount - paid_amount), 0) "
            "FROM credit_statement_cycles WHERE credit_account_id = :a AND status NOT IN ('paid', 'closed', 'voided')"
        ),
        {"a": acc_id},
    ).scalar()
    total = Decimal(str(total))
    if abs(total - Decimal("1237.66")) > Decimal("0.01"):
        raise RuntimeError(f"fix_huabei: post-fix Σcycle = {total}, expected 1237.66 — aborting")
    conn.execute(
        sa.text("UPDATE accounts SET current_liability = :t WHERE id = :a"),
        {"t": total, "a": acc_id},
    )


def downgrade() -> None:
    # Irreversible data fix. The deleted orphan cash flow cannot be reconstructed;
    # the July amount / June void are not auto-restored. Roll back via the
    # pre-migration backup (deploy-api.sh / production_migrate.py takes one).
    raise RuntimeError(
        "202606160002 is a one-off data correction; restore the pre-migration backup to revert."
    )
