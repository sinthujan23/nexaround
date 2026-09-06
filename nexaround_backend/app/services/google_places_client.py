"""Thin async client around Google Places + Photos.

Only this module ever sees GOOGLE_API_KEY. The mobile client never receives
the key, never sees a googleapis.com URL.
"""
import asyncio
import math
from typing import Optional
import httpx
from app.core.database import async_session
from app.services.settings_service import SettingsService
from app.services import telemetry


_BASE = "https://maps.googleapis.com/maps/api"

# Shared, connection-pooled client reused by every call in this module instead
# of each one opening (and TLS-handshaking) a brand new connection. Created
# lazily — not at import time — because it binds to whichever event loop is
# running on first use.
_http_client: Optional[httpx.AsyncClient] = None
_http_client_lock = asyncio.Lock()

# Bulkhead: caps how many Google Places/Maps HTTP calls can be in flight at
# once across the whole process. Without this, one cold screen-open can fan
# out 50+ concurrent requests across all bands and categories, which risks
# tripping Google's per-key rate limit (billed retries) and slows down the
# very calls a user is actually waiting on.
_GOOGLE_CALL_CONCURRENCY = 10
_google_call_semaphore = asyncio.Semaphore(_GOOGLE_CALL_CONCURRENCY)


async def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None:
        async with _http_client_lock:
            if _http_client is None:
                _http_client = httpx.AsyncClient(timeout=15.0)
    return _http_client


async def aclose_http_client() -> None:
    """Called once from the app's shutdown hook to release pooled connections."""
    global _http_client
    if _http_client is not None:
        await _http_client.aclose()
        _http_client = None

# The grid `place_cache_service` and the Google Maps proxy both snap coordinates
# to before building a cache key (~500m). Duplicated as a one-liner rather than
# imported so this client keeps its single-direction dependency on settings and
# telemetry only.
_KEY_GRID_DEG = 0.005


