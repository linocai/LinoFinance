from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.notification import NotificationRuleCreate, NotificationRuleRead
from app.services import notification
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=List[NotificationRuleRead])
def list_notification_rules(
    status_filter: Optional[str] = Query(default=None, alias="status"),
    rule_type: Optional[str] = None,
    db: Session = Depends(get_db),
) -> List[NotificationRuleRead]:
    return notification.list_notification_rules(db, status=status_filter, rule_type=rule_type)


@router.post("", response_model=NotificationRuleRead, status_code=status.HTTP_201_CREATED)
def create_notification_rule(
    payload: NotificationRuleCreate,
    db: Session = Depends(get_db),
) -> NotificationRuleRead:
    return notification.create_notification_rule(db, payload)


@router.get("/{rule_id}", response_model=NotificationRuleRead)
def get_notification_rule(rule_id: str, db: Session = Depends(get_db)) -> NotificationRuleRead:
    try:
        return notification.get_notification_rule(db, rule_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/{rule_id}/pause", response_model=NotificationRuleRead)
def pause_notification_rule(rule_id: str, db: Session = Depends(get_db)) -> NotificationRuleRead:
    return _mutate_rule(db, notification.pause_notification_rule, rule_id)


@router.post("/{rule_id}/resume", response_model=NotificationRuleRead)
def resume_notification_rule(rule_id: str, db: Session = Depends(get_db)) -> NotificationRuleRead:
    return _mutate_rule(db, notification.resume_notification_rule, rule_id)


@router.post("/{rule_id}/cancel", response_model=NotificationRuleRead)
def cancel_notification_rule(rule_id: str, db: Session = Depends(get_db)) -> NotificationRuleRead:
    return _mutate_rule(db, notification.cancel_notification_rule, rule_id)


def _mutate_rule(db: Session, operation, rule_id: str) -> NotificationRuleRead:
    try:
        return operation(db, rule_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
