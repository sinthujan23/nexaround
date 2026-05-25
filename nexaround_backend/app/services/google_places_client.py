"""Thin async client around Google Places + Photos.

Only this module ever sees GOOGLE_API_KEY. The mobile client never receives
the key, never sees a googleapis.com URL.
"""
import math
from typing import Optional
import httpx
from app.core.config import settings
from app.core.database import async_session
from app.services.settings_service import SettingsService


_BASE = "https://maps.googleapis.com/maps/api"


# Mirrors the Flutter-side mapping in google_places_service.dart so the
# behavior stays identical for callers during the cut-over.
CATEGORY_TYPE_MAP: dict[str, str] = {
    "Attractions": "tourist_attraction",
    "Food & Drink": "restaurant",
    "Hotels": "lodging",
    "Shopping": "shopping_mall",
    "Experiences": "amusement_park",
    "Transport": "transit_station",
    "Medical": "hospital",
}

# Genuine food categories Google returns. Used to filter the broader
# restaurant-typed result set (which can include hotels with restaurants etc.)
_FOOD_TYPE_WHITELIST = {
    "restaurant", "cafe", "food", "bakery", "bar",
    "meal_takeaway", "meal_delivery",
}


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371000.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlng / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(a))


async def nearby_search(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
) -> list[dict]:
    """Call Google Nearby Search. Returns the raw places list (unfiltered)."""
    if category == "Food & Drink":
        google_type = "restaurant"
        eff_radius = min(radius, 10000)
    elif category == "Beach":
        google_type = None
        eff_radius = max(radius, 50000)
    else:
        google_type = CATEGORY_TYPE_MAP.get(category or "", "point_of_interest")
        eff_radius = radius

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key", settings.GOOGLE_API_KEY)

    params = {
        "location": f"{latitude},{longitude}",
        "radius": eff_radius,
        "key": google_maps_key,
    }
    if category == "Beach":
        params["keyword"] = "beach"
    if google_type:
        params["type"] = google_type
        params["rankby"] = "prominence"

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(f"{_BASE}/place/nearbysearch/json", params=params)
        resp.raise_for_status()
        data = resp.json()

    if data.get("status") not in ("OK", "ZERO_RESULTS"):
        # Log but don't crash; treat as empty.
        return []
    return data.get("results", [])


def filter_food(places: list[dict]) -> list[dict]:
    """Drop hotels / generic POIs from a 'restaurant' result set."""
    out: list[dict] = []
    seen: set[str] = set()
    for p in places:
        pid = p.get("place_id")
        if not pid or pid in seen:
            continue
        types = set(p.get("types") or [])
        if types & _FOOD_TYPE_WHITELIST:
            seen.add(pid)
            out.append(p)
    return out


def to_place_dict(
    place: dict,
    origin_lat: float,
    origin_lng: float,
    category_name: Optional[str],
    photo_url_builder,
) -> dict:
    """Convert a raw Google place into the dict that matches PlaceResponse."""
    from datetime import datetime, timezone

    loc = place.get("geometry", {}).get("location") or {}
    plat = float(loc.get("lat", 0.0))
    plng = float(loc.get("lng", 0.0))

    photos = place.get("photos") or []
    photo_urls: list[str] = []
    if photos:
        ref = photos[0].get("photo_reference")
        if ref:
            photo_urls = [photo_url_builder(ref)]

    types = list(place.get("types") or [])
    resolved_category = category_name or _resolve_category_from_types(types)

    return {
        "id": place.get("place_id") or "",
        "name": place.get("name") or "Unknown",
        "description": place.get("vicinity") or "",
        "latitude": plat,
        "longitude": plng,
        "category_id": None,
        "category_name": resolved_category,
        "address": place.get("vicinity") or "",
        "opening_hours": {},
        "entry_fee": 0.0,
        "currency": "USD",
        "rating": float(place.get("rating") or 0.0),
        "review_count": int(place.get("user_ratings_total") or 0),
        "photo_urls": photo_urls,
        "tags": types,
        "geofence_radius_m": 100,
        "distance_m": _haversine_m(origin_lat, origin_lng, plat, plng),
        "is_active": (place.get("business_status") or "OPERATIONAL") == "OPERATIONAL",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def _resolve_category_from_types(types: list[str]) -> str:
    t = set(types)
    if "lodging" in t: return "Hotels"
    if t & {"restaurant", "food", "cafe", "bar"}: return "Food & Drink"
    if t & {"park", "campground", "natural_feature"}: return "Nature"
    if t & {"tourist_attraction", "museum"}: return "Attractions"
    if t & {"shopping_mall", "store"}: return "Shopping"
    return "Attractions"


async def fetch_photo_bytes(photo_reference: str, maxwidth: int = 800) -> tuple[bytes, str]:
    """Download a Place Photo. Returns (bytes, content_type)."""
    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key", settings.GOOGLE_API_KEY)

    params = {
        "maxwidth": maxwidth,
        "photo_reference": photo_reference,
        "key": google_maps_key,
    }
    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        resp = await client.get(f"{_BASE}/place/photo", params=params)
        resp.raise_for_status()
        ctype = resp.headers.get("content-type", "image/jpeg")
        return resp.content, ctype
