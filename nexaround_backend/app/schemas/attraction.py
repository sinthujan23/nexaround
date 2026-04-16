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


class AttractionCreate(AttractionBase):
    category_id: Optional[uuid.UUID] = None
    photo_urls: list[str] = []


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
