from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class SearchHit(BaseModel):
    type: str
    id: str
    title: str
    subtitle: Optional[str] = None
    relevance: float = Field(ge=0)
    target: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class SearchResponse(BaseModel):
    query: str
    limit: int
    items: List[SearchHit]
