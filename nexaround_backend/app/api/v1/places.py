"""Places API — Google passthrough with shared Redis cache.

Replaces the direct Google calls the mobile client was making, cutting
per-user API spend by ~90% via cache reuse across all users in the same
~500m tile, and removes the Google API key from the mobile binary.
"""
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.schemas.place import PlacesNearbyResponse
from app.services import places_service, photo_cache_service

router = APIRouter(prefix="/places", tags=["places"])


@router.get("/nearby", response_model=PlacesNearbyResponse)
async def get_nearby_places(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, description="App-side category name"),
    radius: int = Query(5000, ge=100, le=50000),
):
    """Return Google Places near a coordinate. Cached server-side for 7 days."""
    return await places_service.get_nearby(
        latitude=lat,
        longitude=lng,
        category=category,
        radius=radius,
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
