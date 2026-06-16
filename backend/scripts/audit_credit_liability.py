"""Read-only audit of credit-account liability drift (v2.2.0 P1).

Walks every credit account and reports the three numbers that, after v2.2.0 P1,
must agree:

    stored      = the account's stored ``current_liability`` column
    sum_cycle   = Σ(non-voided statement cycle: statement_amount − paid_amount)
                  -- the new single source of truth (PROJECT_PLAN §5.2 公式)
    delta       = stored − sum_cycle  (the drift; 0 once healthy)

For each drifted account it prints the three numbers plus a **neutral** note that
lays out *both* possible meanings of the delta and the correct handling of each —
it deliberately does NOT pre-judge which one applies. The sign of the delta does
not by itself distinguish "开账误录" from "漏录已出账单": both can produce
``delta = stored − Σcycle > 0`` (reviewer Y2). Only a human who knows the card's
TRUE current liability can decide.

    delta > 0  (stored 比账单口径多 X):
        ① 开账误录 → 应下调至 Σcycle（迁移默认就是这样处理）。
        ② 漏录一张已出账单 → 真欠款 = stored，应先补这张 cycle（补后 Σcycle 已含真欠款，
           迁移对它 no-op），**绝不可让迁移把它抹平**。
    delta < 0  (stored 比账单口径少):
        多半是漏录还款 / 数据异常 / 历史 charge 未反映到 stored —— 人工核对后处理。

This script is STRICTLY READ-ONLY: it opens a session, runs SELECTs, prints, and
exits. It never UPDATEs, INSERTs, or commits. Run it (against a backup or in a
read replica / pre-migration snapshot) to确认 each account's delta meaning before
applying the recompute migration ``202606160001`` in production
(PROJECT_PLAN §5.7 D1 子问: read-only 审计后逐账户确认).

⚠️  本表仅供人工逐账户判断，不预设结论。迁移默认把 delta>0 的账户下调到 Σcycle；若某账户
    的 delta>0 实为「漏录已出账单」（真欠款=stored），务必在迁移前先补这张 cycle，否则会被
    误抹真实欠款。勿盲信任何「疑似」标签。

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
    """Neutral two-sided note — never pre-judges误录 vs 漏账单 (reviewer Y2)."""
    if delta == 0:
        return "一致，无需处理"
    if delta > 0:
        return (
            "stored 比 Σcycle 多 — 可能①开账误录(应下调,迁移默认如此) "
            "②漏录已出账单(应先补 cycle,真欠款=stored)。须人工判断,勿盲信"
        )
    return (
        "stored 比 Σcycle 少 — 可能漏录还款/数据异常,人工核(迁移会上调到 Σcycle)"
    )


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
        print(
            "⚠️  本表仅供人工逐账户判断，不预设结论。迁移默认把 delta>0 的账户下调到 Σcycle；"
        )
        print(
            "   delta>0 也可能是『漏录已出账单』(真欠款=stored)，这类账户务必先补 cycle 再迁移，"
        )
        print("   否则会被误抹真实欠款。勿盲信下方任何措辞，请核对该卡真实欠款后再决定。")
        print("=" * 96)
        header = f"{'账户名':<24} {'currency':<8} {'stored':>14} {'Σcycle':>14} {'delta':>14}  含义(须人工判断)"
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
        if drifted:
            print(
                "⚠️  再次提醒：迁移默认对 delta>0 下调到 Σcycle。漏录已出账单的账户务必先补 cycle，"
            )
            print("   否则其真实欠款会被误抹。请逐账户核对该卡真实欠款后再执行迁移。")


if __name__ == "__main__":
    main()
