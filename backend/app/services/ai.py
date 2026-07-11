import hashlib
import json
from datetime import date as DateType, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Tuple

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.account import Account
from app.models.ai import AIAction, AIActionExecution, AIPlan
from app.models.ai_settings import AISettings
from app.models.audit_log import AuditLog
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.entry import EntryCategoryLine, FinancialEntry
from app.models.installment import InstallmentPlan
from app.models.notification import NotificationRule
from app.schemas.ai import (
    AIActionProposal,
    AIActionRead,
    AIConfigRead,
    AIConfigUpdate,
    AIPlanCreate,
    AIPlanExecute,
    AIPlanRead,
)
from app.schemas.cash_flow import CashFlowItemCreate, CashFlowItemRead
from app.schemas.entry import EntryCreate
from app.schemas.installment import InstallmentPlanCreate
from app.schemas.notification import NotificationRuleCreate, NotificationRuleRead
from app.services import ai_provider, cash_flow, installment, ledger, notification, reimbursement
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money


RISK_ORDER = {"low": 0, "medium": 1, "high": 2}
STRONG_CONFIRM_PHRASE = "EXECUTE_HIGH_RISK"

# v3.1.0 P1 idempotency window. A short (~2 min) window is deliberate: it only
# catches the "same bookkeeping intent fired twice mechanically" case — a
# double-tap, a Siri retry, a Shortcut loop, or `prepareExecution` resubmitting
# after a failed client-side reject (v3.0.0 review 重要-3). It must NOT dedup a
# genuinely repeated purchase hours later ("another coffee, same price") — time
# pulls those apart into distinct plans. Tune here if the hands-free flows change.
IDEMPOTENCY_WINDOW_SECONDS = 120
# ASCII record separator joining the two fingerprint parts so a source_text
# ending in "[" can never collide with the actions-JSON boundary.
_FINGERPRINT_SEPARATOR = "\x1e"
HIGH_RISK_ACTIONS = {"VoidEntry", "DeleteRecord", "ModifyCurrencyRate", "ModifyConfirmedEntry", "BulkUpdate"}
MEDIUM_RISK_ACTIONS = {
    "CreateCashFlowItem",
    "MarkReimbursable",
    "CreateInstallmentPlan",
    "RecordCreditRepayment",
    "GenerateNotificationRule",
    "SetCashFlowStatus",
    "UpdateReimbursementStatus",
}


def _api_key_hint(api_key: Optional[str]) -> Optional[str]:
    """Masked hint for a stored api_key — the last 4 chars only, never the whole
    key. Keys of length <= 4 reveal nothing (real provider keys are far longer)."""
    if not api_key:
        return None
    if len(api_key) <= 4:
        return "..."
    return f"...{api_key[-4:]}"


def get_ai_config(db: Session) -> AIConfigRead:
    settings = get_settings()
    config = ai_provider.resolve_ai_config(db)
    return AIConfigRead(
        provider=config.provider,
        model=config.model,
        base_url=config.base_url,
        base_url_configured=bool(config.base_url),
        api_key_configured=bool(config.api_key),
        api_key_hint=_api_key_hint(config.api_key),
        auto_confirm_limit_cny=settings.ai_auto_confirm_limit_cny,
    )


def update_ai_config(db: Session, payload: AIConfigUpdate) -> AIConfigRead:
    """Upsert the single `ai_settings` row.

    Field-presence semantics (driven by which keys the client actually sent):
    absent -> keep the stored value; empty string / null -> clear to None;
    non-empty value -> set. This lets the client PATCH `model` alone without
    wiping the api_key, and clear the key deliberately by sending "".
    """
    provided = payload.model_dump(exclude_unset=True)
    row = ai_provider._ai_settings_row(db)
    if row is None:
        row = AISettings()
        db.add(row)
    for field in ("base_url", "api_key", "model"):
        if field in provided:
            value = provided[field]
            if isinstance(value, str):
                value = value.strip() or None
            setattr(row, field, value)
    db.commit()
    return get_ai_config(db)


