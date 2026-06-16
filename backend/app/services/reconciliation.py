from decimal import Decimal
from typing import Dict, Iterable, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.timeutils import app_today
from app.models.account import Account
from app.models.audit_log import AuditLog
from app.models.cash_flow import CashFlowItem
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.entry import AccountMovement
from app.models.reimbursement import ReimbursementClaim
from app.models.reconciliation import AccountAdjustment
from app.schemas.reconciliation import (
    AccountAdjustmentCreate,
    ConflictPointer,
    CreditRecomputeResponse,
    ReconciliationAccountRead,
    ReconciliationAccountsResponse,
    ReconciliationBreakdown,
    ReconciliationCheckAccount,
    ReconciliationCheckResponse,
    ReconciliationConflict,
)
from app.services.ledger import (
    LedgerNotFoundError,
    LedgerValidationError,
    quantize_money,
    recompute_credit_liability,
    sum_open_statement_total,
)

RECONCILIATION_THRESHOLD = Decimal("0.01")


def list_account_reconciliation(db: Session) -> ReconciliationAccountsResponse:
    items = [
        _reconciliation_row(db, account)
        for account in db.execute(select(Account).order_by(Account.display_order, Account.name)).scalars()
    ]
    return ReconciliationAccountsResponse(threshold=RECONCILIATION_THRESHOLD, items=items)


def create_adjustment(db: Session, payload: AccountAdjustmentCreate) -> AccountAdjustment:
    account = db.get(Account, payload.account_id)
    if account is None:
        raise LedgerNotFoundError("Account not found")

    # v2.2.0 P1 (D1=甲): credit ``current_liability`` is a derived value
    # (``Σcycle``), so the legacy "set the field to an observed actual amount"
    # path would immediately violate the single source of truth and be
    # overwritten on the next movement. Credit corrections must go through the
    # cycle / recompute path instead, so直接对账信用账户余额走旧机制一律拒绝.
    if account.type == "credit":
        raise LedgerValidationError(
            "Credit accounts cannot be reconciled by setting an actual liability; "
            "their liability is derived from statement cycles — correct the cycles "
            "or use credit recompute instead"
        )

    expected_before = _expected_amount(db, account)
    current_before = _current_amount(account)
    observed_amount = quantize_money(payload.actual_amount or current_before)
    delta = quantize_money(observed_amount - expected_before)
    if delta == 0:
        raise LedgerValidationError("No reconciliation delta to adjust")

    adjustment = AccountAdjustment(
        account_id=account.id,
        reason=payload.reason,
        delta_amount=delta,
        currency=account.currency,
        balance_before=current_before,
        balance_after=observed_amount,
        source="reconciliation",
        note=payload.note,
        created_by=payload.created_by,
    )
    db.add(adjustment)
    # Credit accounts are rejected above; only balance/investment reach here.
    account.current_balance = observed_amount
    db.flush()
    db.add(
        AuditLog(
            actor=payload.created_by,
            action_type="account_adjustment.create",
            target_type="account",
            target_id=account.id,
            before_snapshot={
                "expected_amount": str(expected_before),
                "current_amount": str(current_before),
                "delta_amount": str(current_before - expected_before),
                "currency": account.currency,
            },
            after_snapshot={
                "expected_amount": str(expected_before + delta),
                "current_amount": str(observed_amount),
                "delta_amount": "0.00",
                "currency": account.currency,
                "adjustment_id": adjustment.id,
                "reason": payload.reason,
            },
            note=payload.note,
        )
    )
    db.commit()
    db.refresh(adjustment)
    return adjustment


def _reconciliation_row(db: Session, account: Account) -> ReconciliationAccountRead:
    expected = _expected_amount(db, account)
    current = _current_amount(account)
    delta = quantize_money(current - expected)
    return ReconciliationAccountRead(
        account_id=account.id,
        account_name=account.name,
        account_type=account.type,
        currency=account.currency,
        expected_amount=expected,
        current_amount=current,
        delta_amount=delta,
        needs_adjustment=abs(delta) > RECONCILIATION_THRESHOLD,
    )


def _expected_amount(db: Session, account: Account) -> Decimal:
    if account.type == "credit":
        # v2.2.0 P1: credit liability has a single source of truth —
        # ``Σ(non-voided cycle: statement_amount − paid_amount)``. The stored
        # ``current_liability`` is a cache of exactly this, so expected and
        # current can never disagree (no more恒等-but-drifting double truth).
        return _credit_cycle_total(db, account.id)
    movements = _movement_totals(db, account.id)
    adjustments = _adjustment_total(db, account.id)
    return quantize_money(
        movements["balance_in"]
        + movements["transfer_in"]
        - movements["balance_out"]
        - movements["transfer_out"]
        - movements["credit_repayment"]
        + adjustments
    )


