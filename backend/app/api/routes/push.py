from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.push import PushDeviceCreate, PushDeviceRead
from app.services import push
from app.services.ledger import LedgerNotFoundError

router = APIRouter()


@router.post("/devices", response_model=PushDeviceRead, status_code=status.HTTP_201_CREATED)
def register_device(payload: PushDeviceCreate, db: Session = Depends(get_db)) -> PushDeviceRead:
    return push.register_device(db, payload)


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def disable_device(device_id: str, db: Session = Depends(get_db)) -> None:
    try:
        push.disable_device(db, device_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
