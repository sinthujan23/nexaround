from typing import Optional
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


class DiscoveryGenerateRequest(BaseModel):
    location: str
    mode: str
    latitude: float
    longitude: float
    companions: str
    weather: str
    time_available: str
    mood: str
    time_of_day: str
    budget: Optional[str] = None

