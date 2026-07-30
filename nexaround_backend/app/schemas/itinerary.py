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
    currency: str = "USD"
    travelers: int = 1
    include_flights: bool = False
    departure_city: str = ""
    departure_country: str = ""
    flight_start_date: Optional[str] = None
    flight_end_date: Optional[str] = None
    include_hotels: bool = False
    hotel_check_in_date: Optional[str] = None
    hotel_check_out_date: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None

class OdysseySwapRequest(BaseModel):
    """Request body for swapping a single activity in a saved Odyssey for an
    AI-suggested alternative. `day_index` and `activity_index` are zero-based
    positions within the plan (day position, then activity within that day)."""
    day_index: int
    activity_index: int
    reason: str = ""

class OdysseyPartnerSwapRequest(BaseModel):
    """Request body for swapping a single booking partner in a saved Odyssey."""
    partner_name: str
    reason: str = ""

class ItineraryResponse(ItineraryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    class Config:
        from_attributes = True
