from datetime import date as DateType
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Tuple

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.ai import AIAction, AIActionExecution, AIPlan
from app.models.audit_log import AuditLog
from app.models.cash_flow import CashFlowItem
from app.models.entry import EntryCategoryLine, FinancialEntry
from app.models.installment import InstallmentPlan
from app.models.notification import NotificationRule
from app.schemas.ai import (
    AIActionProposal,
    AIActionRead,
    AIConfigRead,
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
HIGH_RISK_ACTIONS = {"VoidEntry", "DeleteRecord", "ModifyCurrencyRate", "ModifyConfirmedEntry", "BulkUpdate"}
MEDIUM_RISK_ACTIONS = {
    "CreateCashFlowItem",
    "MarkReimbursable",
    "CreateInstallmentPlan",
    "RecordCreditRepayment",
    "GenerateNotificationRule",
}


def get_ai_config() -> AIConfigRead:
    settings = get_settings()
    return AIConfigRead(
        provider=settings.ai_provider,
        model=settings.ai_model,
        base_url_configured=bool(settings.ai_api_base_url),
        api_key_configured=bool(settings.ai_api_key),
        auto_confirm_limit_cny=settings.ai_auto_confirm_limit_cny,
    )


def create_ai_plan(db: Session, payload: AIPlanCreate) -> AIPlanRead:
    settings = get_settings()
    actions = payload.actions
    raw_response = payload.raw_response
    explanation = payload.explanation
    confidence = payload.confidence
    if not actions:
        actions, raw_response, explanation, confidence = ai_provider.generate_action_proposals(
            payload.source_text
        )

    if not actions:
        raise LedgerValidationError("AI plan must include at least one action")

    assessed = [_assess_action(action, settings.ai_auto_confirm_limit_cny) for action in actions]
    plan_risk = _highest_risk(risk for risk, _ in assessed)
    auto_confirm_eligible = plan_risk == "low"
    status = "auto_confirm_candidate" if auto_confirm_eligible else "requires_confirmation"

    plan = AIPlan(
        source_text=payload.source_text,
        provider=settings.ai_provider,
        model=settings.ai_model,
        status=status,
        risk_level=plan_risk,
        auto_confirm_eligible=auto_confirm_eligible,
        confidence=Decimal(str(confidence)) if confidence is not None else None,
        explanation=explanation,
        raw_response=raw_response,
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
    return get_ai_plan(db, plan.id)


def list_ai_plans(db: Session, status: Optional[str] = None) -> List[AIPlanRead]:
    statement = select(AIPlan)
    if status is not None:
        statement = statement.where(AIPlan.status == status)
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
        if item.status not in {"settled", "cancelled"}:
            item.status = "cancelled"
        after = CashFlowItemRead.model_validate(item).model_dump(mode="json")
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
    _validate_known_payload(action)
    if action_type in HIGH_RISK_ACTIONS:
        return "high", True
    if action_type in MEDIUM_RISK_ACTIONS:
        return "medium", True
    if action_type == "CreateEntry":
        amount_cny = _entry_amount_cny(action.payload)
        if amount_cny is not None and amount_cny <= auto_confirm_limit_cny:
            return "low", False
        return "medium", True
    return "high", True


def _validate_known_payload(action: AIActionProposal) -> None:
    try:
        if action.action_type == "CreateEntry":
            EntryCreate.model_validate(action.payload)
        elif action.action_type == "CreateCashFlowItem":
            CashFlowItemCreate.model_validate(action.payload)
        elif action.action_type == "CreateInstallmentPlan":
            InstallmentPlanCreate.model_validate(action.payload)
        elif action.action_type == "GenerateNotificationRule":
            NotificationRuleCreate.model_validate(action.payload)
        elif action.action_type == "RecordCreditRepayment":
            EntryCreate.model_validate(action.payload.get("entry", action.payload))
        elif action.action_type == "VoidEntry" and "entry_id" not in action.payload:
            raise LedgerValidationError("VoidEntry requires entry_id")
        elif action.action_type == "MarkReimbursable" and "entry_line_id" not in action.payload:
            raise LedgerValidationError("MarkReimbursable requires entry_line_id")
    except ValidationError as exc:
        raise LedgerValidationError(str(exc)) from exc


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
