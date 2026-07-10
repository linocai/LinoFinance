from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.ai import (
    AIConfigRead,
    AIConfigUpdate,
    AIPlanApprove,
    AIPlanCreate,
    AIPlanExecute,
    AIPlanRead,
    AIPlanReject,
    AIActionRead,
)
from app.services import ai
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("/config", response_model=AIConfigRead)
def get_ai_config(db: Session = Depends(get_db)) -> AIConfigRead:
    return ai.get_ai_config(db)


@router.put("/config", response_model=AIConfigRead)
def update_ai_config(
    payload: AIConfigUpdate,
    db: Session = Depends(get_db),
) -> AIConfigRead:
    try:
        return ai.update_ai_config(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/plans", response_model=List[AIPlanRead])
def list_ai_plans(
    status_filter: Optional[str] = Query(default=None, alias="status"),
    related_type: Optional[str] = Query(default=None),
    related_to: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
) -> List[AIPlanRead]:
    return ai.list_ai_plans(db, status_filter, related_type, related_to)


@router.post("/plans", response_model=AIPlanRead, status_code=status.HTTP_201_CREATED)
def create_ai_plan(payload: AIPlanCreate, db: Session = Depends(get_db)) -> AIPlanRead:
    try:
        return ai.create_ai_plan(db, payload)
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.get("/plans/{plan_id}", response_model=AIPlanRead)
def get_ai_plan(plan_id: str, db: Session = Depends(get_db)) -> AIPlanRead:
    try:
        return ai.get_ai_plan(db, plan_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.post("/plans/{plan_id}/approve", response_model=AIPlanRead)
def approve_ai_plan(
    plan_id: str,
    payload: AIPlanApprove,
    db: Session = Depends(get_db),
) -> AIPlanRead:
    try:
        return ai.approve_ai_plan(db, plan_id, payload.note)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/plans/{plan_id}/reject", response_model=AIPlanRead)
def reject_ai_plan(
    plan_id: str,
    payload: AIPlanReject,
    db: Session = Depends(get_db),
) -> AIPlanRead:
    try:
        return ai.reject_ai_plan(db, plan_id, payload.note)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/plans/{plan_id}/execute", response_model=AIPlanRead)
def execute_ai_plan(
    plan_id: str,
    payload: AIPlanExecute,
    db: Session = Depends(get_db),
) -> AIPlanRead:
    try:
        return ai.execute_ai_plan(db, plan_id, payload)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/actions/{action_id}/rollback", response_model=AIActionRead)
def rollback_ai_action(action_id: str, db: Session = Depends(get_db)) -> AIActionRead:
    try:
        return ai.rollback_ai_action(db, action_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
