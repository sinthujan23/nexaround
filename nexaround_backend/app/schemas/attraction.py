import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class AttractionBase(BaseModel):
    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    history: Optional[str] = None
    latitude: float
    longitude: float
    address: Optional[str] = None
    opening_hours: dict = {}
    entry_fee: float = 0.0
    currency: str = "USD"
    tags: list[str] = []
    geofence_radius_m: int = 100


class AttractionResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    history: Optional[str] = None
    latitude: float
    longitude: float
    category_id: Optional[uuid.UUID] = None
    category_name: Optional[str] = None
    address: Optional[str] = None
    opening_hours: dict = {}
    entry_fee: float = 0.0
    currency: str = "USD"
    rating: float = 0.0
    review_count: int = 0
    photo_urls: list[str] = []
    tags: list[str] = []
    geofence_radius_m: int = 100
    distance_m: Optional[float] = None  # Populated by proximity queries
    is_active: bool = True
    created_at: datetime
    has_duplicate_coordinates: bool = False

    model_config = {"from_attributes": True}


class AttractionListResponse(BaseModel):
    attractions: list[AttractionResponse]
    total: int
    page: int = 1
    page_size: int = 20


class NearbyRequest(BaseModel):
    latitude: float
    longitude: float
    radius_m: float = 1000.0  # Default 1 km radius
    category_id: Optional[uuid.UUID] = None
    limit: int = 50
    sort: str = "proximity"  # proximity | away


# --- Suggestions from the app --------------------------------------------

class AttractionSuggest(BaseModel):
    """A place an app user proposes. It waits in the admin Review queue."""
    model_config = {"extra": "forbid"}

    name: str = Field(..., min_length=2, max_length=255)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    category_id: Optional[uuid.UUID] = None
    address: Optional[str] = Field(None, max_length=500)
    description: Optional[str] = Field(None, max_length=4000)


# --- Admin: Map Database ---------------------------------------------------

class AdminPlace(BaseModel):
    """A place as the admin panel sees it, lifecycle fields included."""
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    history: Optional[str] = None
    latitude: float
    longitude: float
    category_id: Optional[uuid.UUID] = None
    category_name: Optional[str] = None
    address: Optional[str] = None
    opening_hours: dict = {}
    entry_fee: float = 0.0
    currency: str = "USD"
    rating: float = 0.0
    review_count: int = 0
    photo_urls: list[str] = []
    tags: list[str] = []
    geofence_radius_m: int = 100
    google_place_id: Optional[str] = None
    status: str
    status_reason: Optional[str] = None
    status_note: Optional[str] = None
    source: str
    submitted_by_user_id: Optional[uuid.UUID] = None
    reviewed_at: Optional[datetime] = None
    reviewed_by: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    has_duplicate_coordinates: bool = False
    distance_m: Optional[float] = None


class PlaceStatusCounts(BaseModel):
    live: int = 0
    pending: int = 0
    hidden: int = 0
    rejected: int = 0


class AdminPlaceList(BaseModel):
    items: list[AdminPlace]
    total: int
    page: int
    page_size: int
    counts: PlaceStatusCounts


class PlaceCountsResponse(PlaceStatusCounts):
    pending_user: int = 0


class PlaceUsage(BaseModel):
    reviews: int = 0
    media: int = 0
    visits: int = 0


class PlaceSubmitter(BaseModel):
    id: uuid.UUID
    display_name: str
    email: str


class AdminPlaceDetail(AdminPlace):
    usage: PlaceUsage
    submitter: Optional[PlaceSubmitter] = None


class AdminPlaceCreate(AttractionBase):
    model_config = {"extra": "forbid"}

    category_id: Optional[uuid.UUID] = None
    photo_urls: list[str] = []
    # Set after the admin has seen the possible-duplicate warning.
    confirm_duplicate: bool = False


class AdminPlaceUpdate(BaseModel):
    """Edit a place's details. Status is changed through its own endpoint, so
    an edit can never approve, hide or queue a place as a side effect."""
    model_config = {"extra": "forbid"}

    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = None
    history: Optional[str] = None
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    category_id: Optional[uuid.UUID] = None
    address: Optional[str] = Field(None, max_length=500)
    opening_hours: Optional[dict] = None
    entry_fee: Optional[float] = None
    currency: Optional[str] = Field(None, max_length=10)
    tags: Optional[list[str]] = None
    photo_urls: Optional[list[str]] = None
    geofence_radius_m: Optional[int] = None


class PlaceStatusChange(BaseModel):
    model_config = {"extra": "forbid"}

    status: str
    reason: Optional[str] = None
    note: Optional[str] = Field(None, max_length=2000)


class AdminPlaceUpdateResult(BaseModel):
    place: AdminPlace
    warnings: list[dict] = []