def _snap_coord(value: float) -> str:
    return f"{math.floor(value / _KEY_GRID_DEG) * _KEY_GRID_DEG:.4f}"


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
        "cultural_center", "visitor_center", "observation_deck",
        "zoo", "aquarium", "amusement_park", "water_park", "planetarium",
        "performing_arts_theater", "amusement_center"
    ],
    "Attractions": [
        "tourist_attraction", "museum", "park", "zoo", "aquarium", "art_gallery",
        "amusement_park", "national_park", "hiking_area", "beach",
        "historical_landmark", "historical_place", "cultural_landmark",
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
        # `shopping_mall` leads deliberately. It was missing entirely, and a mall
        # carries nothing else this list recognises — One Galle Face is tagged
        # only `shopping_mall, point_of_interest, establishment`, and the two
        # generic tags are stripped before the relevance test. So the largest
        # mall in the country, with 26,685 reviews, was dropped from Shopping,
        # along with 114 of the 142 malls near it. The legacy type map has
        # always searched Shopping as `shopping_mall`; only this list disagreed.
        "shopping_mall", "department_store",
        "supermarket", "store",
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
    # Nature means *nature*, not "outdoors". Google's generic `park` covers
    # children's playgrounds, jogging tracks and cycling parks, which filled this
    # section with Lotus Tower Kids Park and Mahara Jogging Track. Asking only
    # for the specific natural types keeps genuine national parks and reserves
    # (which also carry `park`) while leaving urban recreation behind.
    "Nature": [
        "national_park", "state_park", "beach", "hiking_area",
        "wildlife_refuge", "wildlife_park", "lake", "river",
        "botanical_garden"
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


# Free-text "near me" search subject → single Google Places type (New API).
#
# Deliberately separate from CATEGORY_TYPES_MAP/_CATEGORY_ALIASES above: those
# group many types under one of the app's ~10 browse-tab sections ("Food &
# Drink"), which only resolves if the user's word happens to name a section.
# A search bar has to answer "atm", "bakery", "gym", "parking" too — none of
# which are section names — so this maps individual nouns straight to the one
# Google type that answers them. Every value here already appears verbatim in
# CATEGORY_TYPES_MAP above (so it is already known-valid against Places API
# (New)) or is one of Google's other well-established Table A types.
NEARBY_TERM_TYPES: dict[str, str] = {
    # Finance
    "atm": "atm", "atms": "atm",
    "bank": "bank", "banks": "bank",
    # Fuel & auto
    "gas station": "gas_station", "gas stations": "gas_station",
    "petrol station": "gas_station", "petrol": "gas_station", "fuel station": "gas_station",
    "parking": "parking", "car park": "parking", "parking lot": "parking",
    "car wash": "car_wash",
    "car repair": "car_repair", "mechanic": "car_repair",
    "car rental": "car_rental", "car hire": "car_rental",
    "car dealer": "car_dealer",
    # Food & drink (specific dish/venue types, not the whole section)
    "restaurant": "restaurant", "restaurants": "restaurant",
    "bakery": "bakery", "bakeries": "bakery",
    "cafe": "cafe", "cafes": "cafe", "coffee shop": "cafe", "coffee": "cafe",
    "bar": "bar", "bars": "bar", "pub": "bar", "pubs": "bar",
    "night club": "night_club", "nightclub": "night_club",
    "ice cream": "ice_cream_shop", "ice cream shop": "ice_cream_shop",
    "fast food": "fast_food_restaurant",
    "food court": "food_court",
    # Shopping
    "supermarket": "supermarket", "grocery": "supermarket",
    "groceries": "supermarket", "grocery store": "supermarket",
    "convenience store": "convenience_store",
    "department store": "department_store",
    "electronics store": "electronics_store",
    "hardware store": "hardware_store",
    "market": "market",
    "mall": "shopping_mall", "shopping mall": "shopping_mall",
    "book store": "book_store", "bookstore": "book_store", "books": "book_store",
    "clothing store": "clothing_store", "clothes shop": "clothing_store", "clothes": "clothing_store",
    "jewelry store": "jewelry_store", "jeweller": "jewelry_store", "jewellery": "jewelry_store",
    "shoe store": "shoe_store", "shoes": "shoe_store",
    "furniture store": "furniture_store", "furniture": "furniture_store",
    "pet store": "pet_store", "pet shop": "pet_store",
    "gift shop": "gift_shop",
    # Medical
    "pharmacy": "pharmacy", "pharmacies": "pharmacy", "chemist": "pharmacy", "drugstore": "pharmacy",
    "hospital": "hospital", "hospitals": "hospital",
    "clinic": "medical_clinic", "clinics": "medical_clinic", "medical clinic": "medical_clinic",
    "dentist": "dentist", "dental clinic": "dental_clinic",
    "doctor": "doctor", "doctors": "doctor",
    "physiotherapist": "physiotherapist",
    "vet": "veterinary_care", "veterinary": "veterinary_care", "veterinary clinic": "veterinary_care",
    # Lodging
    "hotel": "lodging", "hotels": "lodging", "motel": "lodging",
    "hostel": "hostel",
    "guest house": "guest_house",
    "campground": "campground", "camping": "campground", "camp site": "campground",
    # Transport
    "bus station": "bus_station", "bus stop": "bus_station",
    "train station": "train_station",
    "subway station": "subway_station", "subway": "subway_station",
    "metro station": "subway_station", "metro": "subway_station",
    "airport": "airport",
    "taxi stand": "taxi_stand", "taxi": "taxi_stand",
    "ferry terminal": "ferry_terminal", "ferry": "ferry_terminal",
    "light rail station": "light_rail_station",
    # Entertainment / leisure
    "museum": "museum", "museums": "museum",
    "zoo": "zoo",
    "aquarium": "aquarium",
    "amusement park": "amusement_park", "theme park": "amusement_park",
    "water park": "water_park",
    "movie theater": "movie_theater", "movie theatre": "movie_theater", "cinema": "movie_theater",
    "bowling alley": "bowling_alley", "bowling": "bowling_alley",
    "casino": "casino",
    "gym": "gym", "gyms": "gym", "fitness center": "gym", "fitness centre": "gym",
    "spa": "spa",
    "golf course": "golf_course", "golf": "golf_course",
    # Worship
    "church": "church", "churches": "church",
    "mosque": "mosque", "mosques": "mosque",
    "temple": "hindu_temple", "hindu temple": "hindu_temple",
    "synagogue": "synagogue",
    "buddhist temple": "buddhist_temple",
    # Services
    "post office": "post_office",
    "police": "police", "police station": "police",
    "fire station": "fire_station",
    "library": "library", "libraries": "library",
    "laundry": "laundry", "laundromat": "laundry",
    "salon": "hair_salon", "hair salon": "hair_salon", "hairdresser": "hair_salon",
    # Nature
    "beach": "beach", "beaches": "beach",
    "national park": "national_park",
    "hiking area": "hiking_area", "hiking trail": "hiking_area", "trail": "hiking_area",
    "lake": "lake",
    "river": "river",
    "botanical garden": "botanical_garden",
    "park": "park", "parks": "park",
}


def resolve_nearby_term(term: str) -> Optional[str]:
    """Map a free-text 'near me' search subject to a single Google Places type.

    Distinct from canonical_category(): that resolves a UI section name ('Food
    & Drink') to a list of types for the browse tabs. This resolves what a user
    actually types into a search box ("atm", "bakery") to the one type that
    answers it. Returns None for anything not in the table (cuisines, brand
    names, free-form phrases) — the caller is expected to fall back to Text
    Search for those, not to search unfiltered.
    """
    return NEARBY_TERM_TYPES.get(term.strip().lower())


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

    client = await _get_http_client()
    # Self-heal: the Places API (New) rejects the WHOLE request with 400 if
    # any single includedType isn't supported (e.g. legacy 'place_of_worship').
    # Strip the type(s) Google names and retry, so the valid types still
    # return results instead of the category coming back empty.
    resp = None
    for _attempt in range(len(included_types) + 1):
        # Tracked per attempt, not per call: the self-heal retry issues a
        # fresh request each time, and each successful one is billed.
        async with _google_call_semaphore:
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
    radius_m: Optional[float] = None,
) -> list[dict]:
    """Call Google Text Search (New). Returns the raw places list (unfiltered).

    `radius_m` narrows the (soft) location bias — omitted, it keeps the
    long-standing 50km bias used by the general search bar; a "near me"
    triggered search passes a tight radius (2-5km) so a term with no exact
    match nearby doesn't surface a same-name result three cities away.
    """
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

    bias_radius = float(min(max(radius_m, 500.0), 50000.0)) if radius_m else 50000.0
    body = {
        "textQuery": query,
        "locationBias": {
            "circle": {
                "center": {
                    "latitude": latitude,
                    "longitude": longitude
                },
                "radius": bias_radius
            }
        }
    }

    client = await _get_http_client()
    async with _google_call_semaphore:
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


async def nearby_search_typed(
    *,
    latitude: float,
    longitude: float,
    place_type: str,
    radius: int,
) -> Optional[list[dict]]:
    """Typed Nearby Search (New) for exactly one Google Places type.

    Backs the free-text "near me" search path for a term resolved via
    `resolve_nearby_term` (atm, bakery, gym, ...) that isn't one of the app's
    ~10 browse-tab sections. Returns None — not [] — when Google rejects
    `place_type` as unsupported, so the caller can fall back to Text Search
    instead of silently treating "unsupported type" the same as "zero nearby".
    Deliberately skips `nearby_search()`'s self-heal-and-retry loop: there is
    only one type here, so a 400 means this call is over, not "drop one and
    retry the rest".
    """
    eff_radius = float(min(max(radius, 1), 50000))

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

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
        "includedTypes": [place_type],
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

    client = await _get_http_client()
    async with _google_call_semaphore:
        async with telemetry.track(
            "google_maps", "nearby_search_typed",
            sku="nearby_search_new",
            cache_key=f"nbt:{latitude:.4f}:{longitude:.4f}:{place_type}:{radius}",
            params=body,
        ) as t:
            resp = await client.post(
                "https://places.googleapis.com/v1/places:searchNearby",
                json=body,
                headers=headers,
            )
            t.upstream(resp)

    if resp.status_code == 400 and _unsupported_types(resp):
        print(f"⚠️ Google type '{place_type}' unsupported for near-me search — falling back to text search")
        return None
    if resp.status_code != 200:
        print(f"❌ Google searchNearby (typed) HTTP {resp.status_code}: {resp.text[:600]}")
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
    """Convert a raw Google place (New API format) into the dict that matches PlaceResponse.

    `category_name`, when given, is trusted only if this specific place's own
    types actually support it. A category search's included-types filter still
    lets off-topic places through occasionally (a sub-group query covers
    several types at once, and Nearby Search itself can spill over), and a
    caller that persists every raw result — not just the ones it renders —
    would otherwise stamp that search's category onto a place that plainly
    isn't one: a mosque returned by a "Nature" query, permanently mislabeled
    Nature the moment it's written to the database. Falls back to deriving the
    category from types, same as when no category was requested at all.
    """
    from datetime import datetime, timezone

    loc = place.get("location") or {}
    plat = float(loc.get("latitude", 0.0))
    plng = float(loc.get("longitude", 0.0))

    display_name = place.get("displayName", {}).get("text") or "Unknown"
    types = list(place.get("types") or [])

    resolved_category = category_name
    if resolved_category:
        from app.services import place_bands
        if not place_bands.is_relevant(resolved_category, types, display_name):
            resolved_category = None
    if not resolved_category:
        resolved_category = _resolve_category_from_types(types)

    photos = place.get("photos") or []
    photo_urls = []
    if photos and photo_url_builder:
        for idx, ph in enumerate(photos[:2]):
            ref = ph.get("name")
            if ref:
                photo_urls.append(photo_url_builder(ref, idx))

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

    client = await _get_http_client()
    async with _google_call_semaphore:
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
    """Convert a raw Google place (Legacy API format) into the dict that matches PlaceResponse.

    See `to_place_dict`'s docstring — same reasoning: `category_name` is only
    trusted when this specific place's types actually support it.
    """
    from datetime import datetime, timezone

    geom = place.get("geometry") or {}
    loc = geom.get("location") or {}
    plat = float(loc.get("lat", 0.0))
    plng = float(loc.get("lng", 0.0))

    display_name = place.get("name") or "Unknown"
    types = list(place.get("types") or [])

    resolved_category = category_name
    if resolved_category:
        from app.services import place_bands
        if not place_bands.is_relevant(resolved_category, types, display_name):
            resolved_category = None
    if not resolved_category:
        resolved_category = _resolve_category_from_types(types)

    photos = place.get("photos") or []
    photo_urls = []
    if photos and photo_url_builder:
        for idx, ph in enumerate(photos[:2]):
            ref = ph.get("photo_reference")
            if ref:
                photo_urls.append(photo_url_builder(ref, idx))

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

    client = await _get_http_client()
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
    async with _google_call_semaphore:
        async with telemetry.track(
            "google_maps", "place_photo",
            sku="place_photo",
            cache_key=f"photo:{photo_reference[:180]}:{maxwidth}",
        ) as t:
            resp = await client.get(url, params=params, timeout=20.0, follow_redirects=True)
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


async def find_place_id_legacy(
    name: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
) -> Optional[str]:
    """Resolve a place name to a Google Place ID via Find Place From Text (Legacy).

    Requests `place_id` and nothing else. That is deliberate: legacy Find Place
    bills by data tier, and asking for only the ID keeps the call in the IDs-Only
    tier instead of pulling in Basic or Atmosphere. It exists so a row seeded
    before `attractions.google_place_id` — which is all 67k of them — can be
    mapped onto its upstream place once and never looked up again.

    `locationbias` is a tight circle rather than a wide one on purpose. The names
    in our table are generic enough ("Dental Care & Implant Centre") that a 50 km
    bias readily matches the wrong branch; the caller passes the stored
    coordinates, which are the same ones Google gave us for that place.
    """
    clean_name = (name or "").strip()
    if not clean_name:
        return None

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ google_maps_api_key not set in admin settings — cannot resolve place id")
        return None

    # Places API (New) Text Search stands in for legacy Find Place, whose quota
    # is capped on this project — an unresolved id meant the detail page fell
    # back to the sparse local row for every attraction predating
    # `google_place_id`. One result is all this needs: it is resolving an
    # identifier, not offering a choice.
    body: dict = {"textQuery": clean_name, "maxResultCount": 1}
    if latitude is not None and longitude is not None:
        # Same tight circle as before, and for the same reason: the stored names
        # are generic enough that a wide bias matches the wrong branch.
        body["locationBias"] = {"circle": {
            "center": {"latitude": latitude, "longitude": longitude},
            "radius": 200.0,
        }}

    # Same shape and same ~500m grid the proxy uses for its own Find Place key,
    # so both paths land in one group in the duplicates panel instead of looking
    # like two unrelated sources of Find Place spend.
    if latitude is not None and longitude is not None:
        bias_key = f"{_snap_coord(latitude)},{_snap_coord(longitude)}"
    else:
        bias_key = ""
    cache_key = f"fpt:{clean_name.lower()}|{bias_key}"

    try:
        client = await _get_http_client()
        async with _google_call_semaphore:
            async with telemetry.track(
                "google_maps", "resolve_place_id",
                sku="find_place_basic",
                cache_key=cache_key,
            ) as t:
                resp = await client.post(
                    "https://places.googleapis.com/v1/places:searchText",
                    json=body,
                    headers={
                        "X-Goog-Api-Key": google_maps_key,
                        "Content-Type": "application/json",
                        "X-Goog-FieldMask": "places.id",
                    },
                )
                t.upstream(resp)
        resp.raise_for_status()
        data = resp.json()

        if "error" in data:
            err = data.get("error") or {}
            print(f"⚠️ Places API (New) text search {err.get('status')}: {err.get('message')}")
            return None

        candidates = data.get("places") or []
        if not candidates:
            return None
        return candidates[0].get("id") or None
    except Exception as e:
        print(f"⚠️ Error resolving place id for {clean_name!r}: {e}")
        return None


# Field mask for destination resolution. Identity + geometry + address
# components only: Places (New) bills by the tier the mask reaches into, and
# every field here sits in Essentials/Pro. Deliberately NOT reusing
# `_DETAILS_FIELD_MASK_NEW`, which pulls reviews/photos/rating from the
# Enterprise+Atmosphere tier — a needless bill when all this needs is
# "which country is this place in, and where".
_GEO_FIELD_MASK = (
    "places.id,places.displayName,places.formattedAddress,"
    "places.location,places.addressComponents,places.types"
)

# Same mask minus addressComponents. Text Search has historically been fussier
# about which fields it will accept than Place Details is; if Google rejects
# the component list we retry without it and read the country off the tail of
# the formatted address instead, which is worth strictly more than nothing.
_GEO_FIELD_MASK_NO_COMPONENTS = (
    "places.id,places.displayName,places.formattedAddress,"
    "places.location,places.types"
)


def _component(place: dict, wanted_type: str) -> tuple[str, str]:
    """(long_text, short_text) of the first address component of a type."""
    for comp in place.get("addressComponents") or []:
        if wanted_type in (comp.get("types") or []):
            return (comp.get("longText") or "", comp.get("shortText") or "")
    return ("", "")


async def resolve_place_geo(
    name: str,
    *,
    bias_lat: Optional[float] = None,
    bias_lng: Optional[float] = None,
    bias_radius_m: float = 50_000.0,
) -> Optional[dict]:
    """Resolve a free-text place name to its identity, country and coordinates.

    One Text Search call. Returns None rather than raising, so a caller can
    always fall back to whatever it does today.

    Unlike `find_place_id_legacy`, the location bias here is optional and wide.
    That function biases to 200 m because it is disambiguating one clinic branch
    from another; this one is identifying a *destination*, where a tight circle
    around a rough coordinate would exclude the very city being named.
    """
    clean_name = (name or "").strip()
    if not clean_name:
        return None

    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ google_maps_api_key not set in admin settings — cannot resolve destination")
        return None

    body: dict = {"textQuery": clean_name, "maxResultCount": 1}
    if bias_lat is not None and bias_lng is not None:
        body["locationBias"] = {"circle": {
            "center": {"latitude": bias_lat, "longitude": bias_lng},
            "radius": float(min(max(bias_radius_m, 1000.0), 50_000.0)),
        }}
        bias_key = f"{_snap_coord(bias_lat)},{_snap_coord(bias_lng)}"
    else:
        bias_key = ""
    cache_key = f"geo:{clean_name.lower()}|{bias_key}"

    async def _post(field_mask: str):
        client = await _get_http_client()
        async with _google_call_semaphore:
            async with telemetry.track(
                "google_maps", "resolve_place_geo",
                sku="text_search_pro",
                cache_key=cache_key,
            ) as t:
                resp = await client.post(
                    "https://places.googleapis.com/v1/places:searchText",
                    json=body,
                    headers={
                        "X-Goog-Api-Key": google_maps_key,
                        "Content-Type": "application/json",
                        "X-Goog-FieldMask": field_mask,
                    },
                )
                t.upstream(resp)
        return resp

    try:
        resp = await _post(_GEO_FIELD_MASK)
        if resp.status_code == 400:
            # Most likely the component list. Retry without it before giving up.
            resp = await _post(_GEO_FIELD_MASK_NO_COMPONENTS)
        resp.raise_for_status()
        data = resp.json()

        if "error" in data:
            err = data.get("error") or {}
            print(f"⚠️ Places geo resolve {err.get('status')}: {err.get('message')}")
            return None

        candidates = data.get("places") or []
        if not candidates:
            return None
        place = candidates[0]

        country_name, country_code = _component(place, "country")
        admin_area, _ = _component(place, "administrative_area_level_1")
        loc = place.get("location") or {}

        return {
            "place_id": place.get("id") or "",
            "name": (place.get("displayName") or {}).get("text") or clean_name,
            "formatted_address": place.get("formattedAddress") or "",
            "latitude": loc.get("latitude"),
            "longitude": loc.get("longitude"),
            "country": country_name,
            "country_code": (country_code or "").upper(),
            "admin_area": admin_area,
            "types": place.get("types") or [],
        }
    except Exception as e:
        print(f"⚠️ Error resolving destination geo for {clean_name!r}: {e}")
        return None


# Fields the detail page renders, named as Places API (New) names them. New
# bills by the tier the mask reaches into, so this is the same bargain the
# legacy `fields` list struck: Essentials/Pro for identity and geometry,
# Enterprise for opening hours, Enterprise+Atmosphere for rating, reviews and
# price. Nothing here is fetched that the page does not draw.
_DETAILS_FIELD_MASK_NEW = (
    "id,displayName,formattedAddress,location,rating,userRatingCount,"
    "reviews,regularOpeningHours,priceLevel,photos"
)

_PRICE_LEVEL_TO_LEGACY = {
    "PRICE_LEVEL_FREE": 0,
    "PRICE_LEVEL_INEXPENSIVE": 1,
    "PRICE_LEVEL_MODERATE": 2,
    "PRICE_LEVEL_EXPENSIVE": 3,
    "PRICE_LEVEL_VERY_EXPENSIVE": 4,
}


def _new_details_to_legacy_result(data: dict) -> dict:
    """Reshape a Places API (New) place into the legacy `result` object.

    The parsing below this was written against legacy and is correct — the
    closing-time regex, the price table, the photo-reference handling. Adapting
    the payload instead of rewriting that keeps the change to the transport.

    One thing survives the move unchanged by luck rather than design, and is
    worth naming: `weekdayDescriptions` starts on Monday exactly as legacy's
    `weekday_text` did, so the `datetime.weekday()` index into it still lines up.
    """
    loc = data.get("location") or {}
    hours = data.get("regularOpeningHours") or {}
    return {
        "place_id": data.get("id") or "",
        "name": (data.get("displayName") or {}).get("text") or "",
        "formatted_address": data.get("formattedAddress") or "",
        "geometry": {"location": {
            "lat": loc.get("latitude"),
            "lng": loc.get("longitude"),
        }},
        "rating": data.get("rating"),
        "user_ratings_total": data.get("userRatingCount"),
        "reviews": [
            {
                "author_name": (r.get("authorAttribution") or {}).get("displayName"),
                "rating": r.get("rating"),
                # `text` is the localised rendering, `originalText` the language
                # it was written in; the page shows whichever exists.
                "text": (r.get("text") or {}).get("text")
                        or (r.get("originalText") or {}).get("text") or "",
                "relative_time_description": r.get("relativePublishTimeDescription"),
            }
            for r in (data.get("reviews") or [])
        ],
        "opening_hours": {
            "open_now": hours.get("openNow"),
            "weekday_text": hours.get("weekdayDescriptions") or [],
        },
        "price_level": _PRICE_LEVEL_TO_LEGACY.get(data.get("priceLevel")),
        # New names a photo `places/X/photos/Y`, which is what /places/photo
        # already accepts and what the media URL is built from downstream.
        "photos": [
            {"photo_reference": ph["name"]}
            for ph in (data.get("photos") or []) if ph.get("name")
        ],
    }


async def fetch_place_details(place_id: str) -> Optional[dict]:
    """Fetch rich place details (reviews, opening_hours, photos) from Places API
    (New), reshaped into the legacy result the parsing below expects.

    Was legacy Place Details until that API's quota was capped on this project
    and every call started returning OVER_QUERY_LIMIT — which is what emptied
    the detail page of its photo, hours and reviews while the name and rating,
    served from our own table, kept rendering.
    """
    async with async_session() as db:
        settings_service = SettingsService(db)
        google_maps_key = await settings_service.get_setting("google_maps_api_key")

    if not google_maps_key:
        print("⚠️ Google Maps API key not configured")
        return None

    # Handle place ID (strip 'places/' if duplicated, then format for API)
    raw_id = place_id.replace("places/", "")

    try:
        client = await _get_http_client()
        async with _google_call_semaphore:
            async with telemetry.track(
                "google_maps", "place_details_rich",
                sku="place_details",
                cache_key=f"pdr:{raw_id}",
            ) as t:
                resp = await client.get(
                    f"https://places.googleapis.com/v1/places/{raw_id}",
                    params={"languageCode": "en"},
                    headers={
                        "X-Goog-Api-Key": google_maps_key,
                        "X-Goog-FieldMask": _DETAILS_FIELD_MASK_NEW,
                    },
                )
                t.upstream(resp)
        resp.raise_for_status()
        data = resp.json()

        if "error" in data:
            err = data.get("error") or {}
            print(f"⚠️ Places API (New) details {err.get('status')}: {err.get('message')}")
            return None

        result = _new_details_to_legacy_result(data)
        if not result.get("place_id"):
            return None

        # Parse Places API (Legacy) response into normalized dict
        display_name = result.get("name") or "Unknown"
        formatted_address = result.get("formatted_address") or ""
        geom = result.get("geometry") or {}
        loc_data = geom.get("location") or {}
        latitude = float(loc_data.get("lat") or 0.0)
        longitude = float(loc_data.get("lng") or 0.0)
        rating = float(result.get("rating") or 4.0)
        user_ratings_total = int(result.get("user_ratings_total") or 0)
        
        # Reviews (top 5)
        raw_reviews = result.get("reviews") or []
        reviews = []
        for r in raw_reviews[:5]:
            reviews.append({
                "author": r.get("author_name") or "Anonymous",
                "rating": float(r.get("rating") or 5.0),
                "text": r.get("text") or "",
                "time": r.get("relative_time_description") or "",
            })

        # Opening Hours
        hours_data = result.get("opening_hours") or {}
        open_now = hours_data.get("open_now")
        weekday_descriptions = hours_data.get("weekday_text") or []
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
        price_level_val = result.get("price_level")
        price_map = {
            0: "Free",
            1: "Inexpensive",
            2: "Moderate",
            3: "Expensive",
            4: "Very Expensive",
        }
        price_text = price_map.get(price_level_val, "Moderate")

        # Photos (cap at 3)
        photos = result.get("photos") or []
        photo_urls = []
        for idx, ph in enumerate(photos[:3]):
            ref = ph.get("photo_reference")
            if ref:
                photo_urls.append(f"/api/v1/places/photo?ref={ref}&i={idx}")

        return {
            "id": result.get("place_id") or place_id,
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
        }
    except Exception as e:
        print(f"⚠️ Error fetching place details from Google Places API (Legacy) for {place_id}: {e}")
        return None
