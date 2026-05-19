"""Top-level Places service: cache-first, Google as fallback."""
from typing import Optional
from app.services import google_places_client, place_cache_service
from app.schemas.place import PlaceResponse, PlacesNearbyResponse


def _photo_url(photo_reference: str) -> str:
    """Public URL the mobile app should hit to retrieve a photo.

    Routes through our backend so the Google API key never leaves the server.
    """
    return f"/api/v1/places/photo?ref={photo_reference}"


async def get_nearby(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
) -> PlacesNearbyResponse:
    key = place_cache_service.build_key(latitude, longitude, category, radius)

    cached = await place_cache_service.get_cached(key)
    if cached is not None:
        return PlacesNearbyResponse(
            places=[PlaceResponse.model_validate(p) for p in cached],
            cached=True,
            source="cache",
        )

    raw = await google_places_client.nearby_search(
        latitude=latitude,
        longitude=longitude,
        category=category,
        radius=radius,
    )
    if category == "Food & Drink":
        raw = google_places_client.filter_food(raw)
    elif category != "Beach":
        raw = raw[:40]

    place_dicts = [
        google_places_client.to_place_dict(p, latitude, longitude, category, _photo_url)
        for p in raw
    ]
    place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in place_dicts],
        cached=False,
        source="google",
    )
