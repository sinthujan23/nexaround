from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
from uuid import UUID
from datetime import datetime


# ── Masterpiece ──────────────────────────────────────────────────────────────

class MasterpieceOut(BaseModel):
    """A single must-see item returned to the client."""
    id: UUID
    rank: int
    stop: Optional[int] = None
    """Position within the requested itinerary.

    `rank` is a single sequence across every tour, so a shorter tour reads
    1, 2, 3, 9, 11, 53 — gaps that look like missing stops. This is the number
    the spreadsheet gives for the tour actually being shown.
    """
    building: str
    room_gallery: str
    must_see_item: str
    artist: Optional[str] = None
    category: str
    description: Optional[str] = None
    included_3h: bool = False
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
    # Shown on the guide page's chips (the app falls back to its own list).
    website: Optional[str] = None
    opening_hours: Optional[str] = None

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


# ── Admin panel (museums_admin) ──────────────────────────────────────────────
# What data entry types, in the shape the app shows: the museum's card and
# guide header, then each must-see item and the tours (3h / 5h / 1d / 2d) it
# is part of, with its stop number in each.

DURATIONS = ("3h", "5h", "1d", "2d")


def _text(value):
    """Trimmed, with inner runs of spaces kept as typed; "" for None."""
    return (value or "").strip()


def _optional_text(value):
    value = (value or "").strip()
    return value or None


class MuseumAdminCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    city: str = Field(..., min_length=1, max_length=120)
    country: str = Field(..., min_length=1, max_length=120)

    _trim = field_validator("name", "city", "country", mode="before")(_text)


class MuseumItemIn(BaseModel):
    """One must-see item. `id` is set for an item that already exists."""
    id: Optional[UUID] = None
    building: str = Field(..., min_length=1, max_length=255)
    room_gallery: str = Field(..., min_length=1, max_length=255)
    must_see_item: str = Field(..., min_length=1, max_length=255)
    artist: Optional[str] = Field(None, max_length=255)
    category: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = Field(None, max_length=4000)
    included_3h: bool = False
    included_5h: bool = False
    included_1d: bool = False
    included_2d: bool = False
    # Stop number in each tour it is part of; renumbered 1..n on save.
    stop_3h: Optional[int] = Field(None, ge=1)
    stop_5h: Optional[int] = Field(None, ge=1)
    stop_1d: Optional[int] = Field(None, ge=1)
    stop_2d: Optional[int] = Field(None, ge=1)

    _trim = field_validator("building", "room_gallery", "must_see_item", "category", mode="before")(_text)
    _optional = field_validator("artist", "description", mode="before")(_optional_text)


class MuseumAdminSave(BaseModel):
    """The whole museum as the editor holds it. `items` is in the order of
    the museum's full list (its rank); each tour's order is its stop numbers."""
    name: str = Field(..., min_length=1, max_length=255)
    city: str = Field(..., min_length=1, max_length=120)
    country: str = Field(..., min_length=1, max_length=120)
    annual_visitors: Optional[int] = Field(None, ge=0)
    rank: Optional[int] = Field(None, ge=1)
    # The guide page's hours chip, one short line: "9am–6pm (Closed Tue)".
    opening_hours: Optional[str] = Field(None, max_length=200)
    website: Optional[str] = Field(None, max_length=512)
    items: List[MuseumItemIn] = Field(default_factory=list, max_length=400)

    _trim = field_validator("name", "city", "country", mode="before")(_text)
    _optional = field_validator("opening_hours", "website", mode="before")(_optional_text)

    @field_validator("website")
    @classmethod
    def _web_address(cls, value):
        if value and not value.lower().startswith(("http://", "https://")):
            raise ValueError("The website must start with https://")
        return value


class MuseumVisibilityIn(BaseModel):
    hidden: bool


class MuseumItemOut(MuseumItemIn):
    id: UUID
    rank: int

    class Config:
        from_attributes = True


class MuseumAdminListItem(BaseModel):
    id: UUID
    slug: str
    name: str
    city: str
    country: str
    annual_visitors: Optional[int] = None
    rank: Optional[int] = None
    image_url: Optional[str] = None
    item_count: int = 0
    tours: List[str] = []  # the tours with at least one item, e.g. ["5h", "1d"]
    is_hidden: bool = False


class MuseumAdminDetail(BaseModel):
    id: UUID
    slug: str
    name: str
    city: str
    country: str
    annual_visitors: Optional[int] = None
    rank: Optional[int] = None
    image_url: Optional[str] = None
    opening_hours: Optional[str] = None
    website: Optional[str] = None
    is_hidden: bool = False
    items: List[MuseumItemOut] = []
    # Every category used in any museum, most used first, to pick from.
    categories: List[str] = []