def _ledger_context(db: Session) -> Dict[str, Any]:
    """Account + category lists injected into the AI prompt so the model fills
    real ids. Only active rows; only id/name/type(/currency) — no balances or
    ledger detail leave the server for the third-party LLM."""
    accounts = db.execute(
        select(Account).where(Account.status == "active").order_by(Account.display_order.asc())
    ).scalars().all()
    categories = db.execute(
        select(Category).where(Category.is_active.is_(True)).order_by(Category.display_order.asc())
    ).scalars().all()
    return {
        "accounts": [
            {"id": a.id, "name": a.name, "type": a.type, "currency": a.currency}
            for a in accounts
        ],
        "categories": [
            {"id": c.id, "name": c.name, "type": c.type} for c in categories
        ],
    }


def compute_content_fingerprint(
    source_text: str,
    actions: List[AIActionProposal],
) -> str:
    """Deterministic sha256 (hex, 64 chars) over the REQUEST-ORIGINAL content —
    the client's `source_text` + the actions it sent — NOT the LLM's generated
    output.

    Two reasons for hashing the request rather than the generated actions:
    (1) the LLM is non-deterministic, so hashing its output would miss real
    duplicates; (2) we must be able to dedup BEFORE spending an LLM call.

    Each action contributes only ``{action_type, payload}`` — `explanation` and
    `confidence` don't change what gets posted to the ledger, so they must not
    change the fingerprint. `sort_keys=True` canonicalizes key order recursively
    (a client re-serializing the same payload with keys in a different order
    yields the SAME fingerprint). The pure-text path (no client actions) hashes
    an empty ``[]`` marker.
    """
    canonical_actions = [
        {"action_type": action.action_type, "payload": action.payload}
        for action in actions
    ]
    canonical = (
        source_text.strip()
        + _FINGERPRINT_SEPARATOR
        + json.dumps(
            canonical_actions,
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _find_recent_plan_by_fingerprint(db: Session, fingerprint: str) -> Optional[AIPlan]:
    """Return the most recent plan with the same content fingerprint created
    inside the idempotency window, or None. The cutoff is computed in aware UTC
    (matching how `created_at` is stored — `server_default=func.now()` is UTC on
    both SQLite and Postgres — and mirroring the `attachments.cleanup` cutoff
    idiom); the ~120s fuzziness absorbs any app/DB clock skew."""
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=IDEMPOTENCY_WINDOW_SECONDS)
    return db.execute(
        select(AIPlan)
        .where(
            AIPlan.content_fingerprint == fingerprint,
            AIPlan.created_at >= cutoff,
        )
        .order_by(AIPlan.created_at.desc())
    ).scalars().first()


def create_ai_plan(db: Session, payload: AIPlanCreate) -> Tuple[AIPlanRead, bool]:
    """Create an AI plan, or return an existing same-content plan created inside
    the idempotency window (v3.1.0 P1). Returns ``(plan, created)`` where
    ``created`` is False on a dedup hit so the route can answer 200 vs 201."""
    settings = get_settings()
    config = ai_provider.resolve_ai_config(db)

    # Fingerprint the request-original content and dedup BEFORE any LLM call, so a
    # mechanical resubmit neither mints a second plan nor spends a second LLM
    # request. A hit returns the existing plan verbatim (whatever its status —
    # even executed/rejected): the execute state gate then makes a SEQUENTIAL
    # resubmit (the second `create` arrives after the first has already
    # committed) idempotent end to end, and no second executable plan is ever
    # created for it (the exact root cause of v3.0.0 review 重要-3).
    #
    # This is NOT a concurrency guarantee (v3.1.0 评审 建议-1 — softened from an
    # earlier "idempotent end-to-end" claim that overstated it): the
    # query-then-LLM-then-insert path below is not one atomic transaction, so
    # two requests racing inside the same ~120s window can both miss
    # `_find_recent_plan_by_fingerprint` and each insert their own plan — there
    # is no advisory lock and `content_fingerprint`'s index is deliberately
    # non-unique. Left as-is, not closed: a single user's own retries are
    # effectively sequential (Siri is modal; a double-tap/Back Tap resolves to
    # one shortcut invocation), so the residual window is narrow in practice,
    # and a genuine double write stays recoverable via rollback plus the
    # spoken/notified confirmation every write already surfaces.
    fingerprint = compute_content_fingerprint(payload.source_text, payload.actions)
    existing = _find_recent_plan_by_fingerprint(db, fingerprint)
    if existing is not None:
        return get_ai_plan(db, existing.id), False

    actions = payload.actions
    raw_response = payload.raw_response
    explanation = payload.explanation
    confidence = payload.confidence
    if not actions:
        actions, raw_response, explanation, confidence = ai_provider.generate_action_proposals(
            payload.source_text,
            config,
            _ledger_context(db),
        )

    if not actions:
        raise LedgerValidationError("AI plan must include at least one action")

    assessed = [_assess_action(action, settings.ai_auto_confirm_limit_cny) for action in actions]
    plan_risk = _highest_risk(risk for risk, _ in assessed)
    auto_confirm_eligible = plan_risk == "low"
    status = "auto_confirm_candidate" if auto_confirm_eligible else "requires_confirmation"

    plan = AIPlan(
        source_text=payload.source_text,
        provider=config.provider,
        model=config.model,
        status=status,
        risk_level=plan_risk,
        auto_confirm_eligible=auto_confirm_eligible,
        confidence=Decimal(str(confidence)) if confidence is not None else None,
        explanation=explanation,
        raw_response=raw_response,
        content_fingerprint=fingerprint,
    )
    db.add(plan)
    db.flush()

    for index, (action, (risk_level, requires_confirmation)) in enumerate(zip(actions, assessed)):
        db.add(
            AIAction(
                plan_id=plan.id,
                execution_order=index,
                action_type=action.action_type,
                risk_level=risk_level,
                requires_confirmation=requires_confirmation,
                payload=action.payload,
                explanation=action.explanation,
            )
        )

    db.commit()
    if plan.risk_level == "high" and plan.status == "requires_confirmation":
        try:
            from app.services import push_dispatch

            push_dispatch.dispatch_high_risk_ai_plan(db, plan.id)
        except Exception:
            pass
    return get_ai_plan(db, plan.id), True


def list_ai_plans(
    db: Session,
    status: Optional[str] = None,
    related_type: Optional[str] = None,
    related_to: Optional[str] = None,
) -> List[AIPlanRead]:
    statement = select(AIPlan)
    if status is not None:
        statement = statement.where(AIPlan.status == status)
    if related_to is not None:
        action_statement = select(AIAction.plan_id).where(AIAction.target_id == related_to)
        if related_type is not None:
            action_statement = action_statement.where(AIAction.target_type == related_type)
        statement = statement.where(AIPlan.id.in_(action_statement))
    plans = db.execute(
        statement.order_by(AIPlan.created_at.desc(), AIPlan.updated_at.desc())
    ).scalars()
    return [get_ai_plan(db, plan.id) for plan in plans]


def get_ai_plan(db: Session, plan_id: str) -> AIPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    actions = _load_plan_actions(db, plan.id)
    return AIPlanRead(
        id=plan.id,
        source_text=plan.source_text,
        provider=plan.provider,
        model=plan.model,
        status=plan.status,
        risk_level=plan.risk_level,
        auto_confirm_eligible=plan.auto_confirm_eligible,
        confidence=plan.confidence,
        explanation=plan.explanation,
        raw_response=plan.raw_response,
        actions=[AIActionRead.model_validate(action) for action in actions],
    )


def approve_ai_plan(db: Session, plan_id: str, note: Optional[str] = None) -> AIPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    if plan.status in {"executed", "rejected", "cancelled"}:
        raise LedgerValidationError("Final AI plans cannot be approved")
    plan.status = "approved"
    _write_audit_log(db, "ApproveAIPlan", "ai_plan", plan.id, None, {"status": "approved"}, note)
    db.commit()
    return get_ai_plan(db, plan_id)


def reject_ai_plan(db: Session, plan_id: str, note: Optional[str] = None) -> AIPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    if plan.status in {"executed", "rejected", "cancelled"}:
        raise LedgerValidationError("Final AI plans cannot be rejected")
    plan.status = "rejected"
    for action in _load_plan_actions(db, plan.id):
        if action.status == "pending":
            action.status = "skipped"
    _write_audit_log(db, "RejectAIPlan", "ai_plan", plan.id, None, {"status": "rejected"}, note)
    db.commit()
    return get_ai_plan(db, plan_id)


def execute_ai_plan(db: Session, plan_id: str, payload: AIPlanExecute) -> AIPlanRead:
    plan = _get_plan_or_raise(db, plan_id)
    _ensure_plan_can_execute(plan, payload)

    try:
        for action in _load_plan_actions(db, plan.id):
            if action.status != "pending":
                continue
            _execute_action(db, action)
        plan.status = "executed"
        db.commit()
    except (LedgerValidationError, LedgerNotFoundError, ValidationError) as exc:
        db.rollback()
        plan = _get_plan_or_raise(db, plan_id)
        plan.status = "failed"
        db.commit()
        raise LedgerValidationError(str(exc)) from exc

    return get_ai_plan(db, plan_id)


def rollback_ai_action(db: Session, action_id: str) -> AIActionRead:
    action = _get_action_or_raise(db, action_id)
    if action.status != "executed":
        raise LedgerValidationError("Only executed AI actions can be rolled back")
    if action.action_type == "VoidEntry":
        raise LedgerValidationError("VoidEntry rollback is not supported")

    before, after = _rollback_action_target(db, action)
    action.status = "rolled_back"
    action.result = {"rolled_back": True}
    db.add(
        AIActionExecution(
            action_id=action.id,
            status="rolled_back",
            target_type=action.target_type,
            target_id=action.target_id,
            before_snapshot=before,
            after_snapshot=after,
            rollback_snapshot=after,
        )
    )
    _write_audit_log(
        db,
        "RollbackAIAction",
        action.target_type or "ai_action",
        action.target_id or action.id,
        before,
        after,
        f"Rolled back AI action {action.action_type}",
    )
    db.commit()
    return AIActionRead.model_validate(action)


def _execute_action(db: Session, action: AIAction) -> None:
    before: Optional[Dict[str, Any]] = None
    try:
        target_type, target_id, after, rollback_payload, before = _apply_action(db, action)
    except Exception as exc:
        action.status = "failed"
        action.error_message = str(exc)
        db.add(
            AIActionExecution(
                action_id=action.id,
                status="failed",
                error_message=str(exc),
            )
        )
        raise

    action.status = "executed"
    action.target_type = target_type
    action.target_id = target_id
    action.result = {"target_type": target_type, "target_id": target_id}
    action.rollback_payload = rollback_payload
    db.add(
        AIActionExecution(
            action_id=action.id,
            status="executed",
            target_type=target_type,
            target_id=target_id,
            before_snapshot=before,
            after_snapshot=after,
        )
    )
    _write_audit_log(
        db,
        "AIActionExecution",
        target_type,
        target_id,
        before,
        after,
        f"Executed AI action {action.action_type}",
    )


def _apply_action(
    db: Session,
    action: AIAction,
) -> Tuple[str, str, Dict[str, Any], Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    if action.action_type == "CreateEntry":
        entry_payload = EntryCreate.model_validate(action.payload).model_copy(
            update={"created_by": "ai"}
        )
        entry = ledger.create_entry(db, entry_payload, commit=False)
        after = entry.model_dump(mode="json")
        rollback_payload = {"action_type": "VoidEntry", "entry_id": entry.id}
        return "financial_entry", entry.id, after, rollback_payload, None

    if action.action_type == "CreateCashFlowItem":
        item = cash_flow.create_cash_flow_item(
            db,
            CashFlowItemCreate.model_validate(action.payload),
            commit=False,
        )
        after = item.model_dump(mode="json")
        rollback_payload = {"action_type": "CancelCashFlowItem", "cash_flow_item_id": item.id}
        return "cash_flow_item", item.id, after, rollback_payload, None

    if action.action_type == "CreateInstallmentPlan":
        plan = installment.create_installment_plan(
            db,
            InstallmentPlanCreate.model_validate(action.payload),
            commit=False,
        )
        after = plan.model_dump(mode="json")
        rollback_payload = {"action_type": "CancelInstallmentPlan", "installment_plan_id": plan.id}
        return "installment_plan", plan.id, after, rollback_payload, None

    if action.action_type == "GenerateNotificationRule":
        rule = notification.create_notification_rule(
            db,
            NotificationRuleCreate.model_validate(action.payload),
            commit=False,
        )
        after = rule.model_dump(mode="json")
        rollback_payload = {"action_type": "CancelNotificationRule", "notification_rule_id": rule.id}
        return "notification_rule", rule.id, after, rollback_payload, None

    if action.action_type == "RecordCreditRepayment":
        entry_payload = EntryCreate.model_validate(action.payload.get("entry", action.payload))
        if not any(
            movement.movement_type == "credit_repayment"
            for movement in entry_payload.account_movements
        ):
            raise LedgerValidationError("RecordCreditRepayment requires a credit_repayment movement")
        entry = ledger.create_entry(
            db,
            entry_payload.model_copy(update={"created_by": "ai", "status": "confirmed"}),
            commit=False,
        )
        after = entry.model_dump(mode="json")
        rollback_payload = {"action_type": "VoidEntry", "entry_id": entry.id}
        return "financial_entry", entry.id, after, rollback_payload, None

    if action.action_type == "MarkReimbursable":
        return _mark_reimbursable(db, action.payload)

    if action.action_type == "SetCashFlowStatus":
        return _set_cash_flow_status(db, action.payload)

    if action.action_type == "UpdateReimbursementStatus":
        return _update_reimbursement_status(db, action.payload)

    if action.action_type == "VoidEntry":
        entry_id = action.payload.get("entry_id")
        if not entry_id:
            raise LedgerValidationError("VoidEntry requires entry_id")
        before = ledger.get_entry(db, entry_id).model_dump(mode="json")
        entry = ledger.void_entry(db, entry_id, commit=False)
        after = entry.model_dump(mode="json")
        return "financial_entry", entry.id, after, None, before

    raise LedgerValidationError(f"Unsupported AI action type: {action.action_type}")


def _mark_reimbursable(
    db: Session,
    payload: Dict[str, Any],
) -> Tuple[str, str, Dict[str, Any], Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    line_id = payload.get("entry_line_id")
    if not line_id:
        raise LedgerValidationError("MarkReimbursable requires entry_line_id")
    line = db.get(EntryCategoryLine, line_id)
    if line is None:
        raise LedgerNotFoundError("Entry category line not found")
    entry = db.get(FinancialEntry, line.entry_id)
    if entry is None:
        raise LedgerNotFoundError("Entry not found")

    before = _entry_line_snapshot(line)
    line.reimbursable_flag = True
    line.reimbursement_payer = payload.get("payer") or payload.get("reimbursement_payer") or "company"
    expected_date = payload.get("expected_date") or payload.get("reimbursement_expected_date")
    if isinstance(expected_date, str):
        expected_date = DateType.fromisoformat(expected_date)
    line.reimbursement_expected_date = expected_date
    line.reimbursement_status = payload.get("status") or payload.get("reimbursement_status")
    if line.reimbursement_expected_date is None:
        raise LedgerValidationError("MarkReimbursable requires expected_date")
    reimbursement.create_claims_for_entry(db, entry, [line])
    after = _entry_line_snapshot(line)
    rollback_payload = {"action_type": "ClearReimbursable", "entry_line_id": line.id}
    return "entry_category_line", line.id, after, rollback_payload, before


def _set_cash_flow_status(
    db: Session,
    payload: Dict[str, Any],
) -> Tuple[str, str, Dict[str, Any], Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    item_id = payload.get("cash_flow_item_id") or payload.get("item_id")
    target_status = payload.get("status") or payload.get("target_status")
    if not item_id or not target_status:
        raise LedgerValidationError("SetCashFlowStatus requires cash_flow_item_id and status")
    item = db.get(CashFlowItem, item_id)
    if item is None:
        raise LedgerNotFoundError("Cash flow item not found")
    before = CashFlowItemRead.model_validate(item).model_dump(mode="json")
    updated = cash_flow.set_cash_flow_status(db, item_id, target_status, commit=False)
    after = updated.model_dump(mode="json")
    rollback_payload = {
        "action_type": "SetCashFlowStatus",
        "cash_flow_item_id": item_id,
        "status": before["status"],
    }
    return "cash_flow_item", item_id, after, rollback_payload, before


def _update_reimbursement_status(
    db: Session,
    payload: Dict[str, Any],
) -> Tuple[str, str, Dict[str, Any], Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    claim_id = payload.get("reimbursement_claim_id") or payload.get("claim_id")
    target_status = payload.get("status") or payload.get("target_status")
    if not claim_id or not target_status:
        raise LedgerValidationError("UpdateReimbursementStatus requires reimbursement_claim_id and status")
    before = reimbursement.get_reimbursement_claim(db, claim_id).model_dump(mode="json")
    updated = reimbursement.update_claim_status(db, claim_id, target_status, commit=False)
    after = updated.model_dump(mode="json")
    rollback_payload = {
        "action_type": "UpdateReimbursementStatus",
        "reimbursement_claim_id": claim_id,
        "status": before["status"],
    }
    return "reimbursement_claim", claim_id, after, rollback_payload, before


def _rollback_action_target(
    db: Session,
    action: AIAction,
) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    if action.target_type == "financial_entry" and action.target_id is not None:
        before = ledger.get_entry(db, action.target_id).model_dump(mode="json")
        after = ledger.void_entry(db, action.target_id, commit=False).model_dump(mode="json")
        return before, after

    if action.target_type == "cash_flow_item" and action.target_id is not None:
        item = db.get(CashFlowItem, action.target_id)
        if item is None:
            raise LedgerNotFoundError("Cash flow item not found")
        before = CashFlowItemRead.model_validate(item).model_dump(mode="json")
        rollback_status = (action.rollback_payload or {}).get("status")
        if rollback_status is not None:
            if item.status == "settled":
                raise LedgerValidationError("Settled cash flow items cannot be rolled back")
            if rollback_status not in {"expected", "confirmed", "cancelled"}:
                raise LedgerValidationError("Unsupported cash flow rollback status")
            item.status = rollback_status
        elif item.status not in {"settled", "cancelled"}:
            item.status = "cancelled"
        after = CashFlowItemRead.model_validate(item).model_dump(mode="json")
        return before, after

    if action.target_type == "reimbursement_claim" and action.target_id is not None:
        before = reimbursement.get_reimbursement_claim(db, action.target_id).model_dump(mode="json")
        rollback_status = (action.rollback_payload or {}).get("status")
        if rollback_status is None:
            raise LedgerValidationError("Reimbursement status rollback payload is missing")
        updated = reimbursement.update_claim_status(
            db,
            action.target_id,
            rollback_status,
            commit=False,
            allow_final_source=True,
        )
        after = updated.model_dump(mode="json")
        return before, after

    if action.target_type == "notification_rule" and action.target_id is not None:
        rule = db.get(NotificationRule, action.target_id)
        if rule is None:
            raise LedgerNotFoundError("Notification rule not found")
        before = NotificationRuleRead.model_validate(rule).model_dump(mode="json")
        rule.status = "cancelled"
        after = NotificationRuleRead.model_validate(rule).model_dump(mode="json")
        return before, after

    if action.target_type == "installment_plan" and action.target_id is not None:
        plan = db.get(InstallmentPlan, action.target_id)
        if plan is None:
            raise LedgerNotFoundError("Installment plan not found")
        before = {"id": plan.id, "status": plan.status}
        if plan.status == "active":
            installment.cancel_installment_plan(db, plan.id)
        after = {"id": plan.id, "status": plan.status}
        return before, after

    raise LedgerValidationError("AI action target cannot be rolled back")


def _assess_action(action: AIActionProposal, auto_confirm_limit_cny: Decimal) -> Tuple[str, bool]:
    action_type = action.action_type
    incomplete = _validate_known_payload(action)
    if action_type in HIGH_RISK_ACTIONS:
        return "high", True
    if action_type in MEDIUM_RISK_ACTIONS:
        return "medium", True
    if action_type == "CreateEntry":
        # An id-incomplete proposal must NEVER be an auto-confirm candidate —
        # it cannot execute (EntryCreate re-validates strictly in
        # `_apply_action`); it exists to be completed by a human in the
        # review UI, so force the requires-confirmation lane regardless of
        # amount (v3.1.x 快修: the LLM legitimately leaves account_id blank
        # when it can't map the receipt to a listed account).
        if incomplete:
            return "medium", True
        amount_cny = _entry_amount_cny(action.payload)
        if amount_cny is not None and amount_cny <= auto_confirm_limit_cny:
            return "low", False
        return "medium", True
    return "high", True


def _only_missing_ids(exc: ValidationError) -> bool:
    """True when EVERY validation error is a plain `missing` on an
    `account_id` / `category_id` field — the one shape of invalidity the
    system prompt explicitly tells the LLM to produce ("no fitting item →
    leave the id blank and explain"). Anything else (bad amounts, wrong
    types, missing title …) stays a hard create-time 400."""
    errors = exc.errors()
    if not errors:
        return False
    return all(
        error.get("type") == "missing"
        and error.get("loc")
        and error["loc"][-1] in ("account_id", "category_id")
        for error in errors
    )


def _validate_known_payload(action: AIActionProposal) -> bool:
    """Validate an action payload at PROPOSAL time. Returns True when the
    payload is structurally sound but id-INCOMPLETE (missing account_id /
    category_id only) — such proposals are storable (the P4 review UI owns
    letting the user fill the blanks; execute re-validates strictly in
    `_apply_action`), they just must not auto-execute (see `_assess_action`).

    v3.1.x 快修背景（真机实测 2026-07-11）：旧版对 CreateEntry 直接严格
    `EntryCreate.model_validate`，LLM 按 prompt 指示留空 account_id 的合法提案
    在「存提案」这步就被 400 拒收，确认页根本无从补起。"""
    try:
        if action.action_type == "CreateEntry":
            try:
                EntryCreate.model_validate(action.payload)
            except ValidationError as entry_exc:
                if _only_missing_ids(entry_exc):
                    return True
                raise
        elif action.action_type == "CreateCashFlowItem":
            CashFlowItemCreate.model_validate(action.payload)
        elif action.action_type == "CreateInstallmentPlan":
            InstallmentPlanCreate.model_validate(action.payload)
        elif action.action_type == "GenerateNotificationRule":
            NotificationRuleCreate.model_validate(action.payload)
        elif action.action_type == "RecordCreditRepayment":
            try:
                EntryCreate.model_validate(action.payload.get("entry", action.payload))
            except ValidationError as entry_exc:
                if _only_missing_ids(entry_exc):
                    return True
                raise
        elif action.action_type == "VoidEntry" and "entry_id" not in action.payload:
            raise LedgerValidationError("VoidEntry requires entry_id")
        elif action.action_type == "MarkReimbursable" and "entry_line_id" not in action.payload:
            raise LedgerValidationError("MarkReimbursable requires entry_line_id")
        elif action.action_type == "SetCashFlowStatus":
            if not (action.payload.get("cash_flow_item_id") or action.payload.get("item_id")):
                raise LedgerValidationError("SetCashFlowStatus requires cash_flow_item_id")
            if not (action.payload.get("status") or action.payload.get("target_status")):
                raise LedgerValidationError("SetCashFlowStatus requires status")
        elif action.action_type == "UpdateReimbursementStatus":
            if not (
                action.payload.get("reimbursement_claim_id")
                or action.payload.get("claim_id")
            ):
                raise LedgerValidationError("UpdateReimbursementStatus requires reimbursement_claim_id")
            if not (action.payload.get("status") or action.payload.get("target_status")):
                raise LedgerValidationError("UpdateReimbursementStatus requires status")
    except ValidationError as exc:
        raise LedgerValidationError(str(exc)) from exc
    return False


def _entry_amount_cny(payload: Dict[str, Any]) -> Optional[Decimal]:
    amounts = []
    for group_name in ("category_lines", "account_movements"):
        for item in payload.get(group_name, []):
            amount = item.get("converted_cny_amount")
            if amount is not None:
                amounts.append(Decimal(str(amount)))
                continue
            if item.get("currency", "").upper() == "CNY" and item.get("amount") is not None:
                amounts.append(Decimal(str(item["amount"])))
    if not amounts:
        return None
    return quantize_money(max(amounts))


def _ensure_plan_can_execute(plan: AIPlan, payload: AIPlanExecute) -> None:
    if plan.status == "executed":
        raise LedgerValidationError("AI plan has already been executed")
    if plan.status in {"rejected", "cancelled", "failed"}:
        raise LedgerValidationError("Final AI plans cannot be executed")
    if plan.status == "approved":
        allowed = True
    elif plan.status == "auto_confirm_candidate" and plan.auto_confirm_eligible:
        allowed = True
    else:
        allowed = False
    if not allowed:
        raise LedgerValidationError("AI plan requires approval before execution")
    if plan.risk_level == "high" and payload.strong_confirm != STRONG_CONFIRM_PHRASE:
        raise LedgerValidationError("High-risk AI plans require strong confirmation")


def _highest_risk(risks: Iterable[str]) -> str:
    return max(risks, key=lambda risk: RISK_ORDER[risk])


def _get_plan_or_raise(db: Session, plan_id: str) -> AIPlan:
    plan = db.get(AIPlan, plan_id)
    if plan is None:
        raise LedgerNotFoundError("AI plan not found")
    return plan


def _get_action_or_raise(db: Session, action_id: str) -> AIAction:
    action = db.get(AIAction, action_id)
    if action is None:
        raise LedgerNotFoundError("AI action not found")
    return action


def _load_plan_actions(db: Session, plan_id: str) -> List[AIAction]:
    return list(
        db.execute(
            select(AIAction)
            .where(AIAction.plan_id == plan_id)
            .order_by(AIAction.execution_order.asc(), AIAction.created_at.asc())
        ).scalars()
    )


def _entry_line_snapshot(line: EntryCategoryLine) -> Dict[str, Any]:
    return {
        "id": line.id,
        "entry_id": line.entry_id,
        "reimbursable_flag": line.reimbursable_flag,
        "reimbursement_payer": line.reimbursement_payer,
        "reimbursement_expected_date": (
            line.reimbursement_expected_date.isoformat()
            if line.reimbursement_expected_date is not None
            else None
        ),
        "reimbursement_status": line.reimbursement_status,
    }


def _write_audit_log(
    db: Session,
    action_type: str,
    target_type: str,
    target_id: str,
    before_snapshot: Optional[Dict[str, Any]],
    after_snapshot: Optional[Dict[str, Any]],
    note: Optional[str],
) -> None:
    db.add(
        AuditLog(
            actor="ai",
            action_type=action_type,
            target_type=target_type,
            target_id=target_id,
            before_snapshot=before_snapshot,
            after_snapshot=after_snapshot,
            note=note,
        )
    )
