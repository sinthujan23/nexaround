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


class TrendingExperiencesResponse(BaseModel):
    markdown: str
    places: list[PlaceResponse]
    cached: bool = False


class PlacesNearbyBatchRequest(BaseModel):
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)
    categories: list[str] = Field(default=["POI", "Food & Drink", "Shopping", "Medical"])
    radius: int = Field(default=50000, ge=100, le=50000)
    use_legacy: bool = False
    max_photos: int = Field(default=1, ge=1, le=10)
    limit: int = Field(default=20, ge=1, le=100)


class PlacesNearbyBatchResponse(BaseModel):
    categories: list[str]
    places_by_category: dict[str, list[PlaceResponse]]
    all_places: list[PlaceResponse]
    total: int

