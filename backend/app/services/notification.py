from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.notification import NotificationRule
from app.schemas.notification import NotificationRuleCreate, NotificationRuleRead
from app.services.ledger import LedgerNotFoundError, LedgerValidationError


def create_notification_rule(
    db: Session,
    payload: NotificationRuleCreate,
    commit: bool = True,
) -> NotificationRuleRead:
    rule = NotificationRule(
        title=payload.title,
        rule_type=payload.rule_type,
        channel=payload.channel,
        trigger_payload=payload.trigger_payload,
        status=payload.status,
        next_trigger_date=payload.next_trigger_date,
        note=payload.note,
    )
    db.add(rule)
    if commit:
        db.commit()
        db.refresh(rule)
    else:
        db.flush()
    return NotificationRuleRead.model_validate(rule)


def list_notification_rules(
    db: Session,
    status: Optional[str] = None,
    rule_type: Optional[str] = None,
) -> List[NotificationRuleRead]:
    statement = select(NotificationRule)
    if status is not None:
        statement = statement.where(NotificationRule.status == status)
    if rule_type is not None:
        statement = statement.where(NotificationRule.rule_type == rule_type)
    rules = db.execute(
        statement.order_by(NotificationRule.next_trigger_date.asc(), NotificationRule.created_at.desc())
    ).scalars()
    return [NotificationRuleRead.model_validate(rule) for rule in rules]


def get_notification_rule(db: Session, rule_id: str) -> NotificationRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    return NotificationRuleRead.model_validate(rule)


def pause_notification_rule(db: Session, rule_id: str) -> NotificationRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status == "cancelled":
        raise LedgerValidationError("Cancelled notification rules cannot be paused")
    rule.status = "paused"
    db.commit()
    return get_notification_rule(db, rule_id)


def resume_notification_rule(db: Session, rule_id: str) -> NotificationRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status == "cancelled":
        raise LedgerValidationError("Cancelled notification rules cannot be resumed")
    rule.status = "active"
    db.commit()
    return get_notification_rule(db, rule_id)


def cancel_notification_rule(db: Session, rule_id: str) -> NotificationRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    rule.status = "cancelled"
    db.commit()
    return get_notification_rule(db, rule_id)


def _get_rule_or_raise(db: Session, rule_id: str) -> NotificationRule:
    rule = db.get(NotificationRule, rule_id)
    if rule is None:
        raise LedgerNotFoundError("Notification rule not found")
    return rule
