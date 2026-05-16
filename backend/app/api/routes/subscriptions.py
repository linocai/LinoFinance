from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.subscription import SubscriptionRuleCreate, SubscriptionRuleRead
from app.services import subscription
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[SubscriptionRuleRead])
def list_subscription_rules(db: Session = Depends(get_db)) -> List[SubscriptionRuleRead]:
    return subscription.list_subscription_rules(db)


@router.post("", response_model=SubscriptionRuleRead, status_code=status.HTTP_201_CREATED)
def create_subscription_rule(
    payload: SubscriptionRuleCreate,
    db: Session = Depends(get_db),
) -> SubscriptionRuleRead:
    try:
        return subscription.create_subscription_rule(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/{rule_id}", response_model=SubscriptionRuleRead)
def get_subscription_rule(rule_id: str, db: Session = Depends(get_db)) -> SubscriptionRuleRead:
    try:
        return subscription.get_subscription_rule(db, rule_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{rule_id}/pause", response_model=SubscriptionRuleRead)
def pause_subscription_rule(rule_id: str, db: Session = Depends(get_db)) -> SubscriptionRuleRead:
    return _mutate_rule(db, subscription.pause_subscription_rule, rule_id)


@router.post("/{rule_id}/resume", response_model=SubscriptionRuleRead)
def resume_subscription_rule(rule_id: str, db: Session = Depends(get_db)) -> SubscriptionRuleRead:
    return _mutate_rule(db, subscription.resume_subscription_rule, rule_id)


@router.post("/{rule_id}/cancel", response_model=SubscriptionRuleRead)
def cancel_subscription_rule(rule_id: str, db: Session = Depends(get_db)) -> SubscriptionRuleRead:
    return _mutate_rule(db, subscription.cancel_subscription_rule, rule_id)


@router.post("/{rule_id}/generate-next", response_model=SubscriptionRuleRead)
def generate_next_subscription_cash_flow(
    rule_id: str,
    db: Session = Depends(get_db),
) -> SubscriptionRuleRead:
    return _mutate_rule(db, subscription.generate_next_subscription_cash_flow, rule_id)


def _mutate_rule(db: Session, operation, rule_id: str) -> SubscriptionRuleRead:
    try:
        return operation(db, rule_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

