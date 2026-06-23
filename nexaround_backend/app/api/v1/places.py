"""Places API — Google passthrough with shared Redis cache.

Replaces the direct Google calls the mobile client was making, cutting
per-user API spend by ~90% via cache reuse across all users in the same
~500m tile, and removes the Google API key from the mobile binary.
"""
from typing import Optional
from fastapi import APIRouter, HTTPException, Query, Depends
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas.place import PlacesNearbyResponse, TrendingExperiencesResponse
from app.services import places_service, photo_cache_service

router = APIRouter(prefix="/places", tags=["places"])


@router.get("/nearby", response_model=PlacesNearbyResponse)
async def get_nearby_places(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, description="App-side category name"),
    radius: int = Query(5000, ge=100, le=50000),
    use_legacy: bool = Query(False, description="Whether to use legacy Google Places API"),
    around_you: bool = Query(False, description="Whether to apply Around You classification and ranking"),
):
    """Return Google Places near a coordinate. Cached server-side for 7 days."""
    return await places_service.get_nearby(
        latitude=lat,
        longitude=lng,
        category=category,
        radius=radius,
        use_legacy=use_legacy,
        around_you=around_you,
    )


@router.get("/search", response_model=PlacesNearbyResponse)
async def search_places(
    query: str = Query(..., min_length=1, description="Text search query"),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
):
    """Search Google Places near a coordinate by text query. Cached server-side for 7 days."""
    return await places_service.search(
        query=query,
        latitude=lat,
        longitude=lng,
    )


@router.get("/photo")
async def get_place_photo(
    ref: str = Query(..., min_length=10, description="Google photo_reference"),
    maxwidth: int = Query(800, ge=100, le=1600),
):
    """Stream a Place Photo via our cache. First hit fetches from Google; the
    rest are served from local disk. The Google API key never leaves the
    server."""
    path = await photo_cache_service.get_or_fetch(ref, maxwidth=maxwidth)
    if path is None:
        raise HTTPException(status_code=502, detail="Photo unavailable")
    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=2592000"},  # 30d on client
    )


@router.get("/trending", response_model=TrendingExperiencesResponse)
async def get_trending_experiences(
    district: str = Query(..., min_length=1),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    db: AsyncSession = Depends(get_db),
):
    """Fetch Gemini-recommended local experiences and events, with Google Places resolution.
    Cached server-side in Redis for 24 hours.
    """
    return await places_service.get_trending(
        district=district,
        latitude=lat,
        longitude=lng,
        db=db,
    )

