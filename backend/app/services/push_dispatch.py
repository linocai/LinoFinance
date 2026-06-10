import base64
import json
import time
from dataclasses import dataclass, field
from datetime import date as DateType, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any, Optional

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.timeutils import app_today
from app.models.account import Account
from app.models.ai import AIPlan
from app.models.audit_log import AuditLog
from app.models.credit_statement_cycle import CreditStatementCycle
from app.models.notification import NotificationRule
from app.models.push import PushDevice
from app.models.reimbursement import ReimbursementClaim
from app.services import push


APNS_SANDBOX_HOST = "https://api.sandbox.push.apple.com"
APNS_PRODUCTION_HOST = "https://api.push.apple.com"
CREDIT_REMINDER_DAYS = {5, 3, 1, 0}


@dataclass
class PushEvent:
    event_type: str
    rule_type: str
    title: str
    body: str
    target_type: str
    target_id: str
    payload: dict[str, Any] = field(default_factory=dict)


@dataclass
class PushDispatchResult:
    event_type: str
    matched_rules: int = 0
    device_count: int = 0
    sent: int = 0
    failed: int = 0
    dry_run: bool = False
    skipped_reason: Optional[str] = None
    payloads: list[dict[str, Any]] = field(default_factory=list)


def dispatch_event(db: Session, event: PushEvent) -> PushDispatchResult:
    settings = get_settings()
    result = PushDispatchResult(event_type=event.event_type, dry_run=settings.apns_dry_run)
    rules = _matching_rules(db, event)
    result.matched_rules = len(rules)
    if not rules:
        result.skipped_reason = "no_matching_notification_rule"
        return result

    devices = push.enabled_devices(db)
    result.device_count = len(devices)
    if not devices:
        result.skipped_reason = "no_enabled_push_device"
        return result

    payload = _apns_payload(event)
    for device in devices:
        try:
            _send_device(device, payload, settings)
            result.sent += 1
            result.payloads.append(payload)
        except Exception as exc:  # APNs failures should not block finance workflows.
            result.failed += 1
            result.payloads.append({"error": str(exc), "payload": payload})

    if result.sent > 0:
        now = datetime.now(timezone.utc)
        for rule in rules:
            rule.last_triggered_at = now
        db.commit()
    return result


def dispatch_credit_statement_generated(db: Session, cycle_id: str) -> PushDispatchResult:
    cycle = db.get(CreditStatementCycle, cycle_id)
    if cycle is None:
        return PushDispatchResult(event_type="credit_statement_generated", skipped_reason="cycle_not_found")
    account = db.get(Account, cycle.credit_account_id)
    account_name = account.name if account is not None else "信用账户"
    remaining = _money(cycle.statement_amount - cycle.paid_amount, cycle.currency)
    event = PushEvent(
        event_type="credit_statement_generated",
        rule_type="credit_repayment",
        title="信用账单已生成",
        body=f"{account_name} 待还 {remaining}，到期 {cycle.due_date.isoformat()}",
        target_type="credit_statement_cycle",
        target_id=cycle.id,
        payload={
            "cycle_id": cycle.id,
            "credit_account_id": cycle.credit_account_id,
            "account_name": account_name,
            "due_date": cycle.due_date.isoformat(),
            "remaining_amount": str(cycle.statement_amount - cycle.paid_amount),
            "currency": cycle.currency,
        },
    )
    return dispatch_event(db, event)


def dispatch_reimbursement_status(
    db: Session,
    claim_id: str,
    claim_status: str,
) -> PushDispatchResult:
    claim = db.get(ReimbursementClaim, claim_id)
    if claim is None:
        return PushDispatchResult(event_type="reimbursement_status", skipped_reason="claim_not_found")
    if claim_status == "approved":
        title = "报销已批准"
        body = f"{claim.payer} 已批准 {_money(claim.amount, claim.currency)}，等待到账"
    elif claim_status == "received":
        title = "报销已到账"
        body = f"{claim.payer} 报销 {_money(claim.amount, claim.currency)} 已到账"
    else:
        return PushDispatchResult(event_type="reimbursement_status", skipped_reason="unsupported_status")
    event = PushEvent(
        event_type=f"reimbursement_{claim_status}",
        rule_type="reimbursement",
        title=title,
        body=body,
        target_type="reimbursement_claim",
        target_id=claim.id,
        payload={
            "claim_id": claim.id,
            "payer": claim.payer,
            "status": claim_status,
            "amount": str(claim.amount),
            "currency": claim.currency,
        },
    )
    return dispatch_event(db, event)


def dispatch_high_risk_ai_plan(db: Session, plan_id: str) -> PushDispatchResult:
    plan = db.get(AIPlan, plan_id)
    if plan is None:
        return PushDispatchResult(event_type="ai_plan_requires_confirmation", skipped_reason="plan_not_found")
    if plan.risk_level != "high" or plan.status != "requires_confirmation":
        return PushDispatchResult(event_type="ai_plan_requires_confirmation", skipped_reason="not_high_risk")
    event = PushEvent(
        event_type="ai_plan_requires_confirmation",
        rule_type="ai_plan",
        title="高风险 AI 计划待确认",
        body=plan.source_text[:160],
        target_type="ai_plan",
        target_id=plan.id,
        payload={"plan_id": plan.id, "risk_level": plan.risk_level, "status": plan.status},
    )
    return dispatch_event(db, event)


