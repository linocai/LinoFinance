from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.audit_log import AuditLog
from app.schemas.audit_log import AuditLogRead

router = APIRouter()


@router.get("", response_model=List[AuditLogRead])
def list_audit_logs(
    target_type: Optional[str] = None,
    target_id: Optional[str] = None,
    limit: Optional[int] = Query(default=None, ge=1, le=100),
    db: Session = Depends(get_db),
) -> List[AuditLogRead]:
    statement = select(AuditLog)
    if target_type is not None:
        statement = statement.where(AuditLog.target_type == target_type)
    if target_id is not None:
        statement = statement.where(AuditLog.target_id == target_id)
    statement = statement.order_by(AuditLog.created_at.desc())
    if limit is not None:
        statement = statement.limit(limit)
    logs = db.execute(statement).scalars()
    return [AuditLogRead.model_validate(log) for log in logs]
