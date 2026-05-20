from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.push import PushDevice
from app.schemas.push import PushDeviceCreate
from app.services.ledger import LedgerNotFoundError


def register_device(db: Session, payload: PushDeviceCreate) -> PushDevice:
    existing = db.execute(
        select(PushDevice).where(
            PushDevice.platform == payload.platform,
            PushDevice.apns_token == payload.apns_token,
        )
    ).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if existing is not None:
        existing.device_id = payload.device_id
        existing.app_version = payload.app_version
        existing.last_seen_at = now
        existing.enabled = True
        db.commit()
        db.refresh(existing)
        return existing

    device = PushDevice(
        device_id=payload.device_id,
        platform=payload.platform,
        apns_token=payload.apns_token,
        app_version=payload.app_version,
        last_seen_at=now,
        enabled=True,
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


def disable_device(db: Session, device_id: str) -> None:
    device = db.get(PushDevice, device_id)
    if device is None:
        raise LedgerNotFoundError("Push device not found")
    device.enabled = False
    device.last_seen_at = datetime.now(timezone.utc)
    db.commit()
