from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.search import SearchResponse
from app.services import search as search_service

router = APIRouter()


@router.get("", response_model=SearchResponse)
def search(
    q: str = Query(min_length=1),
    limit: Optional[int] = Query(default=None, ge=1),
    types: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
) -> SearchResponse:
    selected_types = types.split(",") if types else None
    return search_service.search(db, q, limit, selected_types)