def _movement_totals(db: Session, account_id: str) -> Dict[str, Decimal]:
    totals = {
        "balance_in": Decimal("0"),
        "balance_out": Decimal("0"),
        "transfer_in": Decimal("0"),
        "transfer_out": Decimal("0"),
        "credit_charge": Decimal("0"),
        "credit_repayment": Decimal("0"),
    }
    rows: Iterable[AccountMovement] = db.execute(
        select(AccountMovement).where(AccountMovement.account_id == account_id)
    ).scalars()
    for movement in rows:
        if movement.movement_type in totals:
            totals[movement.movement_type] = quantize_money(
                totals[movement.movement_type] + movement.amount
            )
    return totals


def _adjustment_total(db: Session, account_id: str) -> Decimal:
    total = Decimal("0")
    rows: Iterable[AccountAdjustment] = db.execute(
        select(AccountAdjustment).where(AccountAdjustment.account_id == account_id)
    ).scalars()
    for adjustment in rows:
        total = quantize_money(total + adjustment.delta_amount)
    return total


def _credit_cycle_total(db: Session, account_id: str) -> Decimal:
    # Single source of truth shared with the ledger recompute writer (v2.2.0 P1).
    return sum_open_statement_total(db, account_id)


def _current_amount(account: Account) -> Decimal:
    if account.type == "credit":
        return quantize_money(account.current_liability)
    return quantize_money(account.current_balance)


# ===========================================================================
# v2.2.0 P2 · 对账一致性/冲突检测器 (PROJECT_PLAN §5.3 / §5.4, read-only)
# ===========================================================================
#
# Replaces the old "subtract two identical numbers → always 0 → 无需调整"
# pattern with a multi-dimension detector that surfaces *cross-object*
# relationships that should agree but don't (R2/R3/R4) plus a breakdown view
# that defuses the "600 vs 1400" confusion (R1). The whole check is **read-only**
# — it never writes the DB. Corrections go through the existing
# ``POST /reconciliation/adjustments`` (R3, balance/investment only) or
# ``POST /reconciliation/recompute-credit/{id}`` (R1, credit only).

RECONCILIATION_ADJUSTMENT_SOURCE = "reconciliation"


def run_consistency_check(db: Session) -> ReconciliationCheckResponse:
    accounts = list(
        db.execute(
            select(Account).order_by(Account.display_order, Account.name)
        ).scalars()
    )
    account_results = [_check_account(db, account) for account in accounts]
    orphans = _check_orphans(db)

    has_conflicts = any(
        any(c.severity == "conflict" for c in result.conflicts)
        for result in account_results
    ) or any(c.severity == "conflict" for c in orphans)

    return ReconciliationCheckResponse(
        checked_at=app_today(),
        has_conflicts=has_conflicts,
        accounts=account_results,
        orphans=orphans,
    )


def _check_account(db: Session, account: Account) -> ReconciliationCheckAccount:
    conflicts: List[ReconciliationConflict] = []
    breakdown: Optional[ReconciliationBreakdown] = None

    if account.type == "credit":
        r1, breakdown = _check_credit_three_way(db, account)
        if r1 is not None:
            conflicts.append(r1)
        conflicts.extend(_check_statement_cashflow(db, account))
    else:
        r3 = _check_balance_external(db, account)
        if r3 is not None:
            conflicts.append(r3)

    has_conflicts = any(c.severity == "conflict" for c in conflicts)
    return ReconciliationCheckAccount(
        account_id=account.id,
        account_name=account.name,
        account_type=account.type,
        currency=account.currency,
        has_conflicts=has_conflicts,
        conflicts=conflicts,
        breakdown=breakdown,
    )


def _open_cycles(db: Session, account_id: str) -> List[CreditStatementCycle]:
    cycles = list(
        db.execute(
            select(CreditStatementCycle)
            .where(CreditStatementCycle.credit_account_id == account_id)
            .order_by(CreditStatementCycle.due_date, CreditStatementCycle.cycle_start_date)
        ).scalars()
    )
    return [c for c in cycles if c.status != "voided"]


