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
    category: Optional[str] = None
    address: Optional[str] = None
    opening_hours: dict = {}
    entry_fee: float = 0.0
    currency: str = "USD"
    rating: float = 0.0
    review_count: int = 0
    photo_urls: list[str] = []
    photo_url: Optional[str] = None
    tags: list[str] = []
    geofence_radius_m: int = 100
    distance_m: Optional[float] = None
    is_active: bool = True
    created_at: datetime
    discovery_score: float = 0.0
    is_hidden_gem: bool = False


class PlacesNearbyResponse(BaseModel):
    """Wraps the result list with cache metadata for debugging / monitoring."""
    places: list[PlaceResponse]
    cached: bool = False
    source: str = Field("google", description="google | cache")


class TrendingExperiencesResponse(BaseModel):
    markdown: str
    places: list[PlaceResponse]
    cached: bool = False

