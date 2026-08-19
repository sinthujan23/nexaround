"""Schemas for Google-Places-backed POI discovery.

Mirrors the shape of AttractionResponse so the Flutter `AttractionModel`
can consume both endpoints without a separate model. Differences:
  - `id` is a Google Place ID string, not a UUID.
  - `category_id` is null (Google places aren't in our category table).
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class PlaceResponse(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    history: Optional[str] = None
    latitude: float
    longitude: float
    category_id: Optional[str] = None
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
    distance_m: Optional[float] = None
    is_active: bool = True
    created_at: datetime


class PlacesNearbyResponse(BaseModel):
    """Wraps the result list with cache metadata for debugging / monitoring."""
    places: list[PlaceResponse]
    cached: bool = False
    source: str = Field("google", description="google | cache")


class PlaceBand(BaseModel):
    """One distance band of an Around You / Discovery section."""
    index: int
    min_m: float
    max_m: float
    label: str = Field(..., description="Human-readable range, e.g. '10–25 km'")
    places: list[PlaceResponse]


class BandedPlacesResponse(BaseModel):
    category: str
    bands: list[PlaceBand]
    places: list[PlaceResponse] = Field(
        ...,
        description="All bands flattened, nearest first — for clients that "
                    "render one list and don't care about band boundaries.",
    )
    cached: bool = False
    source: str = Field("database", description="cache | database | google")


class TrendingExperiencesResponse(BaseModel):
    markdown: str
    places: list[PlaceResponse]
    cached: bool = False

