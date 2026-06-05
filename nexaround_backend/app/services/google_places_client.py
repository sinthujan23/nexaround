"""Thin async client around Google Places + Photos.

Only this module ever sees GOOGLE_API_KEY. The mobile client never receives
the key, never sees a googleapis.com URL.
"""
import math
from typing import Optional
import httpx
from app.core.database import async_session
from app.services.settings_service import SettingsService


_BASE = "https://maps.googleapis.com/maps/api"


# Expanded Google Place types map to retrieve a much wider and richer set of places
# for each application category, resolving the issue of sparse results.
CATEGORY_TYPES_MAP: dict[str, list[str]] = {
    "Attractions": [
        "tourist_attraction", "museum", "art_gallery", "historical_landmark",
        "place_of_worship", "church", "hindu_temple", "mosque", "synagogue",
        "buddhist_temple", "amusement_park", "aquarium", "cultural_center"
    ],
    "Food & Drink": [
        "restaurant", "cafe", "coffee_shop", "bar", "bakery", "fast_food_restaurant",
        "ice_cream_shop", "food_court", "pub", "wine_bar", "meal_takeaway", "meal_delivery"
    ],
    "Hotels": [
        "lodging", "hotel", "motel", "resort_hotel", "guest_house", "hostel",
        "bed_and_breakfast"
    ],
    "Shopping": [
        "shopping_mall", "department_store", "clothing_store", "supermarket",
        "grocery_store", "convenience_store", "gift_shop", "book_store",
        "electronics_store", "jewelry_store", "shoe_store", "store"
    ],
    "Experiences": [
        "amusement_park", "aquarium", "zoo", "museum", "art_gallery"
    ],
    "Transport": [
        "transit_station", "bus_station", "train_station", "subway_station",
        "light_rail_station", "airport", "taxi_stand"
    ],
    "Medical": [
        "hospital", "pharmacy", "medical_clinic", "dentist"
    ],
    "Beach": [
        "beach", "park", "national_park", "campground", "hiking_area", "garden", "zoo"
    ],
}

# Genuine food categories Google returns. Used to filter the broader
# restaurant-typed result set (which can include hotels with restaurants etc.)
_FOOD_TYPE_WHITELIST = {
    "restaurant", "cafe", "food", "bakery", "bar",
    "meal_takeaway", "meal_delivery",
}


# Aliases → canonical CATEGORY_TYPES_MAP keys. Different UI surfaces send
# different vocabularies: the AR navigation tiles use short lowercase ids
# ('food', 'historical'), the chat chips/datasource use full names
# ('Food & Drink'). Without normalization an unrecognized label falls through
# to an UNFILTERED nearby search — that's how banks/ATMs ended up under "Food".
# Keys here MUST be lowercase (lookup is done on category.lower()).
_CATEGORY_ALIASES: dict[str, str] = {
    "food": "Food & Drink",
    "food & drink": "Food & Drink",
    "food and drink": "Food & Drink",
    "drink": "Food & Drink",
    "restaurant": "Food & Drink",
    "restaurants": "Food & Drink",
    "shop": "Shopping",
    "shops": "Shopping",
    "historical": "Attractions",
    "historical sites": "Attractions",
    "history": "Attractions",
    "attraction": "Attractions",
    "hotel": "Hotels",
    "stay": "Hotels",
    "lodging": "Hotels",
    "service": "Experiences",
    "services": "Experiences",
    "experience": "Experiences",
}


# Case-insensitive index of the canonical keys so 'shopping' resolves to
# 'Shopping', 'attractions' to 'Attractions', etc. without an alias entry each.
_CANONICAL_BY_LOWER: dict[str, str] = {k.lower(): k for k in CATEGORY_TYPES_MAP}


