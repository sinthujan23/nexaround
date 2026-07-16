from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime


# ── Masterpiece ──────────────────────────────────────────────────────────────

class MasterpieceOut(BaseModel):
    """A single must-see item returned to the client."""
    id: UUID
    rank: int
    building: str
    room_gallery: str
    must_see_item: str
    artist: Optional[str] = None
    category: str
    description: Optional[str] = None
    included_5h: bool = False
    included_1d: bool = False
    included_2d: bool = False

    class Config:
        from_attributes = True


# ── Museum ───────────────────────────────────────────────────────────────────

class MuseumListItem(BaseModel):
    """Lightweight museum card for the list page."""
    id: UUID
    slug: str
    name: str
    city: str
    country: str
    annual_visitors: Optional[int] = None
    rank: Optional[int] = None
    image_url: Optional[str] = None
    masterpiece_count: int = 0

    class Config:
        from_attributes = True


class MuseumDetail(BaseModel):
    """Full museum detail including all masterpieces."""
    id: UUID
    slug: str
    name: str
    city: str
    country: str
    annual_visitors: Optional[int] = None
    rank: Optional[int] = None
    image_url: Optional[str] = None
    ticket_url: Optional[str] = None
    website: Optional[str] = None
    opening_hours: Optional[str] = None
    closing_hours: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    masterpieces: List[MasterpieceOut] = []

    class Config:
        from_attributes = True


class MuseumItinerary(BaseModel):
    """Filtered itinerary for a specific duration."""
    museum_name: str
    museum_slug: str
    duration: str  # "5h", "1d", "2d"
    total_items: int
    buildings: List["BuildingSection"]

    class Config:
        from_attributes = True


class BuildingSection(BaseModel):
    """A group of masterpieces in the same building."""
    building: str
    items: List[MasterpieceOut]
