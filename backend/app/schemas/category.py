from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    parent_id: Optional[str] = None
    type: str = Field(pattern="^(expense|income|transfer|system)$")
    is_active: bool = True
    display_order: int = 0


class CategoryUpdate(BaseModel):
    """Patch a subset of editable category fields (audit 2.5).

    Immutable fields (``type`` / ``parent_id``) are intentionally absent;
    unknown fields are rejected so attempts to mutate them fail loudly.
    """

    model_config = ConfigDict(extra="forbid")

    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    is_active: Optional[bool] = None
    display_order: Optional[int] = None


class CategoryRead(BaseModel):
    id: str
    name: str
    parent_id: Optional[str] = None
    type: str
    is_active: bool
    display_order: int

    model_config = ConfigDict(from_attributes=True)

