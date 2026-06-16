"""recompute credit-account liability to the single source of truth

Revision ID: 202606160001
Revises: 202606150001
Create Date: 2026-06-16

v2.2.0 P1 (D1=甲): ``current_liability`` becomes a *derived* value —
``Σ(non-voided statement cycle: statement_amount − paid_amount)`` (PROJECT_PLAN
§5.2 公式). Historically ``AccountCreate`` accepted an opening liability number
that was累加 by movements but never covered by any cycle, so the stored
``current_liability`` could drift from ``Σcycle`` (the −1400 / 花呗 800 bug). This
migration re-derives every credit account's ``current_liability`` from its cycles
and parks the drift in a traceable trail.

For each credit account where ``stored ≠ Σcycle``:
  1. ``UPDATE accounts SET current_liability = Σcycle``;
  2. INSERT an ``account_adjustments`` row (``source='liability_recompute_migration'``,
     ``delta_amount = Σcycle − stored``, ``balance_before = stored``,
     ``balance_after = Σcycle``) so the抹平 amount is auditable;
  3. INSERT an ``audit_logs`` row (``action_type='account.liability_recompute_migration'``)
     with before/after snapshots.

The migration uses a **dedicated source/action marker** (``*_migration``) distinct
from the runtime "重算此账户" API (``app.services.reconciliation.recompute_credit_account``,
which writes ``source='liability_recompute'`` / ``action_type='account.liability_recompute'``).
This keeps the two trails isolated: ``downgrade`` only deletes/restores **its own**
migration rows and never touches API-produced adjustments. So the sequence
「升级 → 用户在对账界面点重算(API) → downgrade」 correctly undoes only the migration's
change (liability back to the **pre-migration** value via this row's ``balance_before``),
leaves the user's API adjustment intact, and removes only the migration adjustment.

The default policy抹平 the delta as an opening mis-entry (PROJECT_PLAN §5.7 D1:
用户已确认花呗真实=600=Σcycle、stored 1400 的 800 是开账误录). Per §5.7, the
read-only audit script ``scripts/audit_credit_liability.py`` should be run first
to confirm每个账户的 delta 含义 (误录 vs 漏账单); accounts that are actually
"漏账单" should have the missing cycle created *before* this migration runs, so
their ``Σcycle`` already reflects the true liability and this migration leaves
them untouched (delta 0).

Postgres/SQLite-compatible: pure data UPDATE + INSERT via ``sa.text``, no DDL,
no dialect branch. Idempotent: re-running matches 0 drifted accounts once the
column already equals ``Σcycle``. Reversible: ``downgrade`` restores each
account's pre-migration ``current_liability`` from this migration's own
``balance_before`` and removes only the migration's adjustment/audit rows —
runtime API recompute adjustments (bare ``liability_recompute`` source) are left
untouched (reviewer Y1).
"""
import json
from decimal import Decimal
from uuid import uuid4

from alembic import op
import sqlalchemy as sa

revision = "202606160001"
down_revision = "202606150001"
branch_labels = None
depends_on = None

# Dedicated migration markers — must stay DISTINCT from the runtime recompute API
# (``app.services.reconciliation.recompute_credit_account`` uses bare
# ``liability_recompute`` / ``account.liability_recompute``). The ``*_migration``
# suffix lets ``downgrade`` delete/restore only this migration's rows and never
# touch API-produced adjustments (reviewer Y1).
ADJUSTMENT_SOURCE = "liability_recompute_migration"
AUDIT_ACTION = "account.liability_recompute_migration"
ADJUSTMENT_REASON = "v2.2.0 P1 credit liability recompute"
# Mirror app.services.ledger.CREDIT_LIABILITY_EXCLUDED_CYCLE_STATUSES.
EXCLUDED_CYCLE_STATUSES = ("voided",)
QUANT = Decimal("0.01")


def _q(value) -> Decimal:
    return Decimal(value).quantize(QUANT)