def _check_credit_three_way(
    db: Session, account: Account
) -> tuple[Optional[ReconciliationConflict], ReconciliationBreakdown]:
    """R1 信用三数拆解：本期待还 / 其他期未还 / 合计.

    Under the P1 derived liability (``current_liability ≡ Σcycle``), the three
    numbers are self-consistent — R1 is primarily an *information* breakdown that
    splits the total so the user sees 本期待还 600 / 其他期未还 800 / 合计 1400
    and the "600 vs 1400" confusion vanishes. If the stored field has somehow
    drifted from ``Σcycle`` (legacy data not yet recomputed) it is surfaced as a
    ``conflict`` with ``fix=internal_recompute``.
    """
    open_cycles = _open_cycles(db, account.id)
    sum_open = quantize_money(sum_open_statement_total(db, account.id))
    unbilled = Decimal("0.00")  # 现模型无未出账消费概念 (§5.2)
    stored = quantize_money(account.current_liability)
    expected = quantize_money(sum_open + unbilled)
    delta = quantize_money(stored - expected)

    # 本期待还 = 最早到期的未结清 cycle 的 remaining；其他期未还 = 合计 − 本期待还.
    current_due = Decimal("0.00")
    for cycle in open_cycles:
        remaining = quantize_money(cycle.statement_amount - cycle.paid_amount)
        if remaining > 0:
            current_due = remaining
            break
    other_due = quantize_money(sum_open - current_due)

    breakdown = ReconciliationBreakdown(
        stored_liability=stored,
        open_statements_total=sum_open,
        unbilled_charges=unbilled,
    )

    offending = [
        ConflictPointer(
            type="credit_statement_cycle",
            id=cycle.id,
            label=_cycle_label(cycle),
        )
        for cycle in open_cycles
        if quantize_money(cycle.statement_amount - cycle.paid_amount) != 0
    ]

    if abs(delta) > RECONCILIATION_THRESHOLD:
        # 真不一致（存量未重算）。
        conflict = ReconciliationConflict(
            code="credit_three_way",
            severity="conflict",
            title="信用欠款与账单不平",
            stored_liability=stored,
            sum_open_statements=sum_open,
            unbilled_charges=unbilled,
            expected_liability=expected,
            delta=delta,
            detail=(
                f"本期待还 {current_due}，其他期未还 {other_due}，"
                f"合计 {sum_open}，但账户记录欠款 {stored}（差 {delta}）。"
            ),
            offending=offending,
            fix="internal_recompute",
        )
        return conflict, breakdown

    # 自洽：仍给一条 info 拆解（界面三数展示），不计 has_conflicts.
    info = ReconciliationConflict(
        code="credit_three_way",
        severity="info",
        title="信用欠款拆解",
        stored_liability=stored,
        sum_open_statements=sum_open,
        unbilled_charges=unbilled,
        expected_liability=expected,
        delta=delta,
        detail=f"本期待还 {current_due}，其他期未还 {other_due}，合计 {sum_open}。",
        offending=offending,
        fix="none",
    )
    return info, breakdown


def _check_statement_cashflow(
    db: Session, account: Account
) -> List[ReconciliationConflict]:
    """R2 每期账单 ↔ 还款现金流.

    Each non-voided cycle with a remaining balance should have exactly one
    linked repayment cash-flow item whose ``amount`` equals ``statement −
    paid``. Mirrors ``ledger.sync_credit_statement_cash_flow`` so it does not
    false-flag. Detects: 缺一笔 / 金额对不上 / cycle 指向已 cancelled 的现金流.
    """
    conflicts: List[ReconciliationConflict] = []
    for cycle in _open_cycles(db, account.id):
        remaining = quantize_money(cycle.statement_amount - cycle.paid_amount)
        if remaining <= 0:
            continue
        linked = (
            db.get(CashFlowItem, cycle.linked_cash_flow_item_id)
            if cycle.linked_cash_flow_item_id
            else None
        )
        if linked is None:
            conflicts.append(
                ReconciliationConflict(
                    code="statement_cashflow",
                    severity="conflict",
                    title="账单缺对应还款现金流",
                    delta=remaining,
                    detail=f"{_cycle_label(cycle)} 未还 {remaining}，但没有关联的还款现金流。",
                    offending=[
                        ConflictPointer(
                            type="credit_statement_cycle",
                            id=cycle.id,
                            label=_cycle_label(cycle),
                        )
                    ],
                    fix="jump_record",
                )
            )
            continue
        if linked.status == "cancelled":
            conflicts.append(
                ReconciliationConflict(
                    code="statement_cashflow",
                    severity="conflict",
                    title="账单关联的还款现金流已取消",
                    delta=remaining,
                    detail=f"{_cycle_label(cycle)} 未还 {remaining}，但关联现金流已取消。",
                    offending=[
                        ConflictPointer(
                            type="cash_flow_item", id=linked.id, label=linked.title
                        )
                    ],
                    fix="jump_record",
                )
            )
            continue
        if quantize_money(linked.amount) != remaining:
            conflicts.append(
                ReconciliationConflict(
                    code="statement_cashflow",
                    severity="conflict",
                    title="账单与还款现金流金额不符",
                    delta=quantize_money(linked.amount - remaining),
                    detail=(
                        f"{_cycle_label(cycle)} 未还 {remaining}，"
                        f"但关联现金流金额 {quantize_money(linked.amount)}。"
                    ),
                    offending=[
                        ConflictPointer(
                            type="credit_statement_cycle",
                            id=cycle.id,
                            label=_cycle_label(cycle),
                        ),
                        ConflictPointer(
                            type="cash_flow_item", id=linked.id, label=linked.title
                        ),
                    ],
                    fix="jump_record",
                )
            )
    return conflicts


