from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class DiscoveryHistoryBase(BaseModel):
    location: str
    mode: str
    result: str


class DiscoveryHistoryCreate(DiscoveryHistoryBase):
    pass


class DiscoveryHistoryResponse(DiscoveryHistoryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    class Config:
        from_attributes = True