def _sum_cycle(bind, account_id: str) -> Decimal:
    rows = bind.execute(
        sa.text(
            "SELECT statement_amount, paid_amount, status "
            "FROM credit_statement_cycles WHERE credit_account_id = :aid"
        ),
        {"aid": account_id},
    ).all()
    total = Decimal("0")
    for statement_amount, paid_amount, status in rows:
        if status in EXCLUDED_CYCLE_STATUSES:
            continue
        total += Decimal(statement_amount) - Decimal(paid_amount)
    return _q(total)


def upgrade() -> None:
    bind = op.get_bind()
    accounts = bind.execute(
        sa.text(
            "SELECT id, name, currency, current_liability FROM accounts "
            "WHERE type = 'credit'"
        )
    ).all()

    for account_id, name, currency, current_liability in accounts:
        stored = _q(current_liability)
        sum_cycle = _sum_cycle(bind, account_id)
        delta = _q(sum_cycle - stored)
        if delta == 0:
            continue

        bind.execute(
            sa.text(
                "UPDATE accounts SET current_liability = :v, "
                "updated_at = CURRENT_TIMESTAMP WHERE id = :id"
            ),
            {"v": str(sum_cycle), "id": account_id},
        )
        bind.execute(
            sa.text(
                "INSERT INTO account_adjustments "
                "(id, account_id, reason, delta_amount, currency, "
                " balance_before, balance_after, source, note, created_by, "
                " created_at, updated_at) "
                "VALUES (:id, :account_id, :reason, :delta, :currency, "
                " :before, :after, :source, :note, 'system', "
                " CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {
                "id": str(uuid4()),
                "account_id": account_id,
                "reason": ADJUSTMENT_REASON,
                "delta": str(delta),
                "currency": currency,
                "before": str(stored),
                "after": str(sum_cycle),
                "source": ADJUSTMENT_SOURCE,
                "note": (
                    f"Recomputed {name} current_liability from {stored} to "
                    f"{sum_cycle} (Σ non-voided cycle); drift {delta} parked."
                ),
            },
        )
        bind.execute(
            sa.text(
                "INSERT INTO audit_logs "
                "(id, actor, action_type, target_type, target_id, "
                " before_snapshot, after_snapshot, note, created_at, updated_at) "
                "VALUES (:id, 'system', :action, 'account', :target_id, "
                " :before, :after, :note, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            ),
            {
                "id": str(uuid4()),
                "action": AUDIT_ACTION,
                "target_id": account_id,
                "before": json.dumps(
                    {"current_liability": str(stored), "currency": currency}
                ),
                "after": json.dumps(
                    {
                        "current_liability": str(sum_cycle),
                        "sum_cycle": str(sum_cycle),
                        "delta": str(delta),
                        "currency": currency,
                    }
                ),
                "note": ADJUSTMENT_REASON,
            },
        )


def downgrade() -> None:
    """Restore each account's pre-migration ``current_liability``.

    The original value is the ``balance_before`` recorded on **this migration's**
    ``account_adjustments`` rows (``source=ADJUSTMENT_SOURCE`` = the dedicated
    ``liability_recompute_migration`` marker). After restoring, only the
    migration's adjustment and audit rows are removed.

    Crucially, the filters key on the migration-specific marker, so runtime
    "重算此账户" API adjustments (bare ``source='liability_recompute'`` /
    ``action_type='account.liability_recompute'``) are NEVER deleted or used as a
    restore source. The sequence 「升级 → API 重算 → downgrade」 therefore returns
    the account to its true pre-migration value and keeps the user's API
    adjustment intact (reviewer Y1).
    """
    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT account_id, balance_before FROM account_adjustments "
            "WHERE source = :source"
        ),
        {"source": ADJUSTMENT_SOURCE},
    ).all()
    for account_id, balance_before in rows:
        bind.execute(
            sa.text(
                "UPDATE accounts SET current_liability = :v, "
                "updated_at = CURRENT_TIMESTAMP WHERE id = :id"
            ),
            {"v": str(_q(balance_before)), "id": account_id},
        )
    bind.execute(
        sa.text("DELETE FROM account_adjustments WHERE source = :source"),
        {"source": ADJUSTMENT_SOURCE},
    )
    bind.execute(
        sa.text("DELETE FROM audit_logs WHERE action_type = :action"),
        {"action": AUDIT_ACTION},
    )
