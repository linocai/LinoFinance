from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.attachment import AttachmentRead
from app.services import attachments
from app.services.ledger import LedgerNotFoundError, LedgerValidationError

router = APIRouter()


@router.get("", response_model=list[AttachmentRead])
def list_attachments(
    owner_type: str = Query(),
    owner_id: str = Query(),
    db: Session = Depends(get_db),
) -> list[AttachmentRead]:
    try:
        return attachments.list_attachments(db, owner_type=owner_type, owner_id=owner_id)
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("", response_model=AttachmentRead, status_code=status.HTTP_201_CREATED)
async def upload_attachment(
    owner_type: str = Form(),
    owner_id: str = Form(),
    uploaded_by: Optional[str] = Form(default=None),
    note: Optional[str] = Form(default=None),
    file: UploadFile = File(),
    db: Session = Depends(get_db),
) -> AttachmentRead:
    data = await file.read()
    try:
        return attachments.create_attachment(
            db,
            owner_type=owner_type,
            owner_id=owner_id,
            filename=file.filename or "attachment",
            content_type=file.content_type,
            data=data,
            uploaded_by=uploaded_by,
            note=note,
        )
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except LedgerValidationError as exc:
        status_code = status.HTTP_413_CONTENT_TOO_LARGE if "exceeds" in str(exc) else 400
        raise HTTPException(status_code=status_code, detail=str(exc)) from exc


@router.get("/{attachment_id}")
def download_attachment(attachment_id: str, db: Session = Depends(get_db)) -> FileResponse:
    try:
        attachment = attachments.get_attachment(db, attachment_id)
        path = attachments.attachment_path(attachment)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    return FileResponse(
        path,
        media_type=attachment.content_type,
        filename=attachment.filename,
    )


@router.delete("/{attachment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_attachment(attachment_id: str, db: Session = Depends(get_db)) -> None:
    try:
        attachments.delete_attachment(db, attachment_id)
    except LedgerNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
