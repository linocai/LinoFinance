from typing import List

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.account import Account
from app.models.cash_flow import CashFlowItem
from app.models.category import Category
from app.models.subscription import SubscriptionRule
from app.schemas.subscription import SubscriptionRuleCreate, SubscriptionRuleRead
from app.services import ledger
from app.services.ledger import LedgerNotFoundError, LedgerValidationError, quantize_money
from app.services.schedule import next_subscription_date


def create_subscription_rule(db: Session, payload: SubscriptionRuleCreate) -> SubscriptionRuleRead:
    currency = payload.currency.upper()
    _validate_links(db, payload.account_id, payload.category_id, currency)
    next_charge_date = payload.next_charge_date or payload.start_date
    if payload.end_date is not None and next_charge_date > payload.end_date:
        raise LedgerValidationError("Next charge date cannot be after subscription end date")

    rule = SubscriptionRule(
        title=payload.title,
        amount=quantize_money(payload.amount),
        currency=currency,
        account_id=payload.account_id,
        category_id=payload.category_id,
        billing_interval=payload.billing_interval,
        billing_day=payload.billing_day,
        start_date=payload.start_date,
        end_date=payload.end_date,
        next_charge_date=next_charge_date,
        status=payload.status,
        note=payload.note,
    )
    db.add(rule)
    db.flush()
    if rule.status == "active":
        _generate_next_cash_flow(db, rule)
    db.commit()
    db.refresh(rule)
    return _read_rule(db, rule)


def list_subscription_rules(db: Session) -> List[SubscriptionRuleRead]:
    rules = db.execute(
        select(SubscriptionRule).order_by(SubscriptionRule.next_charge_date.asc(), SubscriptionRule.created_at.asc())
    ).scalars()
    return [_read_rule(db, rule) for rule in rules]


def get_subscription_rule(db: Session, rule_id: str) -> SubscriptionRuleRead:
    rule = db.get(SubscriptionRule, rule_id)
    if rule is None:
        raise LedgerNotFoundError("Subscription rule not found")
    return _read_rule(db, rule)


def pause_subscription_rule(db: Session, rule_id: str) -> SubscriptionRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status == "cancelled":
        raise LedgerValidationError("Cancelled subscription rules cannot be paused")
    rule.status = "paused"
    db.commit()
    return get_subscription_rule(db, rule_id)


def resume_subscription_rule(db: Session, rule_id: str) -> SubscriptionRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status == "cancelled":
        raise LedgerValidationError("Cancelled subscription rules cannot be resumed")
    rule.status = "active"
    _generate_next_cash_flow(db, rule)
    db.commit()
    return get_subscription_rule(db, rule_id)


def cancel_subscription_rule(db: Session, rule_id: str) -> SubscriptionRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    rule.status = "cancelled"
    _cancel_open_cash_flows(db, rule.id)
    db.commit()
    return get_subscription_rule(db, rule_id)


def generate_next_subscription_cash_flow(db: Session, rule_id: str) -> SubscriptionRuleRead:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status != "active":
        raise LedgerValidationError("Only active subscriptions can generate cash flow")
    _generate_next_cash_flow(db, rule)
    db.commit()
    return get_subscription_rule(db, rule_id)


def advance_subscription_after_settlement(db: Session, rule_id: str) -> None:
    rule = _get_rule_or_raise(db, rule_id)
    if rule.status != "active":
        return
    rule.next_charge_date = next_subscription_date(
        rule.next_charge_date,
        rule.billing_interval,
        rule.billing_day,
    )
    _generate_next_cash_flow(db, rule)


def _generate_next_cash_flow(db: Session, rule: SubscriptionRule) -> None:
    if rule.end_date is not None and rule.next_charge_date > rule.end_date:
        return

    existing = db.execute(
        select(CashFlowItem).where(
            CashFlowItem.linked_subscription_rule_id == rule.id,
            CashFlowItem.expected_date == rule.next_charge_date,
            CashFlowItem.status.in_(["expected", "confirmed"]),
        )
    ).scalar_one_or_none()
    if existing is not None:
        return

    converted_cny_amount, exchange_rate_id = ledger.convert_to_cny(
        db,
        rule.amount,
        rule.currency,
        rule.next_charge_date,
    )
    item = CashFlowItem(
        title=rule.title,
        direction="outflow",
        cash_flow_type="subscription",
        amount=rule.amount,
        currency=rule.currency,
        exchange_rate_id=exchange_rate_id,
        converted_cny_amount=converted_cny_amount,
        expected_date=rule.next_charge_date,
        account_id=rule.account_id,
        category_id=rule.category_id,
        status="expected",
        linked_subscription_rule_id=rule.id,
        note="Generated from subscription rule.",
    )
    db.add(item)


def _cancel_open_cash_flows(db: Session, rule_id: str) -> None:
    items = db.execute(
        select(CashFlowItem).where(CashFlowItem.linked_subscription_rule_id == rule_id)
    ).scalars()
    for item in items:
        if item.status in {"expected", "confirmed"}:
            item.status = "cancelled"


def _read_rule(db: Session, rule: SubscriptionRule) -> SubscriptionRuleRead:
    count = db.execute(
        select(func.count(CashFlowItem.id)).where(CashFlowItem.linked_subscription_rule_id == rule.id)
    ).scalar_one()
    return SubscriptionRuleRead(
        id=rule.id,
        title=rule.title,
        amount=rule.amount,
        currency=rule.currency,
        account_id=rule.account_id,
        category_id=rule.category_id,
        billing_interval=rule.billing_interval,
        billing_day=rule.billing_day,
        start_date=rule.start_date,
        end_date=rule.end_date,
        next_charge_date=rule.next_charge_date,
        status=rule.status,
        generated_cash_flow_count=count,
        note=rule.note,
    )


def _validate_links(db: Session, account_id: str, category_id: str, currency: str) -> None:
    if account_id is not None:
        account = db.get(Account, account_id)
        if account is None:
            raise LedgerValidationError("Subscription account not found")
        if account.currency != currency:
            raise LedgerValidationError("Subscription currency must match account currency")
    if category_id is not None and db.get(Category, category_id) is None:
        raise LedgerValidationError("Subscription category not found")


def _get_rule_or_raise(db: Session, rule_id: str) -> SubscriptionRule:
    rule = db.get(SubscriptionRule, rule_id)
    if rule is None:
        raise LedgerNotFoundError("Subscription rule not found")
    return rule