def dispatch_due_credit_reminders(
    db: Session,
    anchor_date: Optional[DateType] = None,
) -> list[PushDispatchResult]:
    anchor = anchor_date or app_today()
    target_dates = {anchor + timedelta(days=days) for days in CREDIT_REMINDER_DAYS}
    statement = (
        select(CreditStatementCycle, Account)
        .join(Account, CreditStatementCycle.credit_account_id == Account.id)
        .where(
            CreditStatementCycle.due_date.in_(target_dates),
            CreditStatementCycle.status.not_in(["paid", "closed", "voided"]),
            CreditStatementCycle.statement_amount > CreditStatementCycle.paid_amount,
        )
    )
    results: list[PushDispatchResult] = []
    for cycle, account in db.execute(statement):
        days = (cycle.due_date - anchor).days
        if days not in CREDIT_REMINDER_DAYS:
            continue
        action_type = f"push.credit_due.t_minus_{days}"
        if _audit_exists(db, action_type, "credit_statement_cycle", cycle.id):
            results.append(PushDispatchResult(event_type=action_type, skipped_reason="already_sent"))
            continue
        remaining = _money(cycle.statement_amount - cycle.paid_amount, cycle.currency)
        label = "今天" if days == 0 else f"{days} 天后"
        event = PushEvent(
            event_type=action_type,
            rule_type="credit_repayment",
            title=f"{account.name} 还款提醒",
            body=f"{label}到期，待还 {remaining}",
            target_type="credit_statement_cycle",
            target_id=cycle.id,
            payload={
                "cycle_id": cycle.id,
                "credit_account_id": cycle.credit_account_id,
                "account_name": account.name,
                "due_date": cycle.due_date.isoformat(),
                "days_until_due": days,
                "remaining_amount": str(cycle.statement_amount - cycle.paid_amount),
                "currency": cycle.currency,
            },
        )
        result = dispatch_event(db, event)
        if result.sent > 0:
            db.add(
                AuditLog(
                    actor="system",
                    action_type=action_type,
                    target_type="credit_statement_cycle",
                    target_id=cycle.id,
                    before_snapshot=None,
                    after_snapshot={"sent": result.sent, "dry_run": result.dry_run},
                    note="APNs credit due reminder",
                )
            )
            db.commit()
        results.append(result)
    return results


def _matching_rules(db: Session, event: PushEvent) -> list[NotificationRule]:
    rules = db.execute(
        select(NotificationRule).where(
            NotificationRule.status == "active",
            NotificationRule.rule_type == event.rule_type,
            NotificationRule.channel == "system",
        )
    ).scalars()
    return [rule for rule in rules if _rule_payload_matches(rule.trigger_payload or {}, event.payload)]


def _rule_payload_matches(rule_payload: dict[str, Any], event_payload: dict[str, Any]) -> bool:
    for key, expected in rule_payload.items():
        if str(event_payload.get(key)) != str(expected):
            return False
    return True


def _apns_payload(event: PushEvent) -> dict[str, Any]:
    deep_link = f"linofinance://{event.target_type}/{event.target_id}"
    return {
        "aps": {
            "alert": {"title": event.title, "body": event.body},
            "sound": "default",
            "thread-id": event.rule_type,
            "interruption-level": "active",
        },
        "event_type": event.event_type,
        "target_type": event.target_type,
        "target_id": event.target_id,
        "deep_link": deep_link,
        "payload": event.payload,
    }


def _send_device(device: PushDevice, payload: dict[str, Any], settings) -> None:
    if settings.apns_dry_run:
        return
    if not all([settings.apns_topic, settings.apns_key_id, settings.apns_team_id, settings.apns_key_path]):
        raise RuntimeError("APNs is not configured")
    token = _apns_jwt(settings)
    host = APNS_SANDBOX_HOST if settings.apns_use_sandbox else APNS_PRODUCTION_HOST
    response = httpx.post(
        f"{host}/3/device/{device.apns_token}",
        json=payload,
        headers={
            "authorization": f"bearer {token}",
            "apns-topic": settings.apns_topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
        },
        timeout=10,
    )
    if response.status_code >= 300:
        raise RuntimeError(f"APNs {response.status_code}: {response.text}")


def _apns_jwt(settings) -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    header = {"alg": "ES256", "kid": settings.apns_key_id}
    claims = {"iss": settings.apns_team_id, "iat": int(time.time())}
    signing_input = b".".join(
        [
            _base64url(json.dumps(header, separators=(",", ":")).encode()),
            _base64url(json.dumps(claims, separators=(",", ":")).encode()),
        ]
    )
    private_key = serialization.load_pem_private_key(
        Path(settings.apns_key_path).expanduser().read_bytes(),
        password=None,
    )
    signature_der = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r_value, s_value = utils.decode_dss_signature(signature_der)
    signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
    return b".".join([signing_input, _base64url(signature)]).decode()


def _base64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def _audit_exists(db: Session, action_type: str, target_type: str, target_id: str) -> bool:
    return db.execute(
        select(AuditLog.id).where(
            AuditLog.action_type == action_type,
            AuditLog.target_type == target_type,
            AuditLog.target_id == target_id,
        )
    ).first() is not None


def _money(amount: Decimal, currency: str) -> str:
    return f"{currency} {amount:.2f}"
