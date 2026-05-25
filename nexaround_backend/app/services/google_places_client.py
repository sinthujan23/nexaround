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
    """Call Google Nearby Search (New). Returns the raw places list (unfiltered)."""
    # Cap radius between 1 and 50000 meters for the new Places API
    eff_radius = float(min(max(radius, 1), 50000))

    included_types = []
    if category == "Food & Drink":
        included_types = ["restaurant"]
    elif category == "Beach":
        included_types = ["beach"]
    elif category and category in CATEGORY_TYPE_MAP:
        included_types = [CATEGORY_TYPE_MAP[category]]

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key", settings.GOOGLE_API_KEY)

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": google_maps_key,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.types"
    }

    body = {
        "maxResultCount": 20,
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": latitude,
                    "longitude": longitude
                },
                "radius": eff_radius
            }
        }
    }

    if included_types:
        body["includedTypes"] = included_types

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post("https://places.googleapis.com/v1/places:searchNearby", json=body, headers=headers)
        resp.raise_for_status()
        data = resp.json()

    return data.get("places", [])


def filter_food(places: list[dict]) -> list[dict]:
    """Drop hotels / generic POIs from a 'restaurant' result set."""
    out: list[dict] = []
    seen: set[str] = set()
    for p in places:
        pid = p.get("id") or p.get("place_id")
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
    """Convert a raw Google place (New API format) into the dict that matches PlaceResponse."""
    from datetime import datetime, timezone

    loc = place.get("location") or {}
    plat = float(loc.get("latitude", 0.0))
    plng = float(loc.get("longitude", 0.0))

    display_name = place.get("displayName", {}).get("text") or "Unknown"
    types = list(place.get("types") or [])
    resolved_category = category_name or _resolve_category_from_types(types)

    return {
        "id": place.get("id") or "",
        "name": display_name,
        "description": "",
        "latitude": plat,
        "longitude": plng,
        "category_id": None,
        "category_name": resolved_category,
        "address": "",
        "opening_hours": {},
        "entry_fee": 0.0,
        "currency": "USD",
        "rating": 0.0,
        "review_count": 0,
        "photo_urls": [],
        "tags": types,
        "geofence_radius_m": 100,
        "distance_m": _haversine_m(origin_lat, origin_lng, plat, plng),
        "is_active": True,
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
