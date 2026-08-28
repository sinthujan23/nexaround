import uuid
from datetime import datetime
from pydantic import BaseModel


class ExcludedKeywordResponse(BaseModel):
    id: uuid.UUID
    keyword: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ExcludedKeywordCreate(BaseModel):
    keyword: str