def _last_external_actual(db: Session, account_id: str) -> Optional[Decimal]:
    """R3：用户上次录入的真实余额 = 最近一条 reconciliation adjustment 的 balance_after."""
    row = db.execute(
        select(AccountAdjustment)
        .where(
            AccountAdjustment.account_id == account_id,
            AccountAdjustment.source == RECONCILIATION_ADJUSTMENT_SOURCE,
        )
        .order_by(AccountAdjustment.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
    if row is None:
        return None
    return quantize_money(row.balance_after)


def _check_balance_external(
    db: Session, account: Account
) -> Optional[ReconciliationConflict]:
    """R3 账户余额 ↔ 用户录真实余额（外部真相，balance/investment only）.

    The app cannot self-know the bank's real balance; this compares the stored
    balance against the user's last recorded external actual. No prior record →
    an ``info`` prompt to record one. A non-zero gap → a ``conflict`` whose fix
    is ``external_actual`` (record the real number → ``POST /reconciliation/adjustments``).
    """
    stored = quantize_money(account.current_balance)
    external = _last_external_actual(db, account.id)

    if external is None:
        return ReconciliationConflict(
            code="balance_external",
            severity="info",
            title="未录真实余额",
            stored_balance=stored,
            external_actual=None,
            detail="尚未录入真实余额，无法核对。录一次真实余额后即可对平。",
            offending=[
                ConflictPointer(type="account", id=account.id, label=account.name)
            ],
            fix="external_actual",
        )

    delta = quantize_money(stored - external)
    if abs(delta) <= RECONCILIATION_THRESHOLD:
        return None

    return ReconciliationConflict(
        code="balance_external",
        severity="conflict",
        title="账户余额与真实余额不符",
        stored_balance=stored,
        external_actual=external,
        delta=delta,
        detail=f"系统余额 {stored}，上次录入真实余额 {external}（差 {delta}）。",
        offending=[ConflictPointer(type="account", id=account.id, label=account.name)],
        fix="external_actual",
    )


def _check_orphans(db: Session) -> List[ReconciliationConflict]:
    """R4 孤儿/状态一致性（D4 宽，read-only）.

    ① 现金流 status=settled 却无 linked_entry_id；
    ② 报销 status=received 却无 received_entry_id；
    ③ 未还 cycle 无对应还款现金流（与 R2 重叠但全局视角，去重靠前端按 offending id）。
    本检测只读标记，不改任何报销/现金流/周期.
    """
    conflicts: List[ReconciliationConflict] = []

    # ① settled cash flow without a linked entry.
    settled_orphans = db.execute(
        select(CashFlowItem).where(
            CashFlowItem.status == "settled",
            CashFlowItem.linked_entry_id.is_(None),
        )
    ).scalars()
    for item in settled_orphans:
        conflicts.append(
            ReconciliationConflict(
                code="orphan",
                severity="conflict",
                title="已结算现金流缺记账",
                detail=f"现金流「{item.title}」已结算但没有关联的记账分录。",
                offending=[
                    ConflictPointer(
                        type="cash_flow_item", id=item.id, label=item.title
                    )
                ],
                fix="jump_record",
            )
        )

    # ② received reimbursement without a received entry.
    received_orphans = db.execute(
        select(ReimbursementClaim).where(
            ReimbursementClaim.status == "received",
            ReimbursementClaim.received_entry_id.is_(None),
        )
    ).scalars()
    for claim in received_orphans:
        conflicts.append(
            ReconciliationConflict(
                code="orphan",
                severity="conflict",
                title="已到账报销缺到账记账",
                detail=f"报销（{claim.payer} {quantize_money(claim.amount)}）已到账但没有到账分录。",
                offending=[
                    ConflictPointer(
                        type="reimbursement_claim",
                        id=claim.id,
                        label=f"{claim.payer} {quantize_money(claim.amount)}",
                    )
                ],
                fix="jump_record",
            )
        )

    # ③ non-voided cycle with a remaining balance but no linked cash flow.
    cycle_orphans = db.execute(
        select(CreditStatementCycle).where(
            CreditStatementCycle.status != "voided",
            CreditStatementCycle.linked_cash_flow_item_id.is_(None),
        )
    ).scalars()
    for cycle in cycle_orphans:
        remaining = quantize_money(cycle.statement_amount - cycle.paid_amount)
        if remaining <= 0:
            continue
        conflicts.append(
            ReconciliationConflict(
                code="orphan",
                severity="conflict",
                title="未还账单缺还款现金流",
                delta=remaining,
                detail=f"{_cycle_label(cycle)} 未还 {remaining}，但没有关联的还款现金流。",
                offending=[
                    ConflictPointer(
                        type="credit_statement_cycle",
                        id=cycle.id,
                        label=_cycle_label(cycle),
                    )
                ],
                fix="jump_record",
            )
        )

    return conflicts


def _cycle_label(cycle: CreditStatementCycle) -> str:
    remaining = quantize_money(cycle.statement_amount - cycle.paid_amount)
    return (
        f"{cycle.statement_date.isoformat()} 账单 "
        f"{quantize_money(cycle.statement_amount)}（未还 {remaining}）"
    )


# --- R1 信用重算对平 (recompute) -------------------------------------------


def recompute_credit_account(
    db: Session, account_id: str, created_by: str = "system"
) -> CreditRecomputeResponse:
    """重算单个信用账户的 ``current_liability := Σcycle``，差额记 adjustment + audit.

    Reuses the P1 single source of truth (``recompute_credit_liability``). For a
    drifted account it persists the corrected liability and leaves an audit
    trail (``AccountAdjustment(source='liability_recompute')`` +
    ``audit_log(account.liability_recompute)``), mirroring the P1 migration so
    the per-account "重算此账户" button is fully traceable. Non-credit account →
    ``LedgerValidationError`` (400). No-op (no adjustment) when already aligned.
    """
    account = db.get(Account, account_id)
    if account is None:
        raise LedgerNotFoundError("Account not found")
    if account.type != "credit":
        raise LedgerValidationError(
            "Only credit accounts support liability recompute"
        )

    stored_before = quantize_money(account.current_liability)
    recomputed = recompute_credit_liability(db, account)
    delta = quantize_money(recomputed - stored_before)

    adjustment_id: Optional[str] = None
    if abs(delta) > RECONCILIATION_THRESHOLD:
        adjustment = AccountAdjustment(
            account_id=account.id,
            reason="liability recompute",
            delta_amount=delta,
            currency=account.currency,
            balance_before=stored_before,
            balance_after=recomputed,
            source="liability_recompute",
            note="Recomputed current_liability to Σ(non-voided cycle).",
            created_by=created_by,
        )
        db.add(adjustment)
        db.flush()
        adjustment_id = adjustment.id
        db.add(
            AuditLog(
                actor=created_by,
                action_type="account.liability_recompute",
                target_type="account",
                target_id=account.id,
                before_snapshot={
                    "current_liability": str(stored_before),
                    "currency": account.currency,
                },
                after_snapshot={
                    "current_liability": str(recomputed),
                    "delta_amount": str(delta),
                    "currency": account.currency,
                    "adjustment_id": adjustment_id,
                },
                note="Single source of truth recompute (v2.2.0 P2).",
            )
        )

    db.commit()
    db.refresh(account)
    return CreditRecomputeResponse(
        account_id=account.id,
        account_name=account.name,
        stored_liability_before=stored_before,
        recomputed_liability=recomputed,
        delta=delta,
        adjustment_id=adjustment_id,
    )
