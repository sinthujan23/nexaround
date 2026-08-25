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
from app.api.deps import get_current_user, get_current_user_optional
from app.models.user import User
from app.schemas.place import (
    BandedPlacesResponse,
    PlacesNearbyResponse,
    TrendingExperiencesResponse,
)
from app.services import (
    banded_places_service,
    places_service,
    photo_cache_service,
    telemetry,
)

router = APIRouter(prefix="/places", tags=["places"])


@router.get("/nearby", response_model=PlacesNearbyResponse)
async def get_nearby_places(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, description="App-side category name"),
    radius: int = Query(5000, ge=100, le=50000),
    use_legacy: bool = Query(False, description="Whether to use legacy Google Places API"),
    max_photos: int = Query(1, ge=1, le=10, description="Max photos per place to return"),
    limit: int = Query(20, ge=1, le=100, description="Max places to return (pagination)"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
    current_user: User = Depends(get_current_user),
):
    """Return Google Places near a coordinate. Cached server-side for 7 days. Requires authentication."""
    return await places_service.get_nearby(
        latitude=lat,
        longitude=lng,
        category=category,
        radius=radius,
        use_legacy=use_legacy,
        max_photos=max_photos,
        limit=limit,
        offset=offset,
    )



@router.get("/nearby/banded", response_model=BandedPlacesResponse)
async def get_nearby_places_banded(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    category: str = Query(
        ...,
        description="Food & Drink | POI | Nature | Shopping | Medical | Hospital",
    ),
    max_photos: int = Query(1, ge=1, le=10, description="Max photos per place"),
    force_refresh: bool = Query(False, description="Bypass the Redis entry"),
    per_band: Optional[int] = Query(
        None, ge=1, le=40,
        description="Override the per-band quota. Around You omits this and gets "
                    "BAND_QUOTAS (4/3/3); Discovery asks for more to list a full "
                    "page per category. Both share one cache entry.",
    ),
    current_user: User = Depends(get_current_user),
):
    """Places for one Around You / Discovery section, split into distance bands.

    Returns ten places — drawn from three bands whose widths are set per category
    (see `place_bands.CATEGORY_BANDS`) on the quotas in `BAND_QUOTAS` — so the
    section reads as a progression outward instead of ten near-identical nearby
    results. Bands the database cannot fill are backfilled nearest-first, so the
    count holds up in sparse areas.

    POI/Nature and Hospital/Medical are exclusive pairs drawn from one shared
    pool each and split by Google type, so a place is never returned by both
    halves of a pair.

    Kept separate from `/nearby` deliberately: the AR ring, the emergency card
    and text search all want a flat radius query, and should not inherit band
    semantics or the extra Google requests that filling an outer band can cost.
    """
    return await banded_places_service.get_nearby_banded(
        latitude=lat,
        longitude=lng,
        category=category,
        max_photos=max_photos,
        force_refresh=force_refresh,
        per_band=per_band,
    )


@router.get("/search", response_model=PlacesNearbyResponse)
async def search_places(
    query: str = Query(..., min_length=1, description="Text search query"),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    radius_m: Optional[float] = Query(
        None, ge=500, le=50000,
        description="Location bias radius in meters. Omitted, keeps the "
                    "default 50km bias; a near_me search should pass a tight "
                    "radius (2-5km) instead.",
    ),
    near_me: bool = Query(
        False,
        description="Set when `query` is a locality-stripped 'near me' "
                    "subject (e.g. 'atm' from 'atm near me'), not a proper "
                    "place name — enables direct type resolution (atm, "
                    "bakery, gym, ...) ahead of the name match / Text Search.",
    ),
    current_user: User = Depends(get_current_user),
):
    """Search Google Places near a coordinate by text query. Cached server-side for 7 days. Requires authentication."""
    return await places_service.search(
        query=query,
        latitude=lat,
        longitude=lng,
        radius_m=radius_m,
        near_me=near_me,
    )


@router.get("/photo")
async def get_place_photo(
    ref: str = Query(..., min_length=10, description="Google photo_reference"),
    maxwidth: int = Query(800, ge=100, le=1600),
    i: int = Query(
        0, ge=0, le=9,
        description="Which of the place's photos this is. The cache is keyed on "
                    "place + position because the reference itself is reissued "
                    "under a new token on every Google response. Defaults to 0 "
                    "so URLs minted before this keep resolving.",
    ),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Stream a Place Photo via our cache.

    Auth is optional, because this URL is consumed as an image source and image
    loaders do not send an Authorization header — requiring one made every
    photo request 401 and put the client into a retry loop (~20k failures/day).

    Anonymous callers are served from the local cache only. That keeps the
    endpoint from being used as a free photo proxy: without a token nothing here
    can reach Google, so an unauthenticated request can never cost money. A
    signed-in caller may trigger the first fetch for a photo we do not hold yet.
    """
    if current_user is None:
        path = photo_cache_service.cached_path(ref, maxwidth, i)
        cached = path.exists() and path.stat().st_size > 0
        # Recorded here rather than left to get_or_fetch, which this branch
        # deliberately skips. Anonymous image loads are the bulk of photo
        # traffic, so omitting them would make the cache look far less
        # effective than it is.
        async with telemetry.track(
            "internal", "place_photo",
            cache_key=f"photo:{photo_cache_service._stable_identity(ref, i)}:{maxwidth}",
        ) as t:
            t.hit("disk" if cached else "negative")
        if not cached:
            # Not cached and no credentials to justify buying it.
            raise HTTPException(status_code=404, detail="Photo not cached")
    else:
        path = await photo_cache_service.get_or_fetch(ref, maxwidth=maxwidth, index=i)
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
    current_user: User = Depends(get_current_user),
):
    """Fetch Gemini-recommended local experiences and events, with Google Places resolution.
    Cached server-side in Redis for 24 hours. Requires authentication.
    """
    return await places_service.get_trending(
        district=district,
        latitude=lat,
        longitude=lng,
        db=db,
    )


@router.get("/{place_id}/details")
async def get_place_details_endpoint(
    place_id: str,
    name: Optional[str] = Query(
        None,
        description="Place name, used to resolve a Place ID when `place_id` is "
                    "not one — a local UUID whose row predates google_place_id, "
                    "or a client-side placeholder.",
    ),
    lat: Optional[float] = Query(None, ge=-90.0, le=90.0),
    lng: Optional[float] = Query(None, ge=-180.0, le=180.0),
    current_user: User = Depends(get_current_user),
):
    """Fetch rich details (reviews, opening hours, photos, price) for a place.

    Google Places API (Legacy) throughout — Find Place to map an identifier we
    cannot send upstream onto a real Place ID, then Place Details — behind a
    14-day Redis cache. Resolution lives here rather than in the client so the
    detail page does not have to make a `/places/search` round trip first, which
    was reaching Places API (New) Text Search on a database miss.
    """
    details = await places_service.get_place_details(
        place_id, name=name, latitude=lat, longitude=lng,
    )
    if details is None:
        raise HTTPException(status_code=404, detail="Place details not found")
    return details

