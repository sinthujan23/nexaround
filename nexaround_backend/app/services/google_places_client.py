"""Thin async client around Google Places + Photos.

Only this module ever sees GOOGLE_API_KEY. The mobile client never receives
the key, never sees a googleapis.com URL.
"""
import math
from typing import Optional
import httpx
from app.core.database import async_session
from app.services.settings_service import SettingsService
from app.services import telemetry


_BASE = "https://maps.googleapis.com/maps/api"


# Expanded Google Place types map to retrieve a much wider and richer set of places
# for each application category, resolving the issue of sparse results.
#
# Every type here is verified against Places API (New). That matters for cost,
# not just correctness: the API rejects the WHOLE request with 400 if a single
# includedType is unsupported, and the self-heal loop below then re-issues it —
# a second billed request on every call. These eight legacy types used to sit in
# the map and were doing exactly that to POI, Food & Drink and Medical:
#
#   food, health, nature_reserve, place_of_worship, resort, scenic_point,
#   scenic_viewpoint, waterfall
#
# Replacements below are drawn only from types the API confirmed it accepts
# (wildlife_refuge/wildlife_park for nature_reserve, the individual worship
# types for place_of_worship, observation_deck for scenic_viewpoint, and so on).
# To re-audit after Google changes its type list, probe includedTypes with a
# deliberately invalid sentinel type appended: the 400 names every unsupported
# type in the batch, and a 400 is not billed.
CATEGORY_TYPES_MAP: dict[str, list[str]] = {
    # Built things worth going to see. The outdoor types this list used to carry
    # moved to 'Nature' when the two became separate sections — leaving them here
    # would have both sections buying, and showing, the same parks.
    "POI": [
        "tourist_attraction", "museum", "art_gallery",
        "historical_landmark", "historical_place", "cultural_landmark",
        "monument", "castle", "sculpture",
        "hindu_temple", "church", "mosque", "synagogue", "buddhist_temple",
        "cultural_center", "visitor_center", "observation_deck",
        "zoo", "aquarium", "amusement_park", "water_park", "planetarium",
        "performing_arts_theater", "amusement_center"
    ],
    "Attractions": [
        "tourist_attraction", "museum", "park", "zoo", "aquarium", "art_gallery",
        "amusement_park", "national_park", "hiking_area", "beach",
        "historical_landmark", "historical_place", "cultural_landmark",
        "hindu_temple", "church", "mosque", "synagogue", "buddhist_temple",
        "cultural_center", "marina", "visitor_center", "observation_deck",
        "wildlife_refuge", "monument", "castle"
    ],
    "Food & Drink": [
        "restaurant", "cafe", "bakery", "meal_takeaway", "meal_delivery",
        "bar", "night_club", "ice_cream_shop", "coffee_shop", "tea_house",
        "fast_food_restaurant", "dessert_shop", "food_court"
    ],
    "Hotels": [
        "lodging", "hotel", "motel", "resort_hotel", "bed_and_breakfast",
        "hostel", "guest_house", "campground", "inn", "cottage"
    ],
    # `pharmacy` is deliberately absent. A chemist is a shop, but it is the
    # Medical section people open when they want one, and leaving the type here
    # listed every pharmacy in the area under Shopping as well.
    "Shopping": [
        "supermarket", "store", "department_store",
        "convenience_store", "electronics_store", "market",
        "grocery_store", "home_goods_store",
        "hardware_store"
    ],
    "Experiences": [
        "amusement_park", "aquarium", "zoo", "museum", "art_gallery",
        "bowling_alley", "movie_theater", "spa", "casino", "golf_course",
        "water_park", "planetarium", "performing_arts_theater"
    ],
    "Transport": [
        "transit_station", "airport", "bus_station", "train_station", "taxi_stand",
        "subway_station", "ferry_terminal", "light_rail_station"
    ],
    # Everyday health: somewhere you walk into for a prescription, a filling or
    # a blood test. `hospital` is deliberately absent — it is what makes a place
    # belong to 'Hospital' instead, and admitting it here put the same
    # institutions at the top of both sections.
    "Medical": [
        "pharmacy", "drugstore", "doctor", "dentist",
        "dental_clinic", "physiotherapist", "chiropractor", "medical_lab",
        "veterinary_care", "medical_clinic"
    ],
    "Nature": [
        "park", "national_park", "state_park", "beach", "hiking_area",
        "wildlife_refuge", "wildlife_park", "lake", "river", "marina",
        "botanical_garden", "garden", "picnic_ground"
    ],
    "Beach": [
        "park", "tourist_attraction", "beach"
    ],
    # One type on purpose. Google ranks its twenty results across the whole
    # includedTypes list, so pairing `hospital` with `medical_clinic` meant a
    # dense strip of clinics could return twenty clinics and no hospital.
    "Hospital": [
        "hospital"
    ],
}

