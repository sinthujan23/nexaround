from pydantic import BaseModel, Field
from typing import List, Optional
from uuid import UUID
from datetime import datetime, date

class ItineraryItem(BaseModel):
    attraction_id: UUID
    time: Optional[str] = None
    note: Optional[str] = None

class ItineraryBase(BaseModel):
    title: str
    trip_date: Optional[date] = None
    items: List[ItineraryItem] = []
    status: str = "draft"

class ItineraryCreate(ItineraryBase):
    pass

class ItineraryUpdate(BaseModel):
    title: Optional[str] = None
    trip_date: Optional[date] = None
    items: Optional[List[ItineraryItem]] = None
    status: Optional[str] = None

class ItineraryResponse(ItineraryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    class Config:
        from_attributes = True
