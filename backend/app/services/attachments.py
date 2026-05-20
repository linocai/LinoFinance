from datetime import datetime, timedelta, timezone
from hashlib import sha256
from pathlib import Path
from re import sub
from typing import Optional
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.attachment import Attachment
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

OWNER_TYPES = {"entry_category_line", "reimbursement_claim", "ai_action"}


def create_attachment(
    db: Session,
    *,
    owner_type: str,
    owner_id: str,
    filename: str,
    content_type: Optional[str],
    data: bytes,
    uploaded_by: Optional[str] = None,
    note: Optional[str] = None,
) -> Attachment:
    if owner_type not in OWNER_TYPES:
        raise LedgerValidationError("Unsupported attachment owner type")

    settings = get_settings()
    size_bytes = len(data)
    if size_bytes <= 0:
        raise LedgerValidationError("Attachment file is empty")
    if size_bytes > settings.attachment_file_max_bytes:
        raise LedgerValidationError("Attachment file exceeds max file size")
    if owner_type == "reimbursement_claim":
        existing_bytes = _active_owner_attachment_bytes(db, owner_type, owner_id)
        if existing_bytes + size_bytes > settings.attachment_max_bytes:
            raise LedgerValidationError("Reimbursement attachments exceed max total size")

    safe_filename = _safe_filename(filename)
    checksum = sha256(data).hexdigest()
    storage_key = f"{owner_type}/{owner_id}/{uuid4()}-{safe_filename}"
    storage_path = _storage_path(storage_key)
    storage_path.parent.mkdir(parents=True, exist_ok=True)
    storage_path.write_bytes(data)

    attachment = Attachment(
        owner_type=owner_type,
        owner_id=owner_id,
        filename=safe_filename,
        content_type=content_type or "application/octet-stream",
        size_bytes=size_bytes,
        storage_key=storage_key,
        checksum_sha256=checksum,
        uploaded_by=uploaded_by,
        note=note,
    )
    db.add(attachment)
    db.commit()
    db.refresh(attachment)
    return attachment


def get_attachment(db: Session, attachment_id: str) -> Attachment:
    attachment = db.get(Attachment, attachment_id)
    if attachment is None or attachment.deleted_at is not None:
        raise LedgerNotFoundError("Attachment not found")
    return attachment


def list_attachments(db: Session, owner_type: str, owner_id: str) -> list[Attachment]:
    if owner_type not in OWNER_TYPES:
        raise LedgerValidationError("Unsupported attachment owner type")
    return list(
        db.execute(
            select(Attachment)
            .where(
                Attachment.owner_type == owner_type,
                Attachment.owner_id == owner_id,
                Attachment.deleted_at.is_(None),
            )
            .order_by(Attachment.created_at.desc())
        ).scalars()
    )


def attachment_path(attachment: Attachment) -> Path:
    path = _storage_path(attachment.storage_key)
    if not path.exists():
        raise LedgerNotFoundError("Attachment file not found")
    return path


def delete_attachment(db: Session, attachment_id: str) -> None:
    attachment = get_attachment(db, attachment_id)
    attachment.deleted_at = datetime.now(timezone.utc)
    db.commit()


def cleanup_deleted_attachments(db: Session, retention_days: int = 30) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    rows = db.execute(
        select(Attachment).where(
            Attachment.deleted_at.is_not(None),
            Attachment.deleted_at <= cutoff,
        )
    ).scalars()
    removed = 0
    for attachment in rows:
        path = _storage_path(attachment.storage_key)
        if path.exists():
            path.unlink()
            removed += 1
    return removed


def _active_owner_attachment_bytes(db: Session, owner_type: str, owner_id: str) -> int:
    total = db.execute(
        select(func.coalesce(func.sum(Attachment.size_bytes), 0)).where(
            Attachment.owner_type == owner_type,
            Attachment.owner_id == owner_id,
            Attachment.deleted_at.is_(None),
        )
    ).scalar_one()
    return int(total or 0)


def _storage_path(storage_key: str) -> Path:
    root = Path(get_settings().storage_root).expanduser()
    return root / storage_key


def _safe_filename(filename: str) -> str:
    normalized = sub(r"[^A-Za-z0-9._-]+", "-", Path(filename).name).strip(".-")
    return normalized or "attachment"