CATEGORY_LEGACY_TYPE_MAP: dict[str, str] = {
    "POI": "tourist_attraction",
    "Attractions": "tourist_attraction",
    "Food & Drink": "restaurant",
    "Hotels": "lodging",
    "Shopping": "shopping_mall",
    "Experiences": "amusement_park",
    "Transport": "transit_station",
    "Medical": "hospital",
    "Beach": "park",
    "Nature": "park",
    "Hospital": "hospital",
}



# Aliases → canonical CATEGORY_TYPES_MAP keys. Different UI surfaces send
# different vocabularies: the AR navigation tiles use short lowercase ids
# ('food', 'historical'), the chat chips/datasource use full names
# ('Food & Drink'). Without normalization an unrecognized label falls through
# to an UNFILTERED nearby search — that's how banks/ATMs ended up under "Food".
# Keys here MUST be lowercase (lookup is done on category.lower()).
_CATEGORY_ALIASES: dict[str, str] = {
    "poi": "POI",
    "point of interest": "POI",
    "points of interest": "POI",
    "attraction": "POI",
    "attractions": "POI",
    "experience": "POI",
    "experiences": "POI",
    "sight": "POI",
    "sights": "POI",
    "food": "Food & Drink",
    "food & drink": "Food & Drink",
    "food and drink": "Food & Drink",
    "drink": "Food & Drink",
    "restaurant": "Food & Drink",
    "restaurants": "Food & Drink",
    "shop": "Shopping",
    "shops": "Shopping",
    "shopping": "Shopping",
    "mall": "Shopping",
    "malls": "Shopping",
    "historical": "POI",
    "historical sites": "POI",
    "history": "POI",
    "hotel": "Hotels",
    "stay": "Hotels",
    "lodging": "Hotels",
    "service": "POI",
    "services": "POI",
    "medical": "Medical",
    "clinic": "Medical",
    "clinics": "Medical",
    "pharmacy": "Medical",
    "pharmacies": "Medical",
    "doctor": "Medical",
    "dentist": "Medical",
    # 'nature', 'hospital' and 'beach' need no entry — each is a canonical key
    # already, and the case-insensitive canonical index below outranks this
    # table. Listing them here would be dead weight that reads like a rule.
    "park": "Nature",
    "parks": "Nature",
    "garden": "Nature",
    "gardens": "Nature",
    "waterfall": "Nature",
    "waterfalls": "Nature",
    "hiking": "Nature",
    "outdoors": "Nature",
    "wildlife": "Nature",
    "national park": "Nature",
    "hospitals": "Hospital",
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


def _unsupported_types(resp) -> set[str]:
    """Parse a Places API (New) 400 'Unsupported types: X, Y.' error body into
    the set of offending type strings, so the caller can strip them and retry.
    Returns an empty set if the message isn't a recognizable type error."""
    try:
        msg = (resp.json().get("error", {}) or {}).get("message", "") or ""
    except Exception:
        msg = resp.text or ""
    marker = "Unsupported types:"
    if marker not in msg:
        return set()
    tail = msg.split(marker, 1)[1].strip().rstrip(".")
    return {t.strip() for t in tail.split(",") if t.strip()}


async def nearby_search(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
    included_types_override: Optional[list[str]] = None,
    type_group: Optional[str] = None,
) -> list[dict]:
    """Call Google Nearby Search (New). Returns the raw places list (unfiltered).

    `included_types_override` narrows the search to a subset of the category's
    types — used by the banded fetch to give each POI sub-group its own request,
    so the 20-result cap is competed for within one theme instead of across all
    of them. `type_group` only labels the telemetry row.
    """
    # Cap radius between 1 and 50000 meters for the new Places API
    eff_radius = float(min(max(radius, 1), 50000))

    # Normalize any UI label (e.g. AR tile 'food') to a canonical key so the
    # type filter is actually applied instead of silently searching everything.
    category = canonical_category(category)
    if included_types_override is not None:
        included_types = included_types_override
    elif category and category in CATEGORY_TYPES_MAP:
        included_types = CATEGORY_TYPES_MAP[category]
    else:
        included_types = []

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
    # Nearby Search (New) hard-caps maxResultCount at 20 — requesting more (this
    # used to ask for 40 on radius > 10km) makes Google reject the WHOLE request
    # with 400 INVALID_ARGUMENT, which surfaced here as a 500. That silently
    # broke every wide-radius search (25–50km AR ring, etc.). Always request the
    # API maximum of 20.
    max_results = 20

    body = {
        "maxResultCount": max_results,
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

    # Work on a mutable copy so the self-heal loop below can prune types.
    included_types = list(included_types)
    if included_types:
        body["includedTypes"] = list(included_types)

    async with httpx.AsyncClient(timeout=15.0) as client:
        # Self-heal: the Places API (New) rejects the WHOLE request with 400 if
        # any single includedType isn't supported (e.g. legacy 'place_of_worship').
        # Strip the type(s) Google names and retry, so the valid types still
        # return results instead of the category coming back empty.
        resp = None
        for _attempt in range(len(included_types) + 1):
            # Tracked per attempt, not per call: the self-heal retry issues a
            # fresh request each time, and each successful one is billed.
            async with telemetry.track(
                "google_maps", "nearby_search",
                sku="nearby_search_new",
                cache_key=(
                    f"nb:{latitude:.4f}:{longitude:.4f}:{category}"
                    f"{':' + type_group if type_group else ''}:{radius}"
                ),
                params=body,
            ) as t:
                resp = await client.post(
                    "https://places.googleapis.com/v1/places:searchNearby",
                    json=body,
                    headers=headers,
                )
                t.upstream(resp)
            if resp.status_code == 200:
                break

            bad = _unsupported_types(resp) if resp.status_code == 400 else set()
            if not bad:
                break  # not a recoverable type error — fall through to raise

            included_types = [t for t in included_types if t not in bad]
            print(f"⚠️ Dropping unsupported includedTypes {sorted(bad)}; "
                  f"retrying with {len(included_types)} type(s)")
            if included_types:
                body["includedTypes"] = list(included_types)
            else:
                # All types were unsupported — fall back to an untyped nearby
                # search rather than failing the whole category.
                body.pop("includedTypes", None)

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
        async with telemetry.track(
            "google_maps", "text_search",
            sku="text_search_new",
            cache_key=f"ts:{query.strip().lower()}",
            params=body,
        ) as t:
            resp = await client.post("https://places.googleapis.com/v1/places:searchText", json=body, headers=headers)
            t.upstream(resp)
        if resp.status_code != 200:
            print(f"❌ Google searchText HTTP {resp.status_code}: {resp.text[:600]}")
            resp.raise_for_status()
        data = resp.json()

    return data.get("places", [])


_FOOD_TYPE_WHITELIST = {
    "restaurant", "cafe", "bakery", "bar",
    "meal_takeaway", "meal_delivery",
}

_EXCLUDE_FOOD_TYPES = {
    "car_repair", "auto_parts", "hardware_store", "gas_station"
}

def filter_food(places: list[dict]) -> list[dict]:
    """Drop hotels / generic POIs from a 'restaurant' result set."""
    out: list[dict] = []
    seen: set[str] = set()
    for p in places:
        pid = p.get("id") or p.get("place_id")
        if not pid or pid in seen:
            continue
        types = set(p.get("types") or [])
        if types & _EXCLUDE_FOOD_TYPES:
            continue
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
        for ph in photos[:2]:
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
    if t & {"restaurant", "cafe", "bakery", "meal_takeaway", "meal_delivery", "food"}:
        return "Food & Drink"
    # `zoo` sits with the built attractions, not here: a zoo is a ticketed venue
    # that happens to be outdoors, and the Nature section is about the outdoors
    # itself. Keeping the two consistent matters because this decides the
    # category a seeded row is stored under.
    if t & {"park", "campground", "natural_feature", "beach", "national_park", "hiking_area", "garden", "botanical_garden", "lake", "river"}:
        return "Nature"
    if t & {"hospital"}:
        return "Hospital"
    if t & {"pharmacy", "doctor", "dentist", "health", "medical_clinic", "physiotherapist"}:
        return "Medical"
    
    # Exclude these from Attractions resolution
    exclude_attractions = {
        "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
        "school", "primary_school", "secondary_school", "preschool", "kindergarten", "university",
        "bank", "atm", "accounting", "lawyer", "insurance_agency", "real_estate_agency",
        "car_repair", "gas_station", "car_dealer", "car_rental", "car_wash",
        "store", "clothing_store", "electronics_store", "supermarket", "convenience_store", "grocery_store",
        "gym", "fitness_center", "laundry", "dry_cleaning", "post_office", "police", "fire_station",
        "cemetery", "funeral_home"
    }
    if t & exclude_attractions:
        if t & {"shopping_mall", "supermarket", "store", "department_store", "convenience_store", "clothing_store"}:
            return "Shopping"
        return "Others"

    if t & {"tourist_attraction", "museum", "zoo", "aquarium", "art_gallery", "amusement_park", "historical_landmark", "castle", "monument"}:
        return "Attractions"
    if t & {"shopping_mall", "supermarket", "store", "department_store", "convenience_store"}:
        return "Shopping"
    return "Others"



async def nearby_search_legacy(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
) -> list[dict]:
    """Call Google Nearby Search (Legacy). Returns the raw places list (unfiltered)."""
    # Cap radius between 1 and 50000 meters for legacy Places API
    eff_radius = float(min(max(radius, 1), 50000))

    # Normalize category name to a canonical key so the type filter is mapped correctly
    category = canonical_category(category)
    legacy_type = CATEGORY_LEGACY_TYPE_MAP.get(category) if category else None

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ google_maps_api_key not set in admin settings — returning no places")
        return []

    params = {
        "location": f"{latitude},{longitude}",
        "radius": eff_radius,
        "key": google_maps_key,
    }

    if legacy_type:
        params["type"] = legacy_type

    async with httpx.AsyncClient(timeout=15.0) as client:
        async with telemetry.track(
            "google_maps", "nearby_search_legacy",
            sku="nearby_search_legacy",
            cache_key=f"nbl:{latitude:.4f}:{longitude:.4f}:{legacy_type or 'all'}:{eff_radius}",
            params=params,
        ) as t:
            resp = await client.get("https://maps.googleapis.com/maps/api/place/nearbysearch/json", params=params)
            t.upstream(resp)
        if resp.status_code != 200:
            print(f"❌ Google nearbysearch legacy HTTP {resp.status_code}: {resp.text[:600]}")
            resp.raise_for_status()
        data = resp.json()

    return data.get("results", [])


def to_place_dict_legacy(
    place: dict,
    origin_lat: float,
    origin_lng: float,
    category_name: Optional[str],
    photo_url_builder,
) -> dict:
    """Convert a raw Google place (Legacy API format) into the dict that matches PlaceResponse."""
    from datetime import datetime, timezone

    geom = place.get("geometry") or {}
    loc = geom.get("location") or {}
    plat = float(loc.get("lat", 0.0))
    plng = float(loc.get("lng", 0.0))

    display_name = place.get("name") or "Unknown"
    types = list(place.get("types") or [])
    resolved_category = category_name or _resolve_category_from_types(types)

    photos = place.get("photos") or []
    photo_urls = []
    if photos and photo_url_builder:
        for ph in photos[:2]:
            ref = ph.get("photo_reference")
            if ref:
                photo_urls.append(photo_url_builder(ref))

    return {
        "id": place.get("place_id") or "",
        "name": display_name,
        "description": place.get("vicinity") or "",
        "latitude": plat,
        "longitude": plng,
        "category_id": None,
        "category_name": resolved_category,
        "address": place.get("vicinity") or "",
        "opening_hours": {},
        "entry_fee": 0.0,
        "currency": "USD",
        "rating": float(place.get("rating") or 4.0),
        "review_count": int(place.get("user_ratings_total") or 0),
        "photo_urls": photo_urls,
        "tags": types,
        "geofence_radius_m": 100,
        "distance_m": _haversine_m(origin_lat, origin_lng, plat, plng),
        "is_active": True,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


async def fetch_photo_bytes(photo_reference: str, maxwidth: int = 800) -> tuple[bytes, str]:
    """Download a Place Photo. Returns (bytes, content_type).

    Photo bytes are cached in Redis (7-day TTL) keyed by reference + width,
    since place photos are static and rarely change. This avoids repeated
    Google Places Photo API calls for the same image.
    """
    import base64
    from app.services import place_cache_service

    cache_key = f"photo:v1:{photo_reference}:w{maxwidth}"

    # 1. Try cache first
    try:
        cached_raw = await place_cache_service.get_raw(cache_key)
        if cached_raw is not None:
            import json
            cached = json.loads(cached_raw)
            return base64.b64decode(cached["data"]), cached["ctype"]
    except Exception as e:
        print(f"⚠️ Photo cache GET error: {e}")

    # 2. Cache miss — fetch from Google
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
        else:
            # Legacy Places API Photo endpoint
            url = f"{_BASE}/place/photo"
            params = {
                "maxwidth": maxwidth,
                "photo_reference": photo_reference,
                "key": google_maps_key,
            }

        # Reaching here always means a disk-cache miss — photo_cache_service
        # only calls this when it has nothing to serve.
        async with telemetry.track(
            "google_maps", "place_photo",
            sku="place_photo",
            cache_key=f"photo:{photo_reference[:180]}:{maxwidth}",
        ) as t:
            resp = await client.get(url, params=params)
            t.upstream(resp)

        resp.raise_for_status()
        ctype = resp.headers.get("content-type", "image/jpeg")
        photo_bytes = resp.content

    # 3. Cache the photo bytes (7-day TTL = 604800 seconds)
    try:
        import json
        cache_data = json.dumps({
            "data": base64.b64encode(photo_bytes).decode("ascii"),
            "ctype": ctype,
        })
        await place_cache_service.set_raw(cache_key, cache_data, ttl=604800)
    except Exception as e:
        print(f"⚠️ Photo cache SET error: {e}")

    return photo_bytes, ctype


async def fetch_place_details(place_id: str) -> Optional[dict]:
    """Fetch rich place details (reviews, regularOpeningHours, photos, phone, website, price)
    from Google Places API (New) using strict field masking to minimize API billing.
    """
    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ Google Maps API key not configured")
        return None

    # Handle place ID (strip 'places/' if duplicated, then format for API)
    raw_id = place_id.replace("places/", "")
    url = f"https://places.googleapis.com/v1/places/{raw_id}"
    
    field_mask = (
        "id,displayName,formattedAddress,location,rating,userRatingCount,"
        "reviews,regularOpeningHours,photos,internationalPhoneNumber,"
        "websiteUri,editorialSummary,priceLevel"
    )
    headers = {
        "X-Goog-Api-Key": google_maps_key,
        "X-Goog-FieldMask": field_mask,
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            # This field mask includes reviews and opening hours, which is the
            # Enterprise tier rather than Essentials — the priciest way to read
            # a place. Worth watching in the SKU breakdown.
            async with telemetry.track(
                "google_maps", "place_details",
                sku="place_details",
                cache_key=f"pd:{raw_id}",
            ) as t:
                resp = await client.get(url, headers=headers)
                t.upstream(resp)
            resp.raise_for_status()
            data = resp.json()

        # Parse Places API (New) response into normalized dict
        display_name = data.get("displayName", {}).get("text") or "Unknown"
        formatted_address = data.get("formattedAddress") or ""
        loc_data = data.get("location") or {}
        latitude = float(loc_data.get("latitude") or 0.0)
        longitude = float(loc_data.get("longitude") or 0.0)
        rating = float(data.get("rating") or 4.0)
        user_ratings_total = int(data.get("userRatingCount") or 0)
        
        # Reviews (top 5)
        raw_reviews = data.get("reviews") or []
        reviews = []
        for r in raw_reviews[:5]:
            reviews.append({
                "author": r.get("authorAttribution", {}).get("displayName") or "Anonymous",
                "rating": float(r.get("rating") or 5.0),
                "text": r.get("text", {}).get("text") or "",
                "time": r.get("relativePublishTimeDescription") or "",
            })

        # Opening Hours
        hours_data = data.get("regularOpeningHours") or {}
        open_now = hours_data.get("openNow")
        weekday_descriptions = hours_data.get("weekdayDescriptions") or []
        closing_time = None
        if open_now and weekday_descriptions:
            import datetime
            today_idx = datetime.datetime.now().weekday()
            if today_idx < len(weekday_descriptions):
                today_text = weekday_descriptions[today_idx]
                import re
                match = re.search(r"[–-]\s*(.+)$", today_text)
                if match:
                    closing_time = match.group(1).strip()

        # Price Level
        price_level_str = data.get("priceLevel")
        price_map = {
            "PRICE_LEVEL_FREE": "Free",
            "PRICE_LEVEL_INEXPENSIVE": "Inexpensive",
            "PRICE_LEVEL_MODERATE": "Moderate",
            "PRICE_LEVEL_EXPENSIVE": "Expensive",
            "PRICE_LEVEL_VERY_EXPENSIVE": "Very Expensive",
        }
        price_text = price_map.get(price_level_str, "Moderate")

        # Photos (cap at 3)
        photos = data.get("photos") or []
        photo_urls = []
        for ph in photos[:3]:
            ref = ph.get("name")
            if ref:
                photo_urls.append(f"/api/v1/places/photo?ref={ref}")

        # Editorial Summary
        editorial_summary = data.get("editorialSummary", {}).get("text")

        return {
            "id": data.get("id") or place_id,
            "name": display_name,
            "address": formatted_address,
            "latitude": latitude,
            "longitude": longitude,
            "rating": rating,
            "user_ratings_total": user_ratings_total,
            "reviews": reviews,
            "open_now": open_now,
            "open_now_text": "Open" if open_now is True else ("Closed" if open_now is False else None),
            "closing_time": closing_time,
            "weekday_hours": weekday_descriptions,
            "price_level": price_text,
            "photo_urls": photo_urls,
            "phone_number": data.get("internationalPhoneNumber"),
            "website_uri": data.get("websiteUri"),
            "editorial_summary": editorial_summary,
        }
    except Exception as e:
        print(f"⚠️ Error fetching place details from Google Places API (New) for {place_id}: {e}")
        return None
