import uuid
from typing import Optional
from pydantic import BaseModel


class CategoryResponse(BaseModel):
    id: uuid.UUID
    name: str
    icon: Optional[str] = None
    color: Optional[str] = None
    sort_order: int = 0
    is_active: bool = True

    model_config = {"from_attributes": True}


class CategoryCreate(BaseModel):
    name: str
    icon: Optional[str] = None
    color: Optional[str] = None
    sort_order: int = 0
