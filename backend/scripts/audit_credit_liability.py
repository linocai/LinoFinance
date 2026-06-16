"""Read-only audit of credit-account liability drift (v2.2.0 P1).

Walks every credit account and reports the three numbers that, after v2.2.0 P1,
must agree:

    stored      = the account's stored ``current_liability`` column
    sum_cycle   = Σ(non-voided statement cycle: statement_amount − paid_amount)
                  -- the new single source of truth (PROJECT_PLAN §5.2 公式)
    delta       = stored − sum_cycle  (the drift; 0 once healthy)

It also prints a heuristic category for each drifted account so the user can
decide, per account, whether the recompute migration should抹平 the delta as an
opening mis-entry (误录) or whether a missing statement cycle (漏账单) should be
created instead before migrating:

    误录?      stored > sum_cycle  -- stored carries an opening/import residue
                that no cycle covers; the recompute will lower the liability.
    漏账单?    stored < sum_cycle  -- cycles总额 exceeds stored; a历史 charge
                wasn't reflected in the stored field; the recompute will raise it.

This script is STRICTLY READ-ONLY: it opens a session, runs SELECTs, prints, and
exits. It never UPDATEs, INSERTs, or commits. Run it (against a backup or in a
read replica / pre-migration snapshot) to确认 each account's delta meaning before
applying the recompute migration ``202606160001`` in production
(PROJECT_PLAN §5.7 D1 子问: read-only 审计后逐账户确认).

Usage:
    cd backend && source .venv/bin/activate
    LINOFINANCE_DATABASE_URL=<url> .venv/bin/python scripts/audit_credit_liability.py

If ``LINOFINANCE_DATABASE_URL`` is unset, the app's configured database is used.
"""
from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select

from app import models  # noqa: F401  (register mappers)
from app.db.session import SessionLocal
from app.models.account import Account
from app.models.credit_statement_cycle import CreditStatementCycle

# Mirror app.services.ledger.CREDIT_LIABILITY_EXCLUDED_CYCLE_STATUSES exactly so
# the audit number matches the recompute migration / runtime to the cent. Kept as
# a local literal so the script stays import-light and never触碰 service writes.
EXCLUDED_CYCLE_STATUSES = {"voided"}
QUANT = Decimal("0.01")


def _q(value: Decimal) -> Decimal:
    return Decimal(value).quantize(QUANT)


def _sum_cycle(db, account_id: str) -> Decimal:
    total = Decimal("0")
    rows = db.execute(
        select(CreditStatementCycle).where(
            CreditStatementCycle.credit_account_id == account_id
        )
    ).scalars()
    for cycle in rows:
        if cycle.status in EXCLUDED_CYCLE_STATUSES:
            continue
        total += Decimal(cycle.statement_amount) - Decimal(cycle.paid_amount)
    return _q(total)


def _category(delta: Decimal) -> str:
    if delta == 0:
        return "OK (一致)"
    if delta > 0:
        return "疑似误录 (stored 高于 Σcycle，recompute 将下调并记 adjustment)"
    return "疑似漏账单 (stored 低于 Σcycle，先补账单再迁移，否则 recompute 会上调)"


def main() -> None:
    drifted = 0
    with SessionLocal() as db:
        accounts = db.execute(
            select(Account)
            .where(Account.type == "credit")
            .order_by(Account.display_order, Account.name)
        ).scalars()
        rows = list(accounts)

        print("=" * 96)
        print("信用账户欠款审计 (read-only) — current_liability vs Σ(未voided cycle)")
        print("=" * 96)
        header = f"{'账户名':<24} {'currency':<8} {'stored':>14} {'Σcycle':>14} {'delta':>14}  疑似类别"
        print(header)
        print("-" * 96)

        for account in rows:
            stored = _q(Decimal(account.current_liability))
            sum_cycle = _sum_cycle(db, account.id)
            delta = _q(stored - sum_cycle)
            if delta != 0:
                drifted += 1
            print(
                f"{account.name[:24]:<24} {account.currency:<8} "
                f"{stored:>14} {sum_cycle:>14} {delta:>14}  {_category(delta)}"
            )

        print("-" * 96)
        print(
            f"共 {len(rows)} 个信用账户，其中 {drifted} 个存在 delta（需逐账户确认 delta 含义后再迁移）。"
        )
        print("本脚本只读，未对数据库做任何写入。")


if __name__ == "__main__":
    main()