def canonical_category(category: Optional[str]) -> Optional[str]:
    """Map any UI category label to a canonical CATEGORY_TYPES_MAP key.

    Resolution order: exact canonical match → case-insensitive canonical match
    ('shopping' → 'Shopping') → known synonym alias ('historical' →
    'Attractions'). Anything unknown is returned unchanged (still safe — just
    unfiltered). Idempotent, so it's safe to call repeatedly along the path.
    """
    if not category:
        return category
    key = category.strip()
    if key in CATEGORY_TYPES_MAP:
        return key
    lower = key.lower()
    if lower in _CANONICAL_BY_LOWER:
        return _CANONICAL_BY_LOWER[lower]
    return _CATEGORY_ALIASES.get(lower, key)


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

    # Normalize any UI label (e.g. AR tile 'food') to a canonical key so the
    # type filter is actually applied instead of silently searching everything.
    category = canonical_category(category)
    included_types = []
    if category and category in CATEGORY_TYPES_MAP:
        included_types = CATEGORY_TYPES_MAP[category]

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    # Single source of truth: the admin-panel key only. No baked-in fallback,
    # so an unset key never silently bills a leftover company account.
    if not google_maps_key:
        print("⚠️ google_maps_api_key not set in admin settings — returning no places")
        return []

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": google_maps_key,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.types,places.photos,places.rating,places.userRatingCount"
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
        if resp.status_code != 200:
            # Log Google's verbatim error (API-not-enabled / billing disabled /
            # key restriction) so the cause is visible in server logs instead of
            # surfacing as a blind 500.
            print(f"❌ Google searchNearby HTTP {resp.status_code}: {resp.text[:600]}")
            resp.raise_for_status()
        data = resp.json()

    return data.get("places", [])


async def text_search(
    *,
    query: str,
    latitude: float,
    longitude: float,
) -> list[dict]:
    """Call Google Text Search (New). Returns the raw places list (unfiltered)."""
    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ google_maps_api_key not set in admin settings — returning no places")
        return []

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": google_maps_key,
        "X-Goog-FieldMask": "places.id,places.displayName,places.location,places.types,places.formattedAddress,places.photos,places.rating,places.userRatingCount"
    }

    body = {
        "textQuery": query,
        "locationBias": {
            "circle": {
                "center": {
                    "latitude": latitude,
                    "longitude": longitude
                },
                "radius": 50000.0
            }
        }
    }

    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post("https://places.googleapis.com/v1/places:searchText", json=body, headers=headers)
        if resp.status_code != 200:
            print(f"❌ Google searchText HTTP {resp.status_code}: {resp.text[:600]}")
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

    photos = place.get("photos") or []
    photo_urls = []
    if photos and photo_url_builder:
        for ph in photos:
            ref = ph.get("name")
            if ref:
                photo_urls.append(photo_url_builder(ref))

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
        "rating": float(place.get("rating") or 4.0),
        "review_count": int(place.get("userRatingCount") or 0),
        "photo_urls": photo_urls,
        "tags": types,
        "geofence_radius_m": 100,
        "distance_m": _haversine_m(origin_lat, origin_lng, plat, plng),
        "is_active": True,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def _resolve_category_from_types(types: list[str]) -> str:
    t = set(types)
    if t & {"lodging", "hotel", "motel", "resort_hotel", "hostel", "guest_house", "bed_and_breakfast"}:
        return "Hotels"
    if t & {"restaurant", "food", "cafe", "bar", "coffee_shop", "bakery", "fast_food_restaurant", "food_court", "pub", "wine_bar"}:
        return "Food & Drink"
    if t & {"park", "campground", "natural_feature", "beach", "national_park", "hiking_area", "garden", "zoo"}:
        return "Nature"
    if t & {"hospital", "pharmacy", "medical_clinic", "dentist"}:
        return "Medical"
    if t & {"tourist_attraction", "museum", "art_gallery", "historical_landmark", "place_of_worship", "church", "hindu_temple", "mosque", "synagogue", "buddhist_temple", "amusement_park", "aquarium", "cultural_center"}:
        return "Attractions"
    if t & {"shopping_mall", "store", "department_store", "clothing_store", "supermarket", "grocery_store", "convenience_store", "gift_shop", "book_store", "electronics_store", "jewelry_store", "shoe_store"}:
        return "Shopping"
    return "Attractions"


async def fetch_photo_bytes(photo_reference: str, maxwidth: int = 800) -> tuple[bytes, str]:
    """Download a Place Photo. Returns (bytes, content_type)."""
    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        if photo_reference.startswith("places/"):
            # New Places API Photo endpoint
            url = f"https://places.googleapis.com/v1/{photo_reference}/media"
            params = {
                "key": google_maps_key,
                "maxWidthPx": maxwidth,
            }
            resp = await client.get(url, params=params)
        else:
            # Legacy Places API Photo endpoint
            url = f"{_BASE}/place/photo"
            params = {
                "maxwidth": maxwidth,
                "photo_reference": photo_reference,
                "key": google_maps_key,
            }
            resp = await client.get(url, params=params)
            
        resp.raise_for_status()
        ctype = resp.headers.get("content-type", "image/jpeg")
        return resp.content, ctype
