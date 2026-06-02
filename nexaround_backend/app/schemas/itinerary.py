from pydantic import BaseModel, ConfigDict
from typing import List, Optional
from uuid import UUID
from datetime import datetime, date

class ItineraryItem(BaseModel):
    # `extra="allow"` + optional attraction_id lets a single Itinerary row hold
    # either a classic saved-attraction item (with attraction_id) OR a free-form
    # AI "Odyssey" block (a meta header or a day's activities) whose shape the
    # backend never needs to understand — it's stored verbatim in the JSON
    # `items` column and round-tripped to the app. Keeps the existing itinerary
    # flow working with zero DB migration.
    model_config = ConfigDict(extra="allow")

    attraction_id: Optional[UUID] = None
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

class OdysseyGenerateRequest(BaseModel):
    """Request body for kicking off a server-side AI Odyssey generation."""
    destination: str
    mood: str = "Adventurous"
    budget: float = 50000
    days: int = 3
    currency: str = "LKR"

class ItineraryResponse(ItineraryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    class Config:
        from_attributes = True
