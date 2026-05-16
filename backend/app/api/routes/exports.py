from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.report import ExportDatasetList
from app.services import export
from app.services.ledger import LedgerValidationError

router = APIRouter()


@router.get("/csv", response_model=ExportDatasetList)
def list_csv_exports() -> ExportDatasetList:
    return export.list_export_datasets()


@router.get("/csv/{dataset}")
def export_csv_dataset(dataset: str, db: Session = Depends(get_db)) -> Response:
    try:
        content = export.export_dataset_csv(db, dataset)
        filename = export.csv_filename(dataset)
    except LedgerValidationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return Response(
        content=content,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
