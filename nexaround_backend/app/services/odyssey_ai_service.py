"""Server-side AI "Odyssey" (trip blueprint) generation via Gemini.

Runs on the backend so the long (20-40s) generative call never depends on the
phone staying in the foreground. The output is shaped to match exactly what the
Flutter app's `Odyssey.fromItinerary` expects: the itinerary `items` list is
`[meta, day, day, ...]` where `meta` carries the trip-level fields and each
`day` carries its activities.
"""
import asyncio
import json
import logging
import re
from dataclasses import dataclass
import urllib.parse
import httpx
from app.services import geo_resolver, telemetry, trip_cost_floor
from app.services.serpapi_service import (
    SerpApiService,
    format_flight_results_for_gemini,
    format_hotel_results_for_gemini,
    extract_hotel_strategies_from_serpapi,
    extract_flight_strategies_from_serpapi,
    rooms_for as serpapi_rooms_for,
)

logger = logging.getLogger(__name__)


def _clean_destination(dest: str) -> str:
    """Deduplicate comma-separated destination tokens (e.g. 'Germany, Germany' -> 'Germany')
    and strip trailing parenthetical annotations (e.g. 'PEN (LCC)' -> 'PEN') — Gemini's
    "route" field sometimes tags an airport code with a note like this, and a free-text
    Google Flights query with a stray "(LCC)" in it can fail to resolve the destination."""
    if not dest:
        return ""
    parts = [
        re.sub(r"\s*\([^)]*\)\s*$", "", p).strip()
        for p in dest.split(",")
    ]
    parts = [p for p in parts if p]
    unique_parts = []
    for p in parts:
        if not any(p.lower() == existing.lower() for existing in unique_parts):
            unique_parts.append(p)
    return ", ".join(unique_parts)


def _build_deep_booking_url(
    provider: str,
    item_name: str,
    destination: str,
    start_date: str,
    end_date: str,
    travelers: int = 1,
    is_flight: bool = False,
    origin_city: str = "",
    airlines: list[str] = None,
) -> str:
    prov_lower = (provider or "").lower()
    dest = _clean_destination(destination)
    if not dest:
        # _clean_destination can strip a route segment down to nothing (e.g. a
        # bare "(LCC)" token) — never let the query end with a blank
        # destination, since Google's free-text flights search then just
        # leaves the "Where to?" field empty instead of failing loudly.
        dest = (destination or "").strip()
    name = (item_name or "").strip()

    # Avoid duplicating destination if item_name already contains destination
    if name and dest and dest.lower() in name.lower():
        query = name
    elif name and dest:
        query = f"{name}, {dest}"
    elif name:
        query = name
    else:
        query = f"hotels in {dest}" if dest else "hotels"

    encoded_query = urllib.parse.quote_plus(query)
    encoded_dest = urllib.parse.quote_plus(dest)

    if is_flight:
        origin = _clean_destination(origin_city)
        if origin.lower() in ["nearest airport", "nearest international airport", "origin", ""]:
            origin = ""

        # Build clean Google Flights query URL
        search_q = f"flights from {origin} to {dest}" if origin else f"flights to {dest}"
        if airlines and len(airlines) > 0:
            search_q += f" with {', '.join(airlines[:2])}"
        if start_date and end_date:
            search_q += f" on {start_date} through {end_date}"
        elif start_date:
            search_q += f" on {start_date}"
        return f"https://www.google.com/travel/flights?q={urllib.parse.quote_plus(search_q)}"
    else:  # Hotel
        # Google Hotels query: use the specific hotel name + destination
        # so Google Hotels opens with the exact hotel from the plan.
        google_hotel_q = query if query else f"hotels in {dest}"
        if "booking" in prov_lower:
            url = f"https://www.booking.com/searchresults.html?ss={encoded_query}"
            if start_date:
                url += f"&checkin={start_date}"
            if end_date:
                url += f"&checkout={end_date}"
            url += f"&group_adults={max(travelers, 1)}"
            return url
        else:
            # Google Hotels as primary fallback
            google_url = f"https://www.google.com/travel/hotels?q={urllib.parse.quote_plus(google_hotel_q)}"
            if start_date and end_date:
                google_url += f"&dates={start_date},{end_date}"
            return google_url

# Gemini Flash models rotate through transient 503 "high demand" — WHICH model
# is overloaded changes minute to minute, so retrying one model isn't enough.
# Try a chain: a 503 on one model falls through to another that's healthy now.
_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-pro",
]
_MODEL = _MODELS[0]  # kept for any external reference / logging

# Budget-scenario multipliers applied through the same waterfall allocation
# used for the "recommended" (as-submitted) budget — gives Minimum/Comfortable
# scenarios without an extra Gemini call.
_SCENARIO_MULTIPLIERS = {"minimum": 0.7, "comfortable": 1.4}

# Hotels are always searched for one standard room, never for the whole party.
#
# Google Hotels prices a *room*, so asking for `adults=6` returns whatever it
# thinks fits six — a family suite, or a filtered set of larger properties —
# and the rate stops meaning anything a caller can multiply. The group cost is
# then derived as rooms x rate (`_rooms_for`), the same reasoning the flight
# search documents for querying one seat at a time.
_STANDARD_ROOM_ADULTS = 2

# "Show only 3-star and above" — the star class every hotel search starts from.
# Google classifies properties 2-5 stars; unclassed guesthouses, hostels and
# apartments carry no class and are excluded by any class filter at all.
_BASE_HOTEL_CLASS = 3

# Nightly spend (USD, one room) above which a trip is treated as able to afford
# 4-star. Set against the 3-star baseline rather than derived: below it the
# floor simply stays at 3, so the number only decides who gets a *stricter*
# search, never who gets a worse one.
_FOUR_STAR_NIGHTLY_USD = 80.0

# Class floors to try in order when a search comes back empty. The traveller
# sees an unclassed property (0 = no class filter) only after 3-star and 2-star
# have both returned nothing for their destination and dates.
_HOTEL_CLASS_FALLBACKS = [3, 2, 0]


def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_SYSTEM = (
    "You are NexAround's expert local travel designer. "
    "You craft realistic, budget-aware, day-by-day trip blueprints. You always "
    "reply with a single JSON object that matches the requested schema exactly - "
    "no markdown, no commentary, no code fences. "
    # A destination whose name resembles somewhere else is the one case where
    # recalling harder makes the answer worse: a trip to Sri Vijaya Puram (the
    # Andamans, India) came back touring Kandy. When the prompt states a
    # country, that country is a fact about the request, not a guess to revise.
    "When a prompt states the destination's country, that country is "
    "authoritative and overrides anything the place name reminds you of. Never "
    "relocate a trip to a different country, however similar the names look."
)


def _days_between(start: str, end: str) -> int:
    """Calculate the number of days between two YYYY-MM-DD date strings."""
    try:
        from datetime import datetime as dt
        s = dt.strptime(start, "%Y-%m-%d")
        e = dt.strptime(end, "%Y-%m-%d")
        return max((e - s).days, 1)
    except Exception:
        return 1


def _to_expedia_date(date_str: str) -> str:
    """Convert YYYY-MM-DD to MM/DD/YYYY for Expedia deep links."""
    try:
        parts = date_str.split("-")
        if len(parts) == 3:
            return f"{parts[1]}/{parts[2]}/{parts[0]}"
    except Exception:
        pass
    return date_str


def build_meta_item(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    days: int,
    nights: int,
    travelers: int = 1,
    summary: str = "",
    budget_split: str = "",
    visa: dict = None,
    logistics: str = "",
    booking_partners: list[dict] = None,
    cover_url: str = "",
    flight_strategies: dict = None,
    hotel_strategies: dict = None,
    start_date: str = "",
    end_date: str = "",
    departure_city: str = "",
    budget_breakdown: dict = None,
    budget_advisory: str = "",
    verified_sources: list[dict] = None,
    verdict: dict = None,
    budget_scenarios: dict = None,
    practical_info: dict = None,
    booking_plan: list[dict] = None,
    legs: list[dict] = None,
    generation_params: dict = None,
    destination_context: dict = None,
    geo_check: dict = None,
) -> dict:
    """The `odyssey_meta` header stored as items[0]. Used both for the initial
    'generating' placeholder and for the finished plan."""
    return {
        "kind": "odyssey_meta",
        "destination": destination,
        # What the destination string actually resolved to, and whether the
        # finished itinerary stayed inside it. Additive keys — the app ignores
        # what it does not know, and the swap endpoint can read the context
        # back out so a replaced activity cannot drift country either.
        "destination_context": destination_context or {},
        "geo_check": geo_check or {},
        "mood": mood,
        "budget": budget,
        "currency": currency,
        "days": days,
        "nights": nights,
        "travelers": travelers,
        "summary": summary,
        "budget_split": budget_split,
        "visa": visa or {},
        "logistics": logistics,
        "booking_partners": booking_partners or [],
        "cover_url": cover_url,
        "flight_strategies": flight_strategies or {},
        "hotel_strategies": hotel_strategies or {},
        "start_date": start_date,
        "end_date": end_date,
        "departure_city": departure_city,
        "budget_breakdown": budget_breakdown or {},
        "budget_advisory": budget_advisory,
        "verified_sources": verified_sources or [],
        "verdict": verdict or {},
        "budget_scenarios": budget_scenarios or {},
        "practical_info": practical_info or {},
        "booking_plan": booking_plan or [],
        # The cities the trip sleeps in, with each leg's nights and dates.
        # Absent on every Odyssey generated before city legs existed, so every
        # reader must treat an empty list as "one leg covering the whole trip"
        # rather than as "no accommodation".
        "legs": legs or [],
        "generation_params": generation_params or {},
    }


async def fetch_unsplash_cover_photo(destination: str, api_key: str) -> str:
    """Query Unsplash for a random landscape orientation photo matching `destination`.
    Returns the regular URL string, or empty string on failure.
    """
    if not api_key:
        return ""
    try:
        url = "https://api.unsplash.com/photos/random"
        params = {
            "query": destination,
            "orientation": "landscape",
            "client_id": api_key,
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            async with telemetry.track(
                "unsplash", "cover_photo_search",
                sku="unsplash_photo", cache_key=f"unsplash:{destination.strip().lower()}",
            ) as t:
                response = await client.get(url, params=params)
                t.upstream(response)
            if response.status_code == 200:
                data = response.json()
                if isinstance(data, dict):
                    urls = data.get("urls") or {}
                    return str(urls.get("regular") or "")
            else:
                logger.error(f"Unsplash API returned status code {response.status_code}: {response.text}")
    except Exception as e:
        logger.error(f"Failed to fetch cover photo from Unsplash: {e}")
    return ""


# SerpApi's google_flights engine rejects free-text places outright —
# `departure_id` must be an uppercase 3-letter code (or a Google /m/ id).
# Passing city names, as this service did, meant every live flight search
# 400'd and silently fell through to Gemini estimation, so the "real data"
# path almost never ran. Codes are resolved before the search now.
#
# Multi-airport cities are listed as comma-separated codes, which the engine
# accepts and searches together. IATA *metro* codes (LON, NYC, PAR) are NOT
# accepted — "LON" returns zero results where "LHR,LGW,STN,LTN" returns
# twenty-plus across all three airports. That comparison is what surfaces
# "Gatwick is cheaper than Heathrow" with a real price attached.
_AIRPORT_CODES = {
    # Multi-airport cities — every airport serving the city, searched together
    "london": "LHR,LGW,STN,LTN", "new york": "JFK,EWR,LGA",
    "new york city": "JFK,EWR,LGA", "paris": "CDG,ORY,BVA",
    "tokyo": "HND,NRT", "milan": "MXP,LIN,BGY", "rome": "FCO,CIA",
    "moscow": "SVO,DME,VKO", "buenos aires": "EZE,AEP",
    "rio de janeiro": "GIG,SDU", "sao paulo": "GRU,CGH",
    "são paulo": "GRU,CGH", "washington": "IAD,DCA,BWI",
    "washington dc": "IAD,DCA,BWI", "chicago": "ORD,MDW",
    "toronto": "YYZ,YTZ", "beijing": "PEK,PKX", "shanghai": "PVG,SHA",
    "seoul": "ICN,GMP", "osaka": "KIX,ITM", "stockholm": "ARN,BMA,NYO",
    "berlin": "BER", "belfast": "BFS,BHD", "jakarta": "CGK,HLP",
    "tehran": "IKA,THR",
    # South Asia
    "colombo": "CMB", "kandy": "CMB", "galle": "CMB", "jaffna": "CMB",
    "kinniya": "CMB", "trincomalee": "CMB", "negombo": "CMB",
    "sri lanka": "CMB", "male": "MLE", "maldives": "MLE",
    "delhi": "DEL", "new delhi": "DEL", "mumbai": "BOM", "bombay": "BOM",
    "bangalore": "BLR", "bengaluru": "BLR", "chennai": "MAA", "madras": "MAA",
    "kolkata": "CCU", "calcutta": "CCU", "hyderabad": "HYD", "kochi": "COK",
    "cochin": "COK", "goa": "GOI", "ahmedabad": "AMD", "trivandrum": "TRV",
    "thiruvananthapuram": "TRV", "kathmandu": "KTM", "dhaka": "DAC",
    "karachi": "KHI", "lahore": "LHE", "islamabad": "ISB",
    "pune": "PNQ", "jaipur": "JAI", "varanasi": "VNS", "amritsar": "ATQ",
    "srinagar": "SXR", "leh": "IXL", "lucknow": "LKO", "guwahati": "GAU",
    # Andaman & Nicobar. Port Blair was renamed Sri Vijaya Puram in 2024, and
    # the new name reads as Sri Lankan to a model — a tester's Andaman trip was
    # routed to CMB and given a Kandy itinerary. Both spellings are pinned here
    # so the resolution never reaches the LLM guess that produced that.
    "port blair": "IXZ", "sri vijaya puram": "IXZ", "andaman": "IXZ",
    "andamans": "IXZ", "andaman islands": "IXZ",
    "andaman and nicobar islands": "IXZ", "andaman & nicobar islands": "IXZ",
    "havelock island": "IXZ", "swaraj dweep": "IXZ",
    "neil island": "IXZ", "shaheed dweep": "IXZ",
    # South-East & East Asia
    "singapore": "SIN", "kuala lumpur": "KUL", "bangkok": "BKK",
    "phuket": "HKT", "chiang mai": "CNX", "hanoi": "HAN",
    "ho chi minh city": "SGN", "saigon": "SGN", "bali": "DPS",
    "denpasar": "DPS", "manila": "MNL", "hong kong": "HKG", "taipei": "TPE",
    "guangzhou": "CAN", "shenzhen": "SZX", "phnom penh": "PNH",
    "siem reap": "SAI", "yangon": "RGN",
    # Kyoto has no airport of its own — Kansai and Itami both serve it.
    "kyoto": "KIX,ITM",
    # Middle East
    "dubai": "DXB", "abu dhabi": "AUH", "doha": "DOH", "sharjah": "SHJ",
    "muscat": "MCT", "riyadh": "RUH", "jeddah": "JED", "kuwait": "KWI",
    "bahrain": "BAH", "manama": "BAH", "amman": "AMM", "beirut": "BEY",
    "tel aviv": "TLV", "istanbul": "IST", "baku": "GYD",
    # Europe
    "amsterdam": "AMS", "frankfurt": "FRA", "munich": "MUC", "madrid": "MAD",
    "barcelona": "BCN", "lisbon": "LIS", "porto": "OPO", "dublin": "DUB",
    "edinburgh": "EDI", "manchester": "MAN", "birmingham": "BHX",
    "glasgow": "GLA", "brussels": "BRU", "zurich": "ZRH", "geneva": "GVA",
    "vienna": "VIE", "prague": "PRG", "budapest": "BUD", "warsaw": "WAW",
    "copenhagen": "CPH", "oslo": "OSL", "helsinki": "HEL", "athens": "ATH",
    "venice": "VCE", "florence": "FLR", "naples": "NAP", "nice": "NCE",
    "hamburg": "HAM", "dusseldorf": "DUS", "cologne": "CGN",
    "reykjavik": "KEF", "bucharest": "OTP", "sofia": "SOF", "zagreb": "ZAG",
    # Americas
    "los angeles": "LAX", "san francisco": "SFO", "miami": "MIA",
    "boston": "BOS", "seattle": "SEA", "atlanta": "ATL", "dallas": "DFW",
    "houston": "IAH", "denver": "DEN", "las vegas": "LAS", "orlando": "MCO",
    "vancouver": "YVR", "montreal": "YUL", "calgary": "YYC",
    "mexico city": "MEX", "cancun": "CUN", "bogota": "BOG", "lima": "LIM",
    "santiago": "SCL",
    # Africa & Oceania
    "cairo": "CAI", "nairobi": "NBO", "johannesburg": "JNB",
    "cape town": "CPT", "casablanca": "CMN", "addis ababa": "ADD",
    "lagos": "LOS", "accra": "ACC", "dar es salaam": "DAR",
    "zanzibar": "ZNZ", "mauritius": "MRU", "seychelles": "SEZ",
    "sydney": "SYD", "melbourne": "MEL", "brisbane": "BNE", "perth": "PER",
    "auckland": "AKL", "wellington": "WLG", "christchurch": "CHC",
}

_AIRPORT_CODE_RE = re.compile(r"^[A-Z]{3}(,[A-Z]{3})*$")

# Strings the app sends when it has no answer, not places anyone can fly to.
# The planner falls back to the literal word "Nearby" when a GPS reverse-geocode
# fails, and that reached the airport resolver as if it were a city: asked
# "which airports serve Nearby?", the model does not decline — it answered MAA,
# and a traveller in Trincomalee was quoted a flight from Chennai. A model will
# always produce a plausible airport, so the guard has to be here, before it.
_NON_PLACE_TOKENS = {
    "nearby", "unknown", "current location", "my location", "your location",
    "n/a", "na", "none", "null", "-", "somewhere", "here",
}


def _is_non_place(text: str) -> bool:
    return (text or "").strip().lower() in _NON_PLACE_TOKENS


def _country_fallback_code(country: str) -> str:
    """The country's own airport, for when the city could not be resolved.

    A last resort, deliberately consulted only after the place itself has
    failed: "Sri Lanka" -> CMB is the right answer for an unknown Sri Lankan
    town, but it would be the wrong answer for Kandy, which has its own entry.
    """
    c = (country or "").strip().lower()
    if not c or _is_non_place(c):
        return ""
    return _AIRPORT_CODES.get(c, "")

# IATA metropolitan codes. Google Flights returns nothing for these, so they
# must never reach a search — they are expanded via _AIRPORT_CODES instead.
# (BER and SHA are deliberately absent — both are real operating airports.)
_METRO_CODES = {
    "LON", "NYC", "PAR", "TYO", "MIL", "ROM", "MOW", "BUE", "RIO", "SAO",
    "WAS", "CHI", "YTO", "BJS", "SEL", "OSA", "STO", "JKT", "TCI",
    "BHZ", "QDU", "REK", "DTT",
}

# Gemini-resolved codes, kept for the life of the process. Airport codes do
# not change, and the same routes recur constantly.
_airport_code_cache: dict[str, str] = {}


async def _verify_airport_codes(
    codes: list[str],
    latitude: float | None,
    longitude: float | None,
    country_code: str,
    *,
    max_km: float = 1000.0,
    budget=None,
) -> list[str]:
    """Drop airports that are not where the trip is.

    Runs only on the guessed path. A model asked which airport serves an
    unfamiliar place will confidently name a real one in the wrong country —
    that is exactly how an Andaman trip got a bookable Colombo flight, with a
    genuine price attached, which is far harder for a traveller to spot than an
    obvious error.

    Anything that cannot be checked is KEPT. An unavailable Places API must not
    be able to delete a correct airport; the check only removes what it has
    positively disproved.
    """
    kept: list[str] = []
    for code in codes:
        check = await geo_resolver.verify_place(
            f"{code} airport",
            near=geo_resolver.DestinationContext(
                query=code, country_code=country_code,
                latitude=latitude, longitude=longitude,
            ),
            max_km=max_km if latitude is not None else None,
            budget=budget,
        )
        if check.checked and not check.ok:
            logger.warning(
                "Rejecting airport %s: resolved to %s (%s), %s km from the destination.",
                code, check.resolved_name or "?", check.country_code or "?",
                f"{check.distance_km:.0f}" if check.distance_km is not None else "?",
            )
            continue
        kept.append(code)
    return kept


async def _resolve_airport_code(
    place: str,
    country: str,
    api_key: str,
    *,
    latitude: float | None = None,
    longitude: float | None = None,
    country_code: str = "",
    budget=None,
) -> str:
    """Resolve a place name to an IATA code SerpApi will accept.

    Static table first (free and instant, covers the common routes), then one
    small Gemini lookup for anything unknown, cached per process. Returns ""
    when nothing usable comes back, which tells the caller to skip the live
    search rather than burn a SerpApi credit on a request that will 400.
    """
    raw = (place or "").strip()
    if not raw:
        return _country_fallback_code(country)

    # A placeholder is not a place. Fall through to the country, which is
    # sometimes still known, rather than asking a model to name its airport.
    if _is_non_place(raw):
        logger.info(
            "Departure/destination %r is a placeholder, not a place — "
            "falling back to the country (%r).", raw, country,
        )
        return _country_fallback_code(country)

    # A city we know wins over anything else — "London" must expand to its
    # four airports rather than being taken at face value.
    key = raw.lower().split(",")[0].strip()
    if key in _AIRPORT_CODES:
        return _AIRPORT_CODES[key]

    # A renamed city is the same airport under either name. Port Blair became
    # Sri Vijaya Puram in 2024; whichever the traveller typed, the answer is
    # IXZ, and letting this fall through to the model is what produced CMB.
    for alias in geo_resolver.aliases_for(key):
        if alias in _AIRPORT_CODES:
            return _AIRPORT_CODES[alias]

    # Already a code (or comma-separated codes), or a "City (CMB)" string.
    upper = raw.upper().replace(" ", "")
    if _AIRPORT_CODE_RE.match(upper) and not any(
        c in _METRO_CODES for c in upper.split(",")
    ):
        return upper
    bracketed = re.search(r"\(([A-Z]{3})\)", raw)
    if bracketed and bracketed.group(1) not in _METRO_CODES:
        return bracketed.group(1)

    cache_key = f"{key}|{(country or '').lower().strip()}"
    if cache_key in _airport_code_cache:
        return _airport_code_cache[cache_key]

    if not api_key:
        return ""

    location = f"{raw}, {country}" if country else raw
    # The destination used to reach this prompt as a bare name with country="",
    # while the origin got its country. "Sri Vijaya Puram" alone reads as Sri
    # Lankan, and the answer came back CMB — a real airport, 1500 km from the
    # trip. Anything we resolved goes in, and "NONE" is an allowed answer.
    where = f'"{location}"'
    if latitude is not None and longitude is not None:
        where += f" at coordinates {latitude:.4f}, {longitude:.4f}"
    country_rule = ""
    if country:
        country_rule = (
            f'The airport MUST be in {country}. If the nearest airport is in a '
            f'different country, answer NONE. '
        )
    prompt = (
        f'Which airports serve {where}? Answer with IATA airport codes ONLY, '
        f"comma-separated, most important first, maximum 3. If the city has several airports "
        f"list them all (e.g. London -> LHR,LGW,STN). If the place has no airport of its own, "
        f"give the nearest major international airport. {country_rule}"
        f"Never answer with a metropolitan area "
        f"code such as LON or NYC. No other text."
    )
    try:
        text, _ = await _call_gemini(prompt, api_key, max_tokens=32, thinking_budget=0)
        codes = re.findall(r"\b([A-Z]{3})\b", (text or "").upper())
        # Metro codes are silently rejected by Google Flights — drop any that
        # slipped through rather than shipping a search that returns nothing.
        codes = [c for c in dict.fromkeys(codes) if c not in _METRO_CODES][:3]
        # Only the model's answers are verified — the static table above is
        # curated, and the live SerpApi path never reaches here at all.
        if codes and country_code:
            codes = await _verify_airport_codes(
                codes, latitude, longitude, country_code, budget=budget,
            )
        if codes:
            code = ",".join(codes)
            _airport_code_cache[cache_key] = code
            logger.info("Resolved airport code for '%s' -> %s", location, code)
            return code
    except Exception as e:
        logger.warning(f"Airport code lookup failed for '{location}': {e}")

    # Nothing usable from the model either. The country's main airport beats
    # returning nothing, which would skip the flight search altogether.
    fallback = _country_fallback_code(country)
    if fallback:
        logger.info(
            "Falling back to the country airport for '%s' -> %s", location, fallback,
        )
    return fallback


def _derive_return_date(start_date: str, days: int) -> str:
    """Best-effort return date so a round trip is priced as a round trip.

    Without a return date SerpApi drops to type=2 and Google quotes a one-way
    fare, which then reaches the traveller with nothing marking it as one-way.
    """
    if not start_date or not days or days <= 0:
        return ""
    try:
        from datetime import date as _date, timedelta as _timedelta
        start = _date.fromisoformat(start_date[:10])
        return (start + _timedelta(days=max(days - 1, 1))).isoformat()
    except Exception:
        return ""


def _enforce_route_destination(data: dict, dest_code: str, origin_code: str = "") -> dict:
    """Rewrite each strategy's `route` to the airports we actually resolved.

    Only touches the AI-estimate path: on the live SerpApi path the route is
    built from the flight legs Google returned, so it is already correct. The
    model, by contrast, invents this string, and it is the string the booking
    link and the Flights card are both read from — so a wrong arrival airport
    there is visible and clickable. Codes we resolved beat codes it imagined.
    """
    strategies = data.get("strategies")
    if not isinstance(strategies, list) or not dest_code:
        return data

    dest_first = dest_code.split(",")[0].strip().upper()
    origin_first = (origin_code or "").split(",")[0].strip().upper()
    for strat in strategies:
        if not isinstance(strat, dict):
            continue
        route_str = str(strat.get("route") or "")
        parts = [p.strip() for p in route_str.replace("->", "→").split("→") if p.strip()]
        left = origin_first or (parts[0].upper() if parts else "")
        if not left:
            continue
        strat["route"] = f"{left} → {dest_first}"
    return data


def _apply_flight_booking_urls(
    data: dict,
    *,
    departure_city: str,
    destination: str,
    flight_start_date: str,
    flight_end_date: str,
    travelers: int,
) -> dict:
    """Force Google Flights as provider and build a deep search URL per strategy."""
    strategies = data.get("strategies")
    if not isinstance(strategies, list):
        return data

    for strat in strategies:
        if not isinstance(strat, dict):
            continue

        airlines = strat.get("airlines")
        if isinstance(airlines, str):
            strat["airlines"] = [a.strip() for a in airlines.split(",") if a.strip()]
        elif not isinstance(airlines, list):
            strat["airlines"] = []
        else:
            strat["airlines"] = [str(a) for a in airlines]

        # Extract origin & destination airport/city from route (e.g. "CMB → LHR").
        #
        # Only a well-formed IATA code is trusted here. On the AI-estimate path
        # the model writes this field freehand, and a hallucinated arrival
        # airport used to flow straight into the booking link — an Andaman trip
        # whose route said "COK → CMB" produced a Google Flights search for
        # Colombo. Anything that is not a code falls back to the real
        # destination, which is resolved rather than generated.
        route_str = str(strat.get("route") or "")
        route_origin = departure_city
        route_dest = destination
        if route_str:
            r_parts = [p.strip() for p in route_str.replace("->", "→").split("→") if p.strip()]
            if r_parts and _AIRPORT_CODE_RE.match(r_parts[0].upper()):
                route_origin = r_parts[0].upper()
            if len(r_parts) > 1 and _AIRPORT_CODE_RE.match(r_parts[-1].upper()):
                route_dest = r_parts[-1].upper()

        strat["provider_name"] = "Google Flights"
        strat["booking_url"] = _build_deep_booking_url(
            provider="Google Flights",
            item_name=strat.get("title") or destination,
            destination=route_dest,
            start_date=flight_start_date,
            end_date=flight_end_date,
            travelers=travelers,
            is_flight=True,
            origin_city=route_origin,
        )
    return data


async def _add_flight_prose(
    data: dict,
    *,
    departure_city: str,
    destination: str,
    api_key: str,
) -> dict:
    """Ask Gemini for copy only — never for numbers.

    The itineraries are already priced from live data by the time this runs.
    Gemini rewrites title/description/tip so the cards read naturally; every
    numeric field is left exactly as SerpApi reported it. Any failure here is
    swallowed and the templated copy stands — prose must never block prices.
    """
    strategies = data.get("strategies") or []
    if not strategies or not api_key:
        return data

    facts = []
    for s in strategies:
        facts.append(
            f'- tier "{s.get("tier")}": {s.get("route")}, {", ".join(s.get("airlines") or []) or "multiple carriers"}, '
            f'{s.get("stops")} stop(s), {s.get("total_duration") or "duration n/a"} outbound'
        )

    prompt = f"""Write short marketing copy for {len(strategies)} flight options from "{departure_city}" to "{destination}".

The options (already priced and verified from live Google Flights data):
{chr(10).join(facts)}

STRICT RULES:
- Do NOT output any price, currency amount, percentage, duration, or airline name that is not listed above.
- Do NOT invent or restate prices. The app renders prices itself.
- "title": 3-6 words naming the option's character (e.g. "Cheapest Fare", "Fastest Non-Stop").
- "description": one sentence, max 25 words, describing the routing experience.
- "tip": one short practical booking tip, max 18 words.

Return ONLY JSON:
{{"copy": [{{"tier": "minimum", "title": "...", "description": "...", "tip": "..."}}]}}"""

    try:
        text, _ = await _call_gemini(prompt, api_key, max_tokens=1024, thinking_budget=0)
        parsed = _parse_json(text)
        by_tier = {
            str(c.get("tier")): c
            for c in (parsed.get("copy") or [])
            if isinstance(c, dict) and c.get("tier")
        }
        for s in strategies:
            c = by_tier.get(str(s.get("tier")))
            if not c:
                continue
            for field in ("title", "description", "tip"):
                value = str(c.get(field) or "").strip()
                if value:
                    s[field] = value
    except Exception as e:
        logger.warning(f"Flight prose pass failed, keeping templated copy: {e}")

    return data


def _structure_ai_flight_strategies(
    data: dict,
    *,
    currency: str,
    travelers: int,
    outbound_date: str,
    return_date: str,
) -> dict:
    """Attach the structured price contract to Gemini-estimated strategies.

    Used only on the fallback path (no SerpApi). The numbers are model
    estimates, so they are tagged is_live_price=False and the app marks them
    as estimated rather than presenting them as quoted fares.
    """
    strategies = data.get("strategies")
    if not isinstance(strategies, list) or not strategies:
        return data

    party = max(int(travelers or 1), 1)
    trip_type = "round_trip" if return_date else "one_way"

    priced = []
    for s in strategies:
        if not isinstance(s, dict):
            continue
        bounds = _extract_price_bounds(s.get("estimated_price_range"))
        if not bounds:
            continue
        low, high = bounds
        per_traveler = round((low + high) / 2, 2)
        s["price_per_traveler"] = per_traveler
        s["price_total"] = round(per_traveler * party, 2)
        s["currency"] = currency.upper()
        s["price_basis"] = "per_traveler"
        s["trip_type"] = trip_type
        s["outbound_date"] = outbound_date
        s["return_date"] = return_date
        s["is_live_price"] = False
        s["price_source"] = "ai_estimate"
        s["travelers"] = party
        priced.append(s)

    # Tier by price rank — distinct strategies, cheapest to dearest.
    priced.sort(key=lambda s: s["price_per_traveler"])
    if len(priced) == 1:
        priced[0]["tier"] = "recommended"
    elif len(priced) == 2:
        priced[0]["tier"] = "minimum"
        priced[1]["tier"] = "comfortable"
    elif priced:
        priced[0]["tier"] = "minimum"
        priced[-1]["tier"] = "comfortable"
        priced[len(priced) // 2]["tier"] = "recommended"

    cheapest = priced[0]["price_per_traveler"] if priced else 0
    dearest = priced[-1]["price_per_traveler"] if priced else 0
    if cheapest > 0 and (dearest - cheapest) / cheapest < 0.15:
        logger.warning(
            "AI flight tiers are within 15%% of each other (%s-%s %s) — tiers will "
            "look near-identical to the traveller.", cheapest, dearest, currency,
        )

    return data


async def generate_flight_strategies(
    *,
    departure_city: str,
    departure_country: str,
    destination: str,
    days: int,
    budget: float,
    currency: str,
    travelers: int,
    flight_start_date: str = "",
    flight_end_date: str = "",
    api_key: str,
    serpapi_key: str = "",
    destination_geo=None,
    geo_budget=None,
    departure_latitude: float | None = None,
    departure_longitude: float | None = None,
) -> dict:
    """Generates tiered flight strategies from live SerpApi Google Flights data.

    Primary path mirrors generate_hotel_strategies' "Option A": SerpApi results
    are turned straight into Minimum / Recommended / Comfortable itineraries by
    extract_flight_strategies_from_serpapi, with no LLM in the pricing path.
    Gemini is then handed the already-priced itineraries and asked for prose
    only.

    Every price returned by either path is **per traveller, round trip when a
    return date is known, in `currency`** — the convention documented in
    trip_cost_floor.py. `price_total` is always derived from it.

    Falls back to Gemini-estimated pricing only when SerpApi is unavailable or
    returns nothing usable.
    """
    real_data_context = ""

    outbound_date = flight_start_date
    return_date = flight_end_date or _derive_return_date(flight_start_date, days)

    # Resolve airport codes up front, independent of whether SerpApi is even
    # configured — Sri Lanka (and other small countries with essentially one
    # commercial gateway) map every city to the same code in _AIRPORT_CODES
    # (e.g. "kinniya" and "colombo" both -> "CMB"). That's deliberate: there is
    # no real domestic flight route between them. Searching CMB->CMB reliably
    # returns nothing and used to fall through to the Gemini-only estimation
    # prompt below, which — having no idea the two cities share an airport —
    # would invent a plausible-sounding "flight" on a real-but-impractical
    # small airfield (e.g. a military/charter strip with no scheduled
    # passenger service), complete with a fabricated price and a booking link
    # that leads nowhere. Bailing out here with no strategies at all (hiding
    # the Flights tab) is the honest answer for a pair with no real route.
    # The app sends the literal word "Nearby" when its reverse geocode fails,
    # and that used to reach the resolver as if it were a city. If the name is
    # unusable but we have the point it came from, recover at least the country
    # so the origin lands in the right one — a traveller in Trincomalee should
    # depart CMB, not the MAA a model volunteered for "Nearby".
    dep_country = departure_country
    if (_is_non_place(departure_city) or not departure_city.strip()) and (
        _is_non_place(departure_country) or not departure_country.strip()
    ):
        if departure_latitude is not None and departure_longitude is not None:
            name, code = await geo_resolver.country_from_coordinates(
                departure_latitude, departure_longitude, budget=geo_budget,
            )
            if name or code:
                dep_country = name or code
                logger.info(
                    "Departure %r was unusable; coordinates resolved it to %s.",
                    departure_city, dep_country,
                )

    # The destination used to be resolved with country="" while the origin got
    # its country — the asymmetry that let an Andaman trip resolve to Colombo.
    # Anything we know about the destination goes in on the same footing.
    _dgeo = destination_geo
    origin_code, dest_code = await asyncio.gather(
        _resolve_airport_code(
            departure_city, dep_country, api_key,
            latitude=departure_latitude, longitude=departure_longitude,
        ),
        _resolve_airport_code(
            destination,
            (_dgeo.country if _dgeo is not None and _dgeo.resolved else ""),
            api_key,
            latitude=(_dgeo.latitude if _dgeo is not None else None),
            longitude=(_dgeo.longitude if _dgeo is not None else None),
            country_code=(_dgeo.country_code if _dgeo is not None else ""),
            budget=geo_budget,
        ),
    )
    if origin_code and dest_code and set(origin_code.split(",")) & set(dest_code.split(",")):
        logger.info(
            "No distinct flight route: '%s' and '%s' both resolve to %s — "
            "skipping flight generation.",
            departure_city, destination, origin_code,
        )
        return {}

    # An endpoint we could not resolve is not an endpoint a model should be
    # asked to guess. Without SerpApi every flight comes from the estimation
    # prompt below, and that prompt will always name *some* airport: asked to
    # fly from "Nearby" it answered MAA, and the traveller got a plausible
    # Chennai fare with a real-looking price. No Flights tab is the honest
    # outcome, and the one the reporter would rather have seen.
    if not origin_code or not dest_code:
        logger.warning(
            "Skipping flight generation: unresolved route (departure=%r -> %s, "
            "destination=%r -> %s).",
            departure_city, origin_code or "?", destination, dest_code or "?",
        )
        return {}

    # ── Primary path: SerpApi direct extraction ──────────────────────────────
    if serpapi_key and origin_code and dest_code:
        try:
            logger.info(
                "Fetching live flight data via SerpApi (Google Flights) %s → %s...",
                origin_code, dest_code,
            )
            serp = SerpApiService(serpapi_key)
            serp_result = await serp.search_flights(
                departure_city=origin_code,
                destination=dest_code,
                outbound_date=outbound_date,
                return_date=return_date,
                # One adult: keeps the returned fare unambiguously per-traveller.
                # The group total is derived, never read back from Google.
                adults=1,
                currency=currency,
            )

            direct = extract_flight_strategies_from_serpapi(
                serp_result,
                departure_city=departure_city,
                destination=destination,
                currency=currency,
                outbound_date=outbound_date,
                return_date=return_date,
                travelers=travelers,
            )

            if direct.get("strategies"):
                logger.info(
                    "SerpAPI produced %d live flight tiers for %s → %s",
                    len(direct["strategies"]), departure_city, destination,
                )
                direct = await _add_flight_prose(
                    direct,
                    departure_city=departure_city,
                    destination=destination,
                    api_key=api_key,
                )
                return _apply_flight_booking_urls(
                    direct,
                    departure_city=departure_city,
                    destination=destination,
                    flight_start_date=outbound_date,
                    flight_end_date=return_date,
                    travelers=travelers,
                )

            logger.warning(
                "SerpAPI returned no usable flight options for %s → %s; "
                "falling back to Gemini estimation.", departure_city, destination,
            )
            real_data_context = format_flight_results_for_gemini(
                serp_result, departure_city, destination, currency
            )
        except Exception as e:
            logger.warning(f"SerpApi flight search failed, falling back to Gemini knowledge: {e}")

    # ── Fallback path: Gemini estimation ─────────────────────────────────────
    date_str = ""
    if outbound_date and return_date:
        date_str = f"- Departure Date: {outbound_date}\n- Return Date: {return_date}"

    real_data_prompt_section = ""
    if real_data_context:
        real_data_prompt_section = f"""
LIVE GOOGLE FLIGHTS SEARCH RESULTS:
{real_data_context}

INSTRUCTION: Base your strategies on the real Google Flights data above. Extract the exact departure/arrival airport codes, actual airlines, actual durations, and real price ranges.
"""

    trip_basis = "round trip (outbound AND return)" if return_date else "one way"

    # Every worked example below used to be hard-coded "CMB → KUL". Five
    # Colombo literals in one prompt is a standing nudge toward Sri Lanka, and
    # an Andaman trip duly came back routed to CMB. Seed the examples with the
    # codes actually resolved for THIS trip; fall back to obviously-fake
    # placeholders rather than any real airport when nothing resolved.
    ex_o = (origin_code.split(",")[0].strip().upper() if origin_code else "AAA")
    ex_d = (dest_code.split(",")[0].strip().upper() if dest_code else "BBB")
    ex_route = f"{ex_o} → {ex_d}"

    prompt = f"""Analyze flight options for a trip from "{departure_city}" ({departure_country}) to "{destination}".
The travelers want to find the cheapest flight options.

Trip Details:
- Departure: {departure_city}, {departure_country}
- Destination: {destination}
{date_str}
- Duration: {days} days
- Group Size: {travelers} traveler(s)
- Total Trip Budget: {int(budget)} {currency} (flights should fit or be optimized against this)
{real_data_prompt_section}
Your task is to act as an agentic flight finder. Propose exactly 3 distinct, realistic flight strategies spanning clearly different price
points: a cheapest option, a mid-priced best-value option, and a premium fastest/fewest-stops
option. The cheapest and the premium option MUST differ by at least 15% in price.
These can be:
- "direct": Direct flight option (if available) or standard single-carrier route.
- "budget_carrier": Utilizing low-cost carriers (e.g. AirAsia, Scoot, Ryanair, IndiGo, FitsAir, Southwest, etc. depending on region).
- "split_ticket": Booking separate tickets to save money.
- "nearby_airport": Flying into or out of a nearby airport.

IMPORTANT RULES:
- In the "route" field, always use real IATA airport codes. The route MUST be "{ex_route}" — {ex_o} is the airport for "{departure_city}" and {ex_d} is the airport for "{destination}". If a city has no airport of its own, its nearest major airport is already reflected in those codes.
- The arrival airport MUST be {ex_d}. Never route to an airport in a different country from "{destination}", however similar the names look.
- provider_name MUST be "Google Flights" for all strategies.
- PRICE BASIS (critical): every "estimated_price_range" is the fare for ONE traveller for the
  ENTIRE {trip_basis} journey, in {currency}, taxes and fees included. Never quote a group
  total. Never quote a single leg of a return trip.
- EVERY strategy in the array MUST have its own non-empty "estimated_price_range". Do not leave price fields blank on any strategy other than the first — all 2-4 strategies are shown to the user and all must display a price.

Field Rules:
- "title": Concise 3-6 word strategy name.
- "provider_name": MUST be "Google Flights".
- "estimated_savings": Very short tag under 4 words (e.g., "Save ~20%").
- "estimated_price_range": Short price string only (e.g., "USD 180 - 300"). REQUIRED on every strategy.
- "route": Short IATA airport code route — use exactly "{ex_route}".
- "convenience": Star rating string ONLY (e.g., "★★★☆☆").
- "tip": Short booking tip.
- "booking_url": Leave empty, will be generated server-side.

Return ONLY a JSON object with this exact shape (note every strategy has a price filled in):
{{
  "departure_city": "{departure_city}",
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "strategy": "direct",
      "title": "Direct Flight via Google Flights",
      "provider_name": "Google Flights",
      "description": "Description of route and strategy.",
      "estimated_savings": "Save ~15%",
      "estimated_price_range": "{currency} 200 - 400",
      "airlines": ["Airline A", "Airline B"],
      "route": "{ex_route}",
      "stops": 0,
      "total_duration": "4h 30m",
      "convenience": "★★★★★",
      "tip": "Short booking tip.",
      "booking_url": ""
    }},
    {{
      "rank": 2,
      "strategy": "budget_carrier",
      "title": "Budget Carrier Route",
      "provider_name": "Google Flights",
      "description": "Description of route and strategy.",
      "estimated_savings": "Save ~25%",
      "estimated_price_range": "{currency} 150 - 280",
      "airlines": ["Airline C"],
      "route": "{ex_route}",
      "stops": 1,
      "total_duration": "6h 15m",
      "convenience": "★★★☆☆",
      "tip": "Short booking tip.",
      "booking_url": ""
    }},
    {{
      "rank": 3,
      "strategy": "nearby_airport",
      "title": "Nearby Airport Option",
      "provider_name": "Google Flights",
      "description": "Description of route and strategy.",
      "estimated_savings": "Save ~10%",
      "estimated_price_range": "{currency} 220 - 350",
      "airlines": ["Airline A"],
      "route": "{ex_route}",
      "stops": 0,
      "total_duration": "4h 45m",
      "convenience": "★★★★☆",
      "tip": "Short booking tip.",
      "booking_url": ""
    }}
  ],
  "general_tips": [
    "Tip 1...",
    "Tip 2..."
  ]
}}
"""
    try:
        text, _ = await _call_gemini(prompt, api_key, max_tokens=4096, thinking_budget=0)
        data = _parse_json(text)
        data = _structure_ai_flight_strategies(
            data,
            currency=currency,
            travelers=travelers,
            outbound_date=outbound_date,
            return_date=return_date,
        )
        # The model wrote these routes freehand. Where we resolved real codes,
        # they win — this is the last point before the route reaches the card
        # and the booking link.
        data = _enforce_route_destination(data, dest_code, origin_code)
        return _apply_flight_booking_urls(
            data,
            departure_city=departure_city,
            destination=destination,
            flight_start_date=outbound_date,
            flight_end_date=return_date,
            travelers=travelers,
        )
    except Exception as e:
        logger.error(f"Failed to generate flight strategies: {e}")
        return {}


async def generate_hotel_strategies(
    *,
    destination: str,
    days: int,
    budget: float,
    currency: str,
    travelers: int,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
    api_key: str,
    serpapi_key: str = "",
) -> dict:
    """Generates hotel/accommodation strategies using SerpApi Google Hotels directly.

    Uses SerpAPI results directly, filtered to a minimum **star class** (see
    `min_hotel_class` below) rather than to a guest review score. Gemini is NOT
    used for hotel selection — prices, classes, ratings and hotel names come
    straight from Google Hotels via SerpAPI.

    Falls back to Gemini-based generation only after every rung of the class
    ladder has come back empty.
    """

    # Filter on **star class**, not on guest review score.
    #
    # The floor this replaces was `overall_rating >= 4.0` — a guest score out
    # of 5 — standing in for "3-star and above". They are unrelated measures: a
    # hostel dorm rated 4.6 by its guests cleared a 4.0 review floor while
    # every 3-star hotel rated 3.9 was excluded, which is the opposite of what
    # the filter was for. Google indexes the star class directly, so ask it for
    # the classes wanted (`hotel_class=3,4,5`) and let the filtering happen
    # against the whole index rather than over one page of results.
    #
    # The floor is still sized to what the trip can spend on a room — a flat
    # ceiling is what priced a 50,000 LKR / 5-day Colombo trip out of its own
    # destination, and the itinerary prompt takes this price range as a
    # mandatory check-in/out cost (see hotel_price_range in _build_prompt) — but
    # it now only ever moves *up* from 3. Below 3-star is reached by the
    # fallback ladder when a class-filtered search comes back empty, so a
    # traveller sees an unclassed guesthouse because nothing else exists in
    # their range, never because their budget was assumed to be small.
    min_hotel_class = _BASE_HOTEL_CLASS
    nights = max(days - 1, 1)
    rooms = _rooms_for(travelers)
    ground_floor = trip_cost_floor.on_ground_floor(
        destination=destination, days=days, travelers=travelers, currency=currency,
    )
    if ground_floor is not None:
        affordable_per_night = max(budget - ground_floor, 0) / nights / rooms
    else:
        # Destination not in trip_cost_floor's place-name tables (a large but
        # necessarily incomplete list) — silently keeping the 4.0 default here
        # was the original bug: for destinations outside that list, this whole
        # budget-aware adjustment never engaged at all. Fall back to a plain
        # budget-share estimate (lodging as ~35% of total, the same rule of
        # thumb the overall budget waterfall elsewhere in this function uses)
        # rather than giving up on being budget-aware.
        affordable_per_night = (budget * 0.35) / nights / rooms

    affordable_usd = trip_cost_floor.to_usd(affordable_per_night, currency)
    if affordable_usd is not None and affordable_usd >= _FOUR_STAR_NIGHTLY_USD:
        # Only when the trip can comfortably afford it does the floor move
        # above 3-star. Everything below this stays at the 3-star baseline
        # instead of being quietly dropped to a lower class: a tight budget is
        # a reason to sort by price, which this search already does, not a
        # reason to show the traveller worse hotels than they asked for.
        min_hotel_class = 4

    # ── Primary path: SerpAPI direct extraction ──────────────────────────────
    if serpapi_key:
        try:
            serp = SerpApiService(serpapi_key)
            # Walk down the class ladder from this trip's floor. The previous
            # version retried exactly once and then gave up on live prices
            # entirely, handing the whole stay to a Gemini guess — for a small
            # town where Google lists no classed hotel at all, that is every
            # time. Trying 2-star and then unfiltered keeps real Google prices
            # in the plan for those destinations.
            attempts = [c for c in _HOTEL_CLASS_FALLBACKS if c <= min_hotel_class]
            if min_hotel_class not in attempts:
                attempts.insert(0, min_hotel_class)

            for attempt, class_floor in enumerate(attempts):
                label = f"{class_floor}-star+" if class_floor else "any class"
                logger.info(
                    "Fetching live hotel data via SerpApi (Google Hotels), %s, for %s...",
                    label, destination,
                )
                serp_result = await serp.search_hotels(
                    destination=destination,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    adults=_STANDARD_ROOM_ADULTS,
                    currency=currency,
                    min_hotel_class=class_floor,
                    # Lowest-price-first, not Google's relevance default. A
                    # quality floor alone still surfaced whichever prominent
                    # (often pricier) chains Google ranks first among the
                    # eligible pool — this is what actually lets the cheapest
                    # eligible options through, so the Minimum/Recommended/
                    # Comfortable tiers span a real price range instead of four
                    # similarly-priced hotels.
                    sort_by=3,
                )

                properties = serp_result.get("properties") or []
                if not properties:
                    logger.warning(
                        "SerpAPI returned 0 hotels at %s for %s%s",
                        label, destination,
                        "; widening the class filter" if attempt + 1 < len(attempts) else "",
                    )
                    continue

                logger.info(
                    "SerpAPI returned %d hotels (%s) for %s",
                    len(properties), label, destination,
                )
                return extract_hotel_strategies_from_serpapi(
                    serp_result,
                    destination=destination,
                    currency=currency,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    travelers=travelers,
                    nights=nights,
                    max_hotels=4,
                )

        except Exception as e:
            logger.warning(f"SerpApi hotel search failed, falling back to Gemini: {e}")

    # ── Fallback: Gemini-based generation (only when SerpAPI unavailable) ────
    logger.info("Using Gemini fallback for hotel strategies (no SerpAPI results)")
    
    date_str = ""
    if hotel_check_in_date and hotel_check_out_date:
        date_str = f"- Check-in Date: {hotel_check_in_date}\n- Check-out Date: {hotel_check_out_date}"

    prompt = f"""Analyze accommodation options for a trip to "{destination}".
The travelers want recommended places to stay.

Trip Details:
- Destination: {destination}
{date_str}
- Duration: {days} days
- Group Size: {travelers} traveler(s)
- Total Trip Budget: {int(budget)} {currency}

Your task is to act as an agentic hotel finder. Propose 2-4 distinct, realistic hotel/stay options.
For each option, include a REAL, well-known hotel name that actually exists in {destination}.
Categories: Luxury, Boutique, Budget, Resort, or Apartment.

IMPORTANT RULES:
- provider_name MUST be "Google Hotels".
- Use REAL hotel names that actually exist in {destination}.
- Estimate REALISTIC per-night rates in {currency}.
- booking_url: Leave empty, will be generated server-side.
- EVERY strategy in the array MUST have its own non-empty "price_per_night" and "total_estimated_cost". Do not leave price fields blank on any strategy other than the first — all 2-4 strategies are shown to the user and all must display a price.

Return ONLY a JSON object with this exact shape (note every strategy has a price filled in):
{{
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "name": "Real Hotel Name",
      "provider_name": "Google Hotels",
      "category": "Boutique / Luxury / Budget",
      "rating": "4.7 ★",
      "price_per_night": "{currency} 120",
      "total_estimated_cost": "{currency} 600",
      "location": "City Center",
      "amenities": ["Free WiFi", "Breakfast Included", "Pool"],
      "description": "Short explanation of why this stay fits the trip.",
      "booking_url": ""
    }},
    {{
      "rank": 2,
      "name": "Real Hotel Name",
      "provider_name": "Google Hotels",
      "category": "Budget",
      "rating": "4.2 ★",
      "price_per_night": "{currency} 80",
      "total_estimated_cost": "{currency} 400",
      "location": "Near Downtown",
      "amenities": ["Free WiFi", "Breakfast Included"],
      "description": "Short explanation of why this stay fits the trip.",
      "booking_url": ""
    }},
    {{
      "rank": 3,
      "name": "Real Hotel Name",
      "provider_name": "Google Hotels",
      "category": "Resort",
      "rating": "4.5 ★",
      "price_per_night": "{currency} 150",
      "total_estimated_cost": "{currency} 750",
      "location": "Beachfront",
      "amenities": ["Free WiFi", "Pool", "Spa"],
      "description": "Short explanation of why this stay fits the trip.",
      "booking_url": ""
    }}
  ],
  "general_tips": [
    "Book at least 2 weeks in advance for best rates."
  ],
  "best_areas": "Central District, Beachfront"
}}
"""
    try:
        text, _ = await _call_gemini(prompt, api_key, max_tokens=4096, thinking_budget=0)
        data = _parse_json(text)
        strategies = data.get("strategies")
        if isinstance(strategies, list):
            rooms = _rooms_for(travelers)
            for strat in strategies:
                if isinstance(strat, dict):
                    provider = strat.get("provider_name") or "Google Hotels"
                    item_name = strat.get("name") or destination
                    strat["booking_url"] = _build_deep_booking_url(
                        provider=provider,
                        item_name=item_name,
                        destination=destination,
                        start_date=hotel_check_in_date,
                        end_date=hotel_check_out_date,
                        travelers=travelers,
                        is_flight=False,
                    )
                    # Put the model's stay total on the same footing as the
                    # SerpApi path's. Left as written, it is a number Gemini
                    # chose — for one room, or for the party, or for one night,
                    # unknowably — while the budget's stay line is computed from
                    # `price_per_night` x nights x rooms either way. This is the
                    # last path on which the Stays tab and the budget could
                    # still quote one stay at two prices.
                    strat["nights"] = nights
                    strat["rooms"] = rooms
                    nightly = _extract_lowest_price(strat.get("price_per_night") or "")
                    if nightly > 0:
                        strat["total_estimated_cost"] = (
                            f"{currency} {nightly * nights * rooms:,.0f}"
                        )
        return data
    except Exception as e:
        logger.error(f"Failed to generate hotel strategies: {e}")
        return {}


def _rooms_for(travelers: int) -> int:
    """Rooms a party needs, at two to a room.

    Accommodation used to ignore party size entirely — it reached SerpApi as
    `adults=` and never became rooms — so three travellers were budgeted one
    room's worth of nights.

    Delegates to `serpapi_service.rooms_for`, which the Stays tab's own stay
    totals are built from: a second copy of this rule here is how the budget's
    stay line and the Stays tab came to quote different totals for one stay.
    """
    return serpapi_rooms_for(travelers)


def _rate_for_tier(rates: list[float], tier: str) -> float:
    """One leg's nightly rate for a budget tier, chosen by price rank.

    Mirrors how flights are tiered (see the `priced.sort` block in
    `_price_ai_flight_strategies` and `_tier_flight_cost`): cheapest room is
    the Minimum tier, dearest is Comfortable, and the median sits between.

    Before this existed every tier was priced at `min(rates)`, which is why
    Stay / Accommodation showed an identical figure on all three Budget
    Allocation tabs while transit, food and activities all moved with the
    tier — the client-reported bug.
    """
    if not rates:
        return 0.0
    ordered = sorted(rates)
    if tier == "minimum":
        return ordered[0]
    if tier == "comfortable":
        return ordered[-1]
    return ordered[len(ordered) // 2]


def required_stay_cost(
    hotel_strategies: dict | None,
    city_legs: list[dict],
    travelers: int,
    tier: str = "minimum",
) -> float:
    """What the accommodation actually costs the party, across every city.

    For each city the trip sleeps in: that city's nightly rate for [tier] x
    that leg's nights x the rooms the party needs. This is the Budget
    Allocation's "Stay / Accommodation" line, and it is deliberately the same
    arithmetic the Stays tab quotes each hotel's Est. Total with — the two are
    a reconciliation, not two independent estimates, and are tested together.

    [tier] defaults to "minimum" — the cheapest room, which is what the
    feasibility floor has to be measured against and what every existing
    caller and test expects. The Budget Allocation tabs pass their own tier so
    Comfortable prices a comfortable room rather than repeating the Minimum
    figure.

    The figure this replaced was a single `min()` over one trip-wide hotel
    search, so a four-city trip was budgeted one city's stay, party size never
    became rooms, and — when no dates reached SerpApi — a single night stood in
    for the whole trip.

    Module-level rather than a closure inside `generate_odyssey` so it can be
    tested against the Stays tab's totals directly, which is the only way to
    catch the two drifting apart again.
    """
    strategies_ = (hotel_strategies or {}).get("strategies")
    if not isinstance(strategies_, list) or not city_legs:
        return 0.0
    rooms_ = _rooms_for(travelers)
    nightly_by_leg: dict[int, list[float]] = {}
    for s in strategies_:
        if not isinstance(s, dict):
            continue
        rate = _extract_lowest_price(s.get("price_per_night"))
        if rate > 0:
            nightly_by_leg.setdefault(int(s.get("leg_index") or 0), []).append(rate)

    total_ = 0.0
    for leg_i, leg_ in enumerate(city_legs):
        nights_ = int(leg_.get("nights") or 0)
        if nights_ <= 0:
            continue
        rates_ = nightly_by_leg.get(leg_i)
        if not rates_:
            # A leg whose search came back empty still has to be slept in.
            # Carry the trip's known rates rather than pricing those nights at
            # zero, which is what made a budget look sufficient. Pooled across
            # legs, then tiered the same way, so an empty leg tracks the tier
            # instead of always falling back to the cheapest room.
            if not nightly_by_leg:
                continue
            rates_ = [r for rr in nightly_by_leg.values() for r in rr]
        total_ += _rate_for_tier(rates_, tier) * nights_ * rooms_
    return round(total_, 2)


async def generate_hotel_strategies_for_legs(
    *,
    legs: list[dict],
    days: int,
    budget: float,
    currency: str,
    travelers: int,
    hotel_check_in_date: str,
    hotel_check_out_date: str,
    api_key: str,
    serpapi_key: str,
) -> dict:
    """Hotels for every city the trip sleeps in, each priced for its own nights.

    Wraps the single-city `generate_hotel_strategies` once per leg rather than
    replacing it — the extraction, the star-rating retry and the Gemini fallback
    all still apply per city.

    The old single search asked Google for `hotels in <destination>`, which for
    a country returned a country-wide mix: a tester's Cambodia trip listed a
    Siem Reap hotel beside a Sihanoukville one, each quoted for all nine nights,
    and every day of every city linked to that one list.

    Returns the same {strategies, general_tips, best_areas} shape, with each
    strategy tagged `leg_index`/`city` so the client can group them. Tagging
    rather than nesting keeps already-saved Odysseys parseable.
    """
    if not legs:
        return {}

    searches = [
        generate_hotel_strategies(
            destination=leg["city"],
            days=max(int(leg.get("nights") or 1), 1) + 1,
            budget=budget,
            currency=currency,
            travelers=travelers,
            # Each leg's own window. This is what makes a two-night stay quote
            # two nights instead of the whole trip.
            hotel_check_in_date=leg.get("check_in_date") or hotel_check_in_date or "",
            hotel_check_out_date=leg.get("check_out_date") or hotel_check_out_date or "",
            api_key=api_key,
            serpapi_key=serpapi_key,
        )
        for leg in legs
    ]
    results = await asyncio.gather(*searches, return_exceptions=True)

    merged: list[dict] = []
    tips: list[str] = []
    areas: list[str] = []
    for index, (leg, result) in enumerate(zip(legs, results)):
        if isinstance(result, Exception) or not isinstance(result, dict):
            logger.warning("Hotel search failed for leg %s (%s): %s", index, leg.get("city"), result)
            continue
        for strategy in result.get("strategies") or []:
            if not isinstance(strategy, dict):
                continue
            strategy["leg_index"] = index
            strategy["city"] = leg.get("city") or ""
            # Only overwrite with a real figure. A leg carrying no nights would
            # otherwise stamp 0 over the nights the stay total was actually
            # priced with, leaving the Stays tab showing a total it then
            # describes as covering no nights at all.
            leg_nights = int(leg.get("nights") or 0)
            if leg_nights > 0:
                strategy["nights"] = leg_nights
            strategy["rooms"] = _rooms_for(travelers)
            merged.append(strategy)
        if result.get("best_areas"):
            areas.append(str(result["best_areas"]))
        for tip in result.get("general_tips") or []:
            if tip not in tips:
                tips.append(str(tip))

    if not merged:
        return {}

    logger.info(
        "Hotels found for %d/%d leg(s): %s",
        len({s["leg_index"] for s in merged}), len(legs),
        ", ".join(f"{l['city']}({l.get('nights')}n)" for l in legs),
    )
    return {"strategies": merged, "general_tips": tips, "best_areas": ", ".join(areas[:3])}


def _single_leg(destination: str, days: int, start_date: str = "", geo=None) -> list[dict]:
    """The whole trip as one leg in one city — the shape before city legs existed.

    Every failure path in leg planning lands here, so a bad or unparseable model
    response degrades the Odyssey to exactly the behaviour it had before rather
    than breaking it or, worse, searching hotels in a city nobody is visiting.
    """
    days = max(int(days or 1), 1)
    leg = {
        "city": destination,
        # Stamped from the resolved destination when we have one, so the safe
        # fallback carries the same country the prompts are constrained to
        # rather than an empty string that reads as "unknown".
        "country": (geo.country_code if geo is not None and geo.resolved else ""),
        "start_day": 1,
        "end_day": days,
        "nights": max(days - 1, 0),
    }
    _date_leg(leg, start_date)
    return [leg]


def _date_leg(leg: dict, start_date: str) -> None:
    """Stamp a leg with its own check-in/check-out dates, derived from day numbers.

    These are what the per-leg hotel search sends to Google, and they are the
    reason a two-night stay is finally quoted for two nights: the single
    trip-wide window is what made every hotel's "Est. Total" the whole trip.
    """
    leg["check_in_date"] = ""
    leg["check_out_date"] = ""
    if not start_date:
        return
    try:
        from datetime import date as _date, timedelta as _timedelta
        trip_start = _date.fromisoformat(str(start_date)[:10])
        check_in = trip_start + _timedelta(days=int(leg["start_day"]) - 1)
        check_out = check_in + _timedelta(days=max(int(leg["nights"]), 1))
    except Exception:
        return
    leg["check_in_date"] = check_in.isoformat()
    leg["check_out_date"] = check_out.isoformat()


def _validate_legs(raw, destination: str, days: int, start_date: str = "", geo=None) -> list[dict]:
    """Coerce a model's leg list into one that actually covers the trip.

    Rejects rather than repairs anything structural: legs must be contiguous,
    start at day 1, end at day `days`, and name a city. A plausible-looking but
    wrong set of legs is the dangerous failure here — it would send the hotel
    search to a city the traveller never visits and look deliberate while doing
    it — so anything that does not line up falls back to a single leg.
    """
    if not isinstance(raw, list) or not raw:
        return _single_leg(destination, days, start_date, geo)

    legs: list[dict] = []
    expected_start = 1
    for entry in raw:
        if not isinstance(entry, dict):
            return _single_leg(destination, days, start_date, geo)
        city = str(entry.get("city") or "").strip()
        if not city:
            return _single_leg(destination, days, start_date, geo)
        try:
            start_day = int(entry.get("start_day"))
            end_day = int(entry.get("end_day"))
        except (TypeError, ValueError):
            return _single_leg(destination, days, start_date, geo)
        if start_day != expected_start or end_day < start_day or end_day > days:
            return _single_leg(destination, days, start_date, geo)

        # Country gate. Free — this field was already being parsed and then
        # discarded, and the model volunteers it unprompted. A trip to the
        # Andamans came back with {"city": "Kandy", "country": "LK"} sitting
        # right here, and nothing looked at it; the hotel search then went to
        # Kandy. Reject rather than repair, like every other check in here:
        # a plausible-but-wrong route is the dangerous failure.
        leg_country = str(entry.get("country") or "").strip().upper()
        if geo is not None and geo.resolved:
            claimed = leg_country if len(leg_country) == 2 else (
                trip_cost_floor.country_for(city) or ""
            ).upper()
            # Silence is tolerated; disagreement is not. A model that omits the
            # country tells us nothing, and guessing on its behalf would reject
            # legitimate routes in countries our own table has never heard of.
            if claimed and claimed != geo.country_code:
                logger.warning(
                    "Leg %r declares country %s but the trip resolved to %s — "
                    "falling back to a single leg.", city, claimed, geo.country_code,
                )
                return _single_leg(destination, days, start_date, geo)

        leg = {
            "city": city,
            "country": str(entry.get("country") or "").strip(),
            "start_day": start_day,
            "end_day": end_day,
            # Derived, never trusted from the model: the nights a leg is worth
            # are what its hotel is priced on, so an invented number here would
            # silently mis-state the accommodation budget.
            "nights": end_day - start_day + 1,
        }
        _date_leg(leg, start_date)
        legs.append(leg)
        expected_start = end_day + 1

    if expected_start != days + 1:
        return _single_leg(destination, days, start_date, geo)

    # The last leg's final day is a departure day, not a night slept.
    legs[-1]["nights"] = max(legs[-1]["nights"] - 1, 0)
    _date_leg(legs[-1], start_date)
    if sum(int(l["nights"]) for l in legs) != max(days - 1, 0):
        return _single_leg(destination, days, start_date, geo)

    return legs


# ── Geographic drift detection ─────────────────────────────────────────────
#
# The prompt grounding in `_build_prompt` is what actually keeps the itinerary
# in the right country. This is the backstop for when it does not, and it is
# built to be nearly free: Tier 1 is one regex pass over text already in
# memory, and it is the check that would have caught the reported bug twice —
# once on the day theme "Arrival and Kandy Exploration" and again on "Sri
# Lankan rice and curry".

# How many generated place names Tier 2 will pay to geocode. Set to 0 to turn
# the paid tier off entirely and rely on Tier 1 alone.
_DRIFT_SAMPLE_SIZE = 3

# One regeneration, ever. The retry is a straight line, not a loop.
_MAX_DESTINATION_RETRIES = 1


def _drift_scan_texts(plan: dict) -> list[tuple[str, str]]:
    """(where, text) pairs worth scanning for foreign place names.

    Deliberately narrow. `visa`, `logistics`, `practical_info` and
    `booking_partners` all legitimately name the traveller's own country and
    the country they fly from — scanning those would flag every international
    trip ever planned.
    """
    out: list[tuple[str, str]] = []
    summary = str(plan.get("summary") or "")
    if summary:
        out.append(("summary", summary))
    for d in (plan.get("day_plans") or plan.get("plan") or []):
        if not isinstance(d, dict):
            continue
        theme = str(d.get("theme") or "")
        if theme:
            out.append(("day theme", theme))
        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            name = str(a.get("name") or a.get("attraction_name") or "")
            if name:
                out.append(("activity", name))
            tip = str(a.get("tip") or "")
            if tip:
                out.append(("tip", tip))
            for r in (a.get("restaurants") or []):
                if isinstance(r, dict):
                    for key in ("name", "cuisine"):
                        val = str(r.get(key) or "")
                        if val:
                            out.append((f"restaurant {key}", val))
    return out


def _drift_sample_names(plan: dict, limit: int) -> list[str]:
    """Distinct, proper-noun-ish activity names spread across the trip."""
    seen: set[str] = set()
    picked: list[str] = []
    for d in (plan.get("day_plans") or plan.get("plan") or []):
        if not isinstance(d, dict):
            continue
        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            if str(a.get("type") or "").strip().lower() not in {
                "attraction", "exploration", "dining", "sightseeing"
            }:
                continue
            name = str(a.get("name") or a.get("attraction_name") or "").strip()
            low = name.lower()
            if len(name) < 6 or low in seen:
                continue
            if "check-in" in low or "check in" in low or "check-out" in low:
                continue
            seen.add(low)
            picked.append(name)
            break  # at most one per day, so the sample spans the trip
        if len(picked) >= limit:
            break
    return picked[:limit]


@dataclass
class GeoDrift:
    ok: bool = True
    reasons: list = None
    offending: list = None

    def __post_init__(self):
        if self.reasons is None:
            self.reasons = []
        if self.offending is None:
            self.offending = []


async def detect_geo_drift(
    plan: dict,
    geo,
    *,
    sample: int = _DRIFT_SAMPLE_SIZE,
    allow_codes: tuple = (),
    budget=None,
) -> "GeoDrift":
    """Has the model written an itinerary for the wrong country?

    Tier 1 is free and always runs. Tier 2 geocodes a few generated names and
    only runs when Tier 1 found nothing, so the common case — a clean plan —
    costs at most `sample` lookups and a drifted one costs none.
    """
    if geo is None or not geo.resolved or not isinstance(plan, dict):
        return GeoDrift(ok=True)

    allow = frozenset(c.upper() for c in allow_codes if c)
    home = geo.country_code
    country = geo.country or home

    # ── Tier 1: free name scan ──
    hits: dict[str, str] = {}
    reasons: list[str] = []
    for where, text in _drift_scan_texts(plan):
        found = geo_resolver.foreign_place_hits(text, home, allow)
        if not found:
            continue
        # A single passing mention in a tip is weak evidence; a foreign name in
        # an activity name or a day theme is the itinerary itself relocating.
        strong = where in {"activity", "day theme", "restaurant name"}
        for name, code in found.items():
            hits[name] = code
            if strong and name not in [r.split('"')[1] for r in reasons if '"' in r]:
                reasons.append(f'The {where} "{text}" names "{name}", which is in {code}, not {country}.')

    if reasons or len(hits) >= 2:
        if not reasons:
            listed = ", ".join(sorted(hits))
            reasons.append(
                f"The plan repeatedly names places outside {country}: {listed}."
            )
        return GeoDrift(ok=False, reasons=reasons, offending=sorted(hits))

    # ── Tier 2: paid, bounded, only when Tier 1 is clean ──
    if sample <= 0 or not geo.has_coords:
        return GeoDrift(ok=True)

    names = _drift_sample_names(plan, sample)
    if not names:
        return GeoDrift(ok=True)

    checks = await asyncio.gather(*(
        geo_resolver.verify_place(n, near=geo, max_km=None, budget=budget)
        for n in names
    ), return_exceptions=True)

    bad = [
        c for c in checks
        if isinstance(c, geo_resolver.PlaceCheck) and c.checked and not c.ok
    ]
    # Two independent misses, not one. A single mis-geocoded name is a fact
    # about Google's index, not evidence the trip moved country.
    if len(bad) >= 2:
        return GeoDrift(
            ok=False,
            reasons=[
                f'"{c.query}" resolves to {c.country_code or "elsewhere"}, not {country}.'
                for c in bad
            ],
            offending=[c.query for c in bad],
        )
    return GeoDrift(ok=True)


async def plan_city_legs(
    *,
    destination: str,
    days: int,
    mood: str,
    travelers: int,
    api_key: str,
    start_date: str = "",
    geo=None,
) -> list[dict]:
    """Decide which cities the trip stays in, and for how long.

    Runs before flights and hotels are bought, because the per-leg hotel search
    needs the cities and the itinerary that would otherwise name them is not
    written until later.

    Deliberately ungrounded: `_call_gemini` can only ask for JSON mode when no
    search tool is attached (see the responseMimeType guard there), and a
    reliable machine-readable answer matters more here than live facts — the
    grounded itinerary pass still checks the places themselves.
    """
    days = max(int(days or 1), 1)
    if not api_key or days < 2:
        return _single_leg(destination, days, start_date, geo)

    # This call is where the hotel search's city strings come from, so an
    # invented country here is expensive: it books rooms in the wrong place.
    geo_line = ""
    if geo is not None and geo.resolved:
        country = geo.country or geo.country_code
        geo_line = (
            f"\n{destination} is in {country}"
            + (f", {geo.admin_area}" if geo.admin_area else "")
            + (f", at {geo.latitude:.4f}, {geo.longitude:.4f}" if geo.has_coords else "")
            + ".\n"
        )

    country_rule = ""
    if geo is not None and geo.resolved:
        country_rule = (
            f"- EVERY leg must be a real city or town in "
            f"{geo.country or geo.country_code}, and the \"country\" field of "
            f"every leg MUST be exactly \"{geo.country_code}\". If the "
            f"destination's name resembles a place in another country, ignore "
            f"the resemblance.\n"
        )

    prompt = f"""Plan the city-by-city route for a {days}-day trip to {destination}.
{geo_line}
Group: {travelers} traveller(s). Travel style: {mood or "balanced"}.

Return ONLY this JSON:
{{"legs": [{{"city": "...", "country": "<ISO 2-letter>", "start_day": 1, "end_day": 3}}]}}

Rules:
- Cover every day from 1 to {days} with no gaps and no overlaps: each leg's
  start_day must be the previous leg's end_day + 1, the first starts at 1 and
  the last ends at {days}.
- "city" must be a real, searchable city or town where the traveller SLEEPS
  that night — this is what the hotel search is given. If a day trips out to a
  smaller town and returns, keep the sleeping city. If the traveller ends the
  day in the smaller town, name the smaller town.
- Prefer fewer, longer legs. Do not move city more often than every 2 days
  unless {destination} is small enough that it makes sense.
- If {destination} is a single city, return exactly one leg for it.
{country_rule}- No commentary, no markdown."""

    try:
        raw, _ = await _call_gemini(prompt, api_key, max_tokens=1024, use_grounding=False)
        parsed = json.loads(raw)
        legs = _validate_legs(
            (parsed or {}).get("legs"), destination, days, start_date, geo,
        )
    except Exception as e:
        logger.warning(f"City-leg planning failed, using a single leg: {e}")
        return _single_leg(destination, days, start_date, geo)

    logger.info(
        "Planned %d city leg(s) for %s: %s",
        len(legs), destination, ", ".join(f"{l['city']} d{l['start_day']}-{l['end_day']}" for l in legs),
    )
    return legs


async def generate_odyssey(
    *,
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
    travelers: int = 1,
    api_key: str,
    unsplash_api_key: str = "",
    serpapi_key: str = "",
    include_flights: bool = False,
    departure_city: str = "",
    departure_country: str = "",
    nationality: str = "",
    has_visa: bool = False,
    flight_start_date: str = "",
    flight_end_date: str = "",
    include_hotels: bool = False,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
    start_date: str = "",
    end_date: str = "",
    destination_place_id: str = "",
    destination_latitude: float | None = None,
    destination_longitude: float | None = None,
    destination_address: str = "",
    departure_latitude: float | None = None,
    departure_longitude: float | None = None,
) -> tuple[str, list[dict]]:
    """Generate the plan. Returns (title, items) ready to store on an Itinerary."""
    final_destination = str(destination)

    # Resolve WHERE this trip is before anything reads the destination string.
    # Everything downstream that used to see a bare, ambiguous name — the leg
    # planner, the airport lookup, the itinerary prompt — gets a country
    # instead. The client sends coordinates when it has them; the lookup here
    # is what makes older app builds and already-saved drafts correct too.
    geo_budget = geo_resolver.GeoBudget()
    geo = await geo_resolver.resolve_destination(
        final_destination,
        place_id=destination_place_id,
        latitude=destination_latitude,
        longitude=destination_longitude,
        address_hint=destination_address,
        budget=geo_budget,
    )
    if geo.resolved:
        logger.info(
            "Destination %r resolved to %s via %s", final_destination, geo.label(), geo.source,
        )
    else:
        logger.warning(
            "Destination %r did not resolve — generating without geographic grounding.",
            final_destination,
        )

    # 1. Fetch Unsplash cover photo, flight strategies, and hotel strategies concurrently FIRST
    async def _get_cover():
        if unsplash_api_key:
            try:
                return await fetch_unsplash_cover_photo(final_destination, unsplash_api_key)
            except Exception as e:
                logger.error(f"Cover photo fetch failed: {e}")
                return ""
        return ""

    async def _get_flights():
        # Coordinates alone are enough: the country recovered from them gives a
        # real origin airport, where the name may only have been "Nearby".
        _has_departure = bool(str(departure_city or "").strip()) or (
            departure_latitude is not None and departure_longitude is not None
        )
        if include_flights and _has_departure:
            try:
                return await generate_flight_strategies(
                    departure_city=departure_city,
                    departure_country=departure_country,
                    destination=final_destination,
                    days=days,
                    budget=budget,
                    currency=currency,
                    travelers=travelers,
                    flight_start_date=flight_start_date or "",
                    flight_end_date=flight_end_date or "",
                    api_key=api_key,
                    serpapi_key=serpapi_key,
                    destination_geo=geo,
                    geo_budget=geo_budget,
                    departure_latitude=departure_latitude,
                    departure_longitude=departure_longitude,
                )
            except Exception as e:
                logger.error(f"Flight strategy sub-job failed: {e}")
                return {}
        return {}

    # Which cities the trip sleeps in, decided before anything is bought: the
    # per-leg hotel search needs them, and the itinerary that would otherwise
    # name them is not written until further down.
    city_legs = await plan_city_legs(
        destination=final_destination,
        days=days,
        mood=mood,
        travelers=travelers,
        api_key=api_key,
        start_date=hotel_check_in_date or start_date or "",
        geo=geo,
    )

    async def _get_hotels():
        if include_hotels:
            try:
                return await generate_hotel_strategies_for_legs(
                    legs=city_legs,
                    days=days,
                    budget=budget,
                    currency=currency,
                    travelers=travelers,
                    hotel_check_in_date=hotel_check_in_date or "",
                    hotel_check_out_date=hotel_check_out_date or "",
                    api_key=api_key,
                    serpapi_key=serpapi_key,
                )
            except Exception as e:
                logger.error(f"Hotel strategy sub-job failed: {e}")
                return {}
        return {}

    cover_url, flight_strategies, hotel_strategies = await asyncio.gather(
        _get_cover(), _get_flights(), _get_hotels()
    )

    # Extract primary recommended hotel entity from confirmed SerpAPI results.
    # Used only for the booking checklist (_assemble_booking_plan) below — a
    # single suggested starting point to book is fine there. It must NOT be
    # named inside the day-by-day itinerary (see hotel_price_range instead):
    # doing so committed the user to one specific, arbitrarily-first-listed
    # property in their schedule, even though the Stays tab shows several
    # real alternatives that can be a completely different hotel.
    primary_hotel = None
    if hotel_strategies and isinstance(hotel_strategies.get("strategies"), list):
        for s in hotel_strategies["strategies"]:
            if isinstance(s, dict) and s.get("name"):
                primary_hotel = s
                break

    # Nightly rate range across every hotel option found, for the itinerary's
    # generic accommodation activity — never one property's exact rate.
    has_hotel_data = bool(
        hotel_strategies
        and isinstance(hotel_strategies.get("strategies"), list)
        and hotel_strategies["strategies"]
    )
    hotel_price_range = ""
    if has_hotel_data:
        rates = [
            _extract_lowest_price(s.get("price_per_night"))
            for s in hotel_strategies["strategies"]
            if isinstance(s, dict) and _extract_lowest_price(s.get("price_per_night")) > 0
        ]
        if rates:
            lo, hi = min(rates), max(rates)
            hotel_price_range = (
                f"{currency} {lo:,.0f}" if lo == hi
                else f"{currency} {lo:,.0f} - {hi:,.0f}"
            )

    # Extract primary flight entity if available.
    # Flight strategies key their label as "title"; only hotels use "name".
    primary_flight = None
    if flight_strategies and isinstance(flight_strategies.get("strategies"), list):
        for s in flight_strategies["strategies"]:
            if isinstance(s, dict) and (s.get("title") or s.get("name")):
                primary_flight = s
                break

    # 2. Build grounded prompt using confirmed live inventory
    prompt = _build_prompt(
        destination=final_destination,
        mood=mood,
        budget=budget,
        days=days,
        currency=currency,
        travelers=travelers,
        hotel_price_range=hotel_price_range,
        confirmed_flight=primary_flight,
        departure_city=departure_city,
        departure_country=departure_country,
        nationality=nationality,
        has_visa=has_visa,
        legs=city_legs,
        geo=geo,
    )
    try:
        text, grounding_chunks = await _call_gemini(
            prompt, api_key, max_tokens=8192, thinking_budget=0, use_grounding=True,
        )
        plan = _parse_json(text)
    except Exception as e:
        logger.warning(
            "Grounded Gemini generation/parsing failed (%s) — falling back to standard ungrounded generation",
            e,
        )
        text, grounding_chunks = await _call_gemini(
            prompt, api_key, max_tokens=8192, thinking_budget=0, use_grounding=False,
        )
        plan = _parse_json(text)

    # ── Geographic drift backstop ──────────────────────────────────────────
    # The grounding above is what keeps the itinerary honest; this catches the
    # residue. Structurally incapable of looping: one await, one regeneration,
    # and the retry cannot re-enter this block.
    geo_check: dict = {"status": "skipped"}
    if geo.resolved:
        # The traveller's own country and the one they fly from get named all
        # over a legitimate plan — neither is drift.
        allow = tuple(
            c for c in (
                (trip_cost_floor.country_for(departure_country) or "").upper(),
                (trip_cost_floor.country_for(nationality) or "").upper(),
                (trip_cost_floor.country_for(departure_city) or "").upper(),
            ) if c
        )
        drift = await detect_geo_drift(plan, geo, allow_codes=allow, budget=geo_budget)
        geo_check = {
            "status": "clean" if drift.ok else "drifted",
            "regenerated": False,
            "reasons": list(drift.reasons),
        }
        if not drift.ok:
            logger.warning(
                "Geographic drift for %s (%s): %s",
                geo.label(), geo.country_code, "; ".join(drift.reasons),
            )
            for _ in range(_MAX_DESTINATION_RETRIES):
                try:
                    retry_prompt = _build_prompt(
                        destination=final_destination, mood=mood, budget=budget,
                        days=days, currency=currency, travelers=travelers,
                        hotel_price_range=hotel_price_range,
                        confirmed_flight=primary_flight,
                        departure_city=departure_city,
                        departure_country=departure_country,
                        nationality=nationality, has_visa=has_visa,
                        legs=city_legs, geo=geo,
                        correction="\n".join(drift.reasons),
                    )
                    retry_text, retry_chunks = await _call_gemini(
                        retry_prompt, api_key, max_tokens=8192,
                        thinking_budget=0, use_grounding=True,
                    )
                    retry_plan = _parse_json(retry_text)
                    retry_drift = await detect_geo_drift(
                        retry_plan, geo, allow_codes=allow, budget=geo_budget,
                    )
                    # Keep the retry only when it is actually better. A second
                    # attempt that drifts just as badly is not an improvement,
                    # and the first plan at least had the grounded pass behind it.
                    if retry_drift.ok or len(retry_drift.reasons) < len(drift.reasons):
                        plan, grounding_chunks, drift = retry_plan, retry_chunks, retry_drift
                    geo_check = {
                        "status": "clean" if drift.ok else "uncertain",
                        "regenerated": True,
                        "reasons": list(drift.reasons),
                    }
                except Exception as e:
                    logger.warning("Geo-corrective regeneration failed, keeping the first plan: %s", e)
                    geo_check["regenerated"] = True
                break
            if not drift.ok:
                # Decision: ship it and record it. Hotels and flights are
                # grounded separately and are correct, so the traveller still
                # gets a usable plan; the warning is how we find out it happened.
                logger.warning(
                    "Geographic drift PERSISTED after regeneration for %s: %s",
                    geo.label(), "; ".join(drift.reasons),
                )
    logger.info("Geo lookups used for this Odyssey: %d", geo_budget.spent)

    g_days = _as_int(plan.get("days"), days)
    nights = _as_int(plan.get("nights"), g_days - 1 if g_days > 1 else 0)
    title = str(plan.get("title") or "Your Odyssey")

    final_start_date = start_date or flight_start_date or hotel_check_in_date or ""
    final_end_date = end_date or flight_end_date or hotel_check_out_date or ""

    # Extract cheapest flight & stay costs if available to synchronize budget breakdown.
    #
    # `price_per_traveler` is unambiguously one traveller's fare (SerpApi is
    # queried with adults=1 for exactly this reason), so multiplying by the
    # party size here is correct. The old path string-parsed
    # `estimated_price_range` — a figure of undefined basis — and multiplied
    # that, which double-counted the party whenever Google had already priced
    # the whole group.
    def _tier_flight_cost(tier: str) -> float:
        """Party-total flight cost for one tier, falling back to the cheapest."""
        if not (flight_strategies and isinstance(flight_strategies.get("strategies"), list)):
            return 0.0
        party = max(travelers, 1)
        per_traveler = []
        tier_price = 0.0
        for s in flight_strategies["strategies"]:
            if not isinstance(s, dict):
                continue
            price = s.get("price_per_traveler")
            if not isinstance(price, (int, float)) or price <= 0:
                # Legacy odysseys / AI fallback without structured pricing.
                price = _extract_lowest_price(s.get("estimated_price_range"))
            if price and price > 0:
                per_traveler.append(float(price))
                if s.get("tier") == tier:
                    tier_price = float(price)
        if tier_price > 0:
            return tier_price * party
        return min(per_traveler) * party if per_traveler else 0.0

    cheapest_flight_cost = _tier_flight_cost("minimum")

    cheapest_hotel_cost = required_stay_cost(
        hotel_strategies, city_legs, travelers,
    )

    def _tier_stay_cost(tier: str) -> float:
        """Party-total stay cost for one tier, falling back to the cheapest.

        The counterpart of `_tier_flight_cost`. Without it every scenario
        repeated `cheapest_hotel_cost`, so Stay / Accommodation was the one
        line that never moved between the Minimum, Recommended and Comfortable
        tabs.
        """
        cost = required_stay_cost(hotel_strategies, city_legs, travelers, tier)
        return cost if cost > 0 else cheapest_hotel_cost

    # Base budget allocation. Parameterized on `total` so the same waterfall
    # can price out Minimum/Comfortable scenarios below without a second
    # Gemini call. `flight_cost` and `stay_cost` both vary per scenario: each
    # budget scenario is priced against *its own* flight and hotel tier, so the
    # Budget tab, the Flights tab and the Stays tab quote the same figures.
    def _waterfall(
        total: float, flight_cost: float = 0.0, stay_cost: float = 0.0,
    ) -> dict:
        tot_ = total if total > 0 else 1.0
        flight_cost_ = flight_cost if flight_cost > 0 else cheapest_flight_cost
        stay_cost_ = stay_cost if stay_cost > 0 else cheapest_hotel_cost

        if flight_cost_ > 0:
            transit_amt_ = min(flight_cost_, round(tot_ * 0.85, 2))
        else:
            transit_amt_ = round(tot_ * 0.30, 2)

        rem_after_transit_ = max(tot_ - transit_amt_, round(tot_ * 0.15, 2))

        if stay_cost_ > 0:
            # The stay costs what it costs. Capping it at a share of what the
            # flights left over is what showed 13,500 against a real 17,900 and
            # called the plan affordable — the traveller cannot book 60% of a
            # room. When this overruns the budget, the feasibility check below
            # is what must say so.
            stay_amt_ = round(stay_cost_, 2)
        else:
            stay_amt_ = round(rem_after_transit_ * 0.45, 2)

        rem_for_food_act_ = max(tot_ - (transit_amt_ + stay_amt_), round(tot_ * 0.05, 2))
        food_amt_ = round(rem_for_food_act_ * 0.60, 2)
        # Floored at zero: a tier whose own flights and rooms outrun its total
        # would otherwise quote a negative activities budget. The scenario
        # totals below are floored against each tier's real cost precisely so
        # this stays a guard rather than a routine outcome.
        activities_amt_ = round(
            max(tot_ - (stay_amt_ + transit_amt_ + food_amt_), 0.0), 2
        )

        return {
            "stay": stay_amt_,
            "transit": transit_amt_,
            "food": food_amt_,
            "activities": activities_amt_,
            "total": tot_,
        }

    final_currency = str(plan.get("currency") or currency)
    visa_info = _parse_visa_info(
        plan.get("visa"),
        nationality=nationality,
        final_start_date=final_start_date,
        has_visa=has_visa,
    )

    # ── Budget feasibility from REAL SerpApi prices ─────────────────────
    # Instead of a static dictionary floor, compare the user's budget
    # against actual flight + hotel costs returned by SerpApi. This catches
    # every destination (including ones the dictionary didn't know, like
    # "Petra") and produces honest numbers the traveller can act on.
    user_budget = float(budget) if budget > 0 else 1.0

    # Flights and beds are measured; eating for the duration is not, and leaving
    # it out is what let a 150,000 budget pass as sufficient against 127,500 of
    # flights and 17,900 of hotel — technically covered, with 4,600 left to feed
    # three people for nine days. `on_ground_floor` excludes lodging on purpose,
    # since `cheapest_hotel_cost` above already prices the rooms.
    on_ground = trip_cost_floor.on_ground_floor(
        destination=final_destination,
        days=days,
        travelers=travelers,
        currency=currency,
    ) or 0.0

    real_minimum_cost = cheapest_flight_cost + cheapest_hotel_cost + on_ground
    budget_is_sufficient = (user_budget >= real_minimum_cost) or real_minimum_cost <= 0

    def _tier_floor(tier: str) -> float:
        """What one tier actually costs: its flights, its rooms, and the ground.

        `real_minimum_cost` is exactly `_tier_floor("minimum")`, so the
        feasibility check and `minimum_required` are unchanged by this — only
        the dearer tiers now price themselves honestly instead of reusing the
        cheapest room.
        """
        return _tier_flight_cost(tier) + _tier_stay_cost(tier) + on_ground

    def _scenario_total(nominal: float, tier: str) -> float:
        """A scenario's headline total, never below what that tier costs.

        A tier priced against its own dearer flights and rooms can outrun a
        multiple of the user's budget; letting it would drive the food and
        activities lines to zero and quote a tab the traveller cannot book.
        """
        floor_ = _tier_floor(tier)
        return max(nominal, round(floor_ * 1.05, 2)) if floor_ > 0 else nominal

    if budget_is_sufficient:
        # User's budget IS the Recommended tier — normal flow.
        tot = user_budget
        # Recommended is the user's own budget, left exactly as entered — it is
        # the headline total on the card, so it is never floored upward.
        budget_breakdown = _waterfall(
            tot,
            _tier_flight_cost("recommended"),
            _tier_stay_cost("recommended"),
        )

        budget_scenarios = {}
        # Only show a Minimum tier if there's meaningful headroom below.
        if real_minimum_cost > 0 and tot > real_minimum_cost * 1.25:
            budget_scenarios["minimum"] = _waterfall(
                _scenario_total(
                    tot * _SCENARIO_MULTIPLIERS["minimum"], "minimum",
                ),
                _tier_flight_cost("minimum"),
                _tier_stay_cost("minimum"),
            )
        budget_scenarios["recommended"] = budget_breakdown
        budget_scenarios["comfortable"] = _waterfall(
            _scenario_total(
                tot * _SCENARIO_MULTIPLIERS["comfortable"], "comfortable",
            ),
            _tier_flight_cost("comfortable"),
            _tier_stay_cost("comfortable"),
        )
        feasible = True
        if real_minimum_cost > 0 and (tot - real_minimum_cost) / real_minimum_cost < 0.2:
            budget_tightness = "tight"
        else:
            budget_tightness = "comfortable"
        minimum_required = real_minimum_cost if real_minimum_cost > 0 else None
    else:
        # Budget is INSUFFICIENT — override with realistic tiers built
        # from actual SerpApi flight + hotel prices. Each tier is costed
        # against *its own* floor (that tier's flights and rooms), not three
        # multiples of the cheapest one: scaling a single floor is what made
        # every tab quote the same stay figure while the others moved.
        # `_tier_floor("minimum")` is `real_minimum_cost`, so `minimum_required`
        # and the feasibility banner are unchanged.
        min_total = _tier_floor("minimum") * 1.15   # +15% buffer for food/activities
        rec_total = _tier_floor("recommended") * 1.35   # ~35% above its own floor
        comf_total = _tier_floor("comfortable") * 1.80  # ~80% above its own floor

        budget_breakdown = _waterfall(
            rec_total,
            _tier_flight_cost("recommended"),
            _tier_stay_cost("recommended"),
        )
        budget_scenarios = {
            "minimum": _waterfall(
                min_total,
                _tier_flight_cost("minimum"),
                _tier_stay_cost("minimum"),
            ),
            "recommended": budget_breakdown,
            "comfortable": _waterfall(
                comf_total,
                _tier_flight_cost("comfortable"),
                _tier_stay_cost("comfortable"),
            ),
        }
        tot = rec_total  # Display total = recommended realistic cost
        feasible = False
        budget_tightness = "insufficient"
        minimum_required = round(min_total, 2)

    stay_amt = budget_breakdown["stay"]
    transit_amt = budget_breakdown["transit"]
    food_amt = budget_breakdown["food"]
    activities_amt = budget_breakdown["activities"]

    stay_pct = round((stay_amt / tot) * 100)
    transit_pct = round((transit_amt / tot) * 100)
    food_pct = round((food_amt / tot) * 100)
    activities_pct = max(100 - (stay_pct + transit_pct + food_pct), 0)
    harmonized_budget_split = f"{stay_pct}% Stay - {transit_pct}% Transit - {food_pct}% Food - {activities_pct}% Activities"

    verified_sources = _deduplicate_grounding_chunks(grounding_chunks)
    if verified_sources:
        logger.info(
            "Google Search grounding: %d verified sources attached to itinerary",
            len(verified_sources),
        )

    if not feasible:
        recommendation = (
            "Your selected budget may not be sufficient for this itinerary and travel dates. "
            "Please increase your budget to the recommended amount or adjust your trip duration."
        )
    else:
        recommendation = ""

    verdict = {
        "feasible": feasible,
        "budget_tightness": budget_tightness,
        "minimum_required": minimum_required,
        "biggest_risk": str(plan.get("biggest_risk") or "").strip(),
        "recommendation": recommendation,
    }

    practical_info = _practical_info(plan.get("practical_info"))
    booking_plan = _assemble_booking_plan(
        primary_flight=primary_flight,
        primary_hotel=primary_hotel,
        booking_partners=plan.get("booking_partners") or [],
        visa_info=visa_info,
    )

    meta = build_meta_item(
        destination=final_destination,
        destination_context=geo.as_dict(),
        geo_check=geo_check,
        mood=mood,
        budget=tot,
        currency=final_currency,
        days=g_days,
        nights=nights,
        travelers=travelers,
        summary=str(plan.get("summary") or ""),
        budget_split=harmonized_budget_split,
        visa=visa_info,
        logistics=_logistics_text(plan.get("logistics")),
        booking_partners=plan.get("booking_partners") or [],
        cover_url=cover_url,
        flight_strategies=flight_strategies,
        hotel_strategies=hotel_strategies,
        start_date=final_start_date,
        end_date=final_end_date,
        departure_city=departure_city or "",
        budget_breakdown=budget_breakdown,
        budget_advisory="",
        verified_sources=verified_sources,
        verdict=verdict,
        budget_scenarios=budget_scenarios,
        practical_info=practical_info,
        booking_plan=booking_plan,
        legs=city_legs,
        generation_params={
            "destination": final_destination,
            "mood": mood,
            "budget": budget,
            "currency": currency,
            "days": days,
            "travelers": travelers,
            "include_flights": include_flights,
            "departure_city": departure_city,
            "departure_country": departure_country,
            "nationality": nationality,
            "has_visa": has_visa,
            "flight_start_date": flight_start_date,
            "flight_end_date": flight_end_date,
            "include_hotels": include_hotels,
            "hotel_check_in_date": hotel_check_in_date,
            "hotel_check_out_date": hotel_check_out_date,
            "start_date": start_date,
            "end_date": end_date,
        },
    )

    day_items: list[dict] = []
    raw_days = plan.get("day_plans") or plan.get("plan") or []
    total_days = len(raw_days)

    for d_idx, d in enumerate(raw_days):
        if not isinstance(d, dict):
            continue
        activities = []
        is_first_day = (d_idx == 0)
        is_last_day = (d_idx == total_days - 1)
        has_accommodation = False

        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            act_type = str(a.get("type") or "").strip().lower()
            name_str = str(a.get("name") or a.get("attraction_name") or "")
            name_lower = name_str.lower()

            is_acc = (
                act_type == "accommodation"
                or "check in" in name_lower
                or "check-in" in name_lower
                or "check out" in name_lower
                or "check-out" in name_lower
                or "freshen up" in name_lower
            )

            act_dict = {
                "time": str(a.get("time") or ""),
                "name": name_str,
                "tip": str(a.get("tip") or a.get("note") or ""),
                "cost": str(a.get("cost") or ""),
            }

            # 3. Reconcile accommodation stops with a price range across the
            # hotel options found — never a single named property, so the
            # itinerary can't contradict (or pre-empt) the actual choices
            # shown on the Stays tab.
            if is_acc and has_hotel_data:
                has_accommodation = True
                display_cost = f"{hotel_price_range} / night" if hotel_price_range else "See Stays tab"

                if is_first_day:
                    act_dict["name"] = "Hotel Check-in"
                    act_dict["tip"] = "Check in and settle into your accommodation."
                elif is_last_day and ("check out" in name_lower or "check-out" in name_lower):
                    act_dict["name"] = "Hotel Check-out"
                    act_dict["tip"] = "Complete check-out and luggage drop before departure."
                else:
                    if "hotel" in name_lower or "resort" in name_lower:
                        act_dict["name"] = "Rest & Freshen Up at Your Hotel"

                act_dict["type"] = "accommodation"
                act_dict["cost"] = display_cost
                act_dict["price_source"] = "Google Hotels"
                act_dict["price_basis"] = (
                    f"Nightly rate range across hotel options found for this trip: {hotel_price_range}."
                    if hotel_price_range else
                    "See the Stays tab for hotel pricing options."
                )
                act_dict["price_confidence"] = "Estimated"
            else:
                price_source = str(a.get("price_source") or "").strip()
                price_basis = str(a.get("price_basis") or "").strip()
                price_confidence = str(a.get("price_confidence") or "").strip()
                booking_url = str(a.get("booking_url") or "").strip()
                if price_source:
                    act_dict["price_source"] = price_source
                if price_basis:
                    act_dict["price_basis"] = price_basis
                if price_confidence:
                    act_dict["price_confidence"] = price_confidence
                if booking_url:
                    act_dict["booking_url"] = booking_url
                if act_type:
                    act_dict["type"] = act_type

            hours = str(a.get("hours") or "").strip()
            if hours:
                act_dict["hours"] = hours

            restaurants = []
            if isinstance(a.get("restaurants"), list):
                for r in a.get("restaurants"):
                    if isinstance(r, dict):
                        restaurants.append({
                            "name": str(r.get("name") or ""),
                            "cuisine": str(r.get("cuisine") or ""),
                            "price_range": str(r.get("price_range") or ""),
                            "rating": str(r.get("rating") or ""),
                            "tip": str(r.get("tip") or ""),
                        })
            if restaurants:
                act_dict["restaurants"] = restaurants
            activities.append(act_dict)

        # Guarantee Day 1 Check-in activity if not present
        if is_first_day and has_hotel_data and not has_accommodation:
            activities.insert(0, {
                "time": "14:00",
                "name": "Hotel Check-in",
                "tip": "Check in and settle into your accommodation.",
                "cost": f"{hotel_price_range} / night" if hotel_price_range else "See Stays tab",
                "price_source": "Google Hotels",
                "price_basis": (
                    f"Nightly rate range across hotel options found for this trip: {hotel_price_range}."
                    if hotel_price_range else
                    "See the Stays tab for hotel pricing options."
                ),
                "price_confidence": "Estimated",
                "type": "accommodation",
            })

        day_items.append({
            "kind": "day",
            "day": _as_int(d.get("day"), len(day_items) + 1),
            "theme": str(d.get("theme") or ""),
            "activities": activities,
        })

    if not day_items:
        raise ValueError("Generated plan had no days")

    return title, [meta] + day_items


async def generate_replacement_activity(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    day_no: int,
    theme: str,
    time_slot: str,
    old_name: str,
    reason: str,
    existing_names: list[str],
    api_key: str,
) -> dict:
    """Generate ONE replacement activity with restaurants."""
    prompt = _build_swap_prompt(
        destination=destination,
        mood=mood,
        budget=budget,
        currency=currency,
        day_no=day_no,
        theme=theme,
        time_slot=time_slot,
        old_name=old_name,
        reason=reason,
        existing_names=existing_names,
    )
    # thinking_budget=0 disables gemini-2.5-flash's hidden "thinking" tokens —
    # they otherwise eat the output budget and can leave zero text for a small
    # task like this. A single activity needs no reasoning, so turn it off.
    text, _ = await _call_gemini(prompt, api_key, max_tokens=2048, thinking_budget=0)
    data = _parse_json(text)

    name = str(data.get("name") or data.get("attraction_name") or "").strip()
    if not name:
        raise ValueError("Replacement had no place name")

    act_type = str(data.get("type") or "").strip().lower()
    restaurants = []
    if isinstance(data.get("restaurants"), list):
        for r in data.get("restaurants"):
            if isinstance(r, dict):
                restaurants.append({
                    "name": str(r.get("name") or ""),
                    "cuisine": str(r.get("cuisine") or ""),
                    "price_range": str(r.get("price_range") or ""),
                    "rating": str(r.get("rating") or ""),
                    "tip": str(r.get("tip") or ""),
                })

    res = {
        "time": time_slot or str(data.get("time") or ""),
        "name": name,
        "tip": str(data.get("tip") or data.get("note") or ""),
        "cost": str(data.get("cost") or ""),
    }
    if act_type:
        res["type"] = act_type
    if restaurants:
        res["restaurants"] = restaurants
    return res


def _build_swap_prompt(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    day_no: int,
    theme: str,
    time_slot: str,
    old_name: str,
    reason: str,
    existing_names: list[str],
) -> str:
    avoid = ", ".join(n for n in existing_names if n) or "(none)"
    why = reason.strip() or "the traveler wants a different option"
    slot = time_slot or "this time slot"
    return f"""A traveler is on a {mood} trip to {destination} (total budget {int(budget)} {currency}).

On Day {day_no} ("{theme}"), one stop needs replacing.
- Stop to replace: "{old_name}" (scheduled for {slot})
- Why replace it: {why}

These places are ALREADY in the trip - do NOT suggest any of them again:
{avoid}

Suggest exactly ONE different, real, well-known place or activity near "{destination}" that:
- fits the day's "{theme}" theme and the "{slot}" time slot,
- matches the "{mood}" travel style,
- keeps within the overall {int(budget)} {currency} budget,
- is NOT in the avoid-list above.

Return ONLY a JSON object with this exact shape (no markdown, no commentary):
{{ "time": "{slot}", "name": "Place or activity name", "tip": "Short practical tip under ~12 words", "cost": "{currency} amount or 'Free'", "type": "transport|attraction|dining|exploration|accommodation|other", "restaurants": [] }}
"""



def _build_prompt(
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
    travelers: int = 1,
    hotel_price_range: str = "",
    confirmed_flight: dict | None = None,
    departure_city: str = "",
    departure_country: str = "",
    nationality: str = "",
    has_visa: bool = False,
    legs: list[dict] | None = None,
    geo: "DestinationContext | None" = None,
    correction: str = "",
) -> str:
    nights = days - 1 if days > 1 else 0
    per_person = int(budget / travelers) if travelers > 0 else int(budget)

    # The route is decided before this call (see `plan_city_legs`) because the
    # per-leg hotel search needs the cities. Handing it back to the model as a
    # fixed table is what stops the itinerary wandering across cities the trip
    # has no accommodation in — a tester's plan moved through four Cambodian
    # cities while every day linked to one city's hotels.
    # ── Geographic identity ────────────────────────────────────────────────
    # Emitted whenever the destination resolved, INDEPENDENT of leg count. That
    # independence is the fix: `route_rules` below only fires for multi-city
    # trips, so a single-city trip previously reached the model with no
    # geographic constraint whatsoever beyond the bare destination string. That
    # is the hole a trip to "Sri Vijaya Puram" fell through, coming back as a
    # tour of Kandy because the name reads as Sri Lankan.
    geo_rules = ""
    if geo is not None and geo.resolved:
        # A single city is a day-trip radius; a multi-city route needs to span
        # its own legs plus a day trip at either end.
        radius_km = 150
        if legs and len(legs) > 1:
            radius_km = 400
        alias_line = ""
        if geo.aliases:
            spelled = " and ".join(f'"{a.title()}"' for a in geo.aliases)
            alias_line = (
                f"- {geo.display_name} is also known as {spelled}. Those names all "
                f"refer to the SAME place in {geo.country or geo.country_code}.\n"
            )
        coord_line = ""
        if geo.has_coords:
            coord_line = (
                f"- It is at coordinates {geo.latitude:.4f}, {geo.longitude:.4f}. "
                f"Everything you name must be within roughly {radius_km} km of there.\n"
            )
        country = geo.country or geo.country_code
        geo_rules = f"""
CRITICAL - DESTINATION IDENTITY (this overrides your prior knowledge):
- This trip is to {geo.label()}. It is in {country}. It is NOT in any other country.
{coord_line}{alias_line}- EVERY city, town, landmark, temple, museum, beach, restaurant, dish and
  transport link you name MUST be a real place in {country}.
- If the destination's name resembles a place in another country, ignore the
  resemblance completely. The country stated above is authoritative.
- Never substitute a similarly-named or culturally-adjacent place from a
  neighbouring country. If a name you are about to write is not in {country},
  it is wrong - use the google_search tool to find a real equivalent that is.
- Unless the plan explicitly crosses a border for a named day trip that returns
  the same day, every overnight stay is in {country}.
"""

    # A regeneration after drift was detected. Naming the specific places that
    # were wrong works far better than repeating the constraint louder.
    correction_rules = ""
    if correction:
        country = (geo.country or geo.country_code) if geo is not None else ""
        correction_rules = f"""
CRITICAL - YOUR PREVIOUS ATTEMPT WAS GEOGRAPHICALLY WRONG:
{correction}
Those places are not in {country}. You have relocated the trip to the wrong
country. Rewrite the ENTIRE plan from scratch using only real places in
{country}. Do not reuse any place name from the previous attempt.
"""

    route_rules = ""
    if legs and len(legs) > 1:
        table = "\n".join(
            f"  Day {l['start_day']}-{l['end_day']}: {l['city']} (sleep in {l['city']})"
            if l["start_day"] != l["end_day"]
            else f"  Day {l['start_day']}: {l['city']} (sleep in {l['city']})"
            for l in legs
        )
        route_rules = f"""
CRITICAL - FIXED ROUTE (do not change it, do not add or drop a city):
{table}

- Every activity on a day must be in, or a day trip from, that day's city above.
- The first day of each leg after the first MUST open with a "transport"
  activity covering the journey from the previous city, priced for {travelers}.
- The last day of each leg must END in that leg's city, because that is where
  the traveller sleeps and where their hotel was booked.
- Do not schedule an overnight anywhere not listed above.
"""

    hotel_rules = ""
    if hotel_price_range:
        hotel_rules = f"""
CRITICAL — ACCOMMODATION (DO NOT NAME OR INVENT A SPECIFIC HOTEL):
- Live hotel search found options ranging {hotel_price_range} per night.
- The actual hotel choices are shown separately to the user on their own
  Stays screen — naming one specific property here would contradict it.

Accommodation Scheduling Rules:
1. Day 1 MUST include check-in: "name": "Hotel Check-in", "type": "accommodation", "cost": "{hotel_price_range} / night", "price_source": "Google Hotels", "price_basis": "Nightly rate range across hotel options found for this trip: {hotel_price_range}.", "price_confidence": "Estimated", "tip": "Check in and settle into your accommodation."
2. Day {days} (Final Day) MUST include check-out: "name": "Hotel Check-out", "type": "accommodation", "cost": "{hotel_price_range} / night", "price_source": "Google Hotels", "tip": "Complete check-out and luggage drop before departure."
3. Do NOT name a specific hotel or invent a hotel name anywhere in the plan — use "your hotel" or "the accommodation" instead.
"""

    flight_rules = ""
    if confirmed_flight and (confirmed_flight.get("title") or confirmed_flight.get("name")):
        f_name = confirmed_flight.get("title") or confirmed_flight.get("name")
        f_route = confirmed_flight.get("route", "")
        f_currency = confirmed_flight.get("currency") or ""
        f_per_traveler = confirmed_flight.get("price_per_traveler")
        if f_per_traveler:
            trip_word = "return" if confirmed_flight.get("trip_type") == "round_trip" else "one-way"
            f_price = f"{f_currency} {f_per_traveler:,.0f} per traveller ({trip_word})"
        else:
            f_price = confirmed_flight.get("estimated_price_range", "")
        flight_rules = f"""
CRITICAL — CONFIRMED FLIGHT ROUTE:
- Flight: "{f_name}"{f' ({f_route})' if f_route else ''}
- Fare: {f_price}
- Provider: Google Flights
"""

    # No confirmed flight means either the traveler turned flights off, or (a
    # domestic pair like Kinniya->Colombo that shares one airport) there was
    # never a real flight route to confirm. Either way, the model was
    # previously never told who's traveling or from where, and would invent
    # an arrival cost with zero grounding — which is how a Kinniya->Colombo
    # bus/train trip ended up priced like it needed a private charter. This
    # only covers the trip's actual start (Day 1); transport between later
    # legs is already covered by route_rules above.
    ground_transport_rules = ""
    if (
        not confirmed_flight
        and departure_city
        and departure_city.strip().lower() != destination.strip().lower()
    ):
        ground_transport_rules = f"""
CRITICAL — GETTING TO {destination.upper()} (NO FLIGHT BOOKED FOR THIS TRIP):
- The traveler starts from "{departure_city}"{f', {departure_country}' if departure_country else ''} and has NOT booked a flight — assume they travel by bus, train, shared taxi, or car.
- Day 1 MUST open with a "transport" activity covering this journey, named something like "Travel from {departure_city} to {destination}".
- Estimate its cost from REAL, typical bus/train/shared-taxi fares for this specific route and distance — do not invent a large or round number. A domestic ground journey of a few hundred kilometers or less is normally a small fraction of the total trip budget, not a major line item.
- If the distance is short (under ~2 hours), keep the cost minimal and say so in the tip.
"""

    if has_visa:
        visa_rules = """CRITICAL — VISA GUIDANCE RULES:
The traveler ALREADY holds a valid visa for this trip.
Set "visa".status to "already_have", "visa".processing_days_min to 0, "visa".processing_days_max to 0, and "visa".note to "Visa already acquired — you are ready to travel!".
Do NOT output any visa application procedures, application steps, or visa warnings."""
    else:
        visa_rules = f"""CRITICAL — VISA GUIDANCE RULES:
1. The traveler needs visa guidance holding a "{nationality or 'not provided'}" passport for "{destination}".
2. Use the google_search tool to check the actual, current visa requirements, application procedure (e.g. online eVisa portal, embassy application, visa on arrival), and estimated processing time in business days.
3. If nationality is "not provided", set "visa".status to "unknown" and "visa".note to "Add your nationality in your profile to get visa guidance for this trip." — do not guess a nationality.
4. "visa".status must be exactly one of: "needed" (an advance visa application is required — e-visas that still take real processing time count as "needed"), "available" (visa on arrival, or an e-visa/ETA that is normally issued within a day or two), "not_needed" (visa-free entry, or the trip is domestic).
5. Only when status is "needed", set "visa".processing_days_min/processing_days_max to a realistic real-world range for that nationality/destination pair (e.g. 15-20 business days) — found via search, not invented. Leave both at 0 for "available"/"not_needed"/"unknown".
6. In "visa".note, provide clear, step-by-step application guidance, required documents, and where to apply.
7. "visa".confidence follows the same Fixed/Typical/Estimated scale used for prices below."""

    # The destination line used to be the model's ONLY geographic input. Each
    # extra line here is emitted only when we actually resolved that fact, so
    # an unresolved destination produces byte-identical output to before.
    dest_anchor = (
        f"{geo.label()} ({geo.country or geo.country_code})"
        if geo is not None and geo.resolved
        else f'"{destination}"'
    )
    dest_lines = f"- Destination: {geo.display_name if geo is not None else destination}\n"
    if geo is not None and geo.resolved:
        dest_lines += f"- Country (authoritative): {geo.country or geo.country_code} ({geo.country_code})\n"
        if geo.admin_area:
            dest_lines += f"- Region / state: {geo.admin_area}\n"
        if geo.has_coords:
            dest_lines += f"- Coordinates: {geo.latitude:.4f}, {geo.longitude:.4f}\n"
        if geo.aliases:
            dest_lines += f"- Also known as / formerly: {', '.join(a.title() for a in geo.aliases)}\n"

    return f"""Design a {days}-day travel Odyssey for a group of {travelers} traveler(s).
{correction_rules}{geo_rules}
Trip brief:
{dest_lines}- Travel style / mood: {mood}
- Group size: {travelers} traveler(s)
- Total budget: {int(budget)} {currency} for the whole group of {travelers} (hard cap for the entire trip; about {per_person} {currency} per person)
- Currency to use in all costs: {currency}
- Traveler nationality (passport held): {nationality or "not provided"}
- Traveler already has visa: {"Yes" if has_visa else "No"}
{route_rules}
{hotel_rules}
{flight_rules}
{ground_transport_rules}
{visa_rules}

CRITICAL — LIVE SEARCH GROUNDING RULES:
1. You have been given live Google Search access via the google_search tool for this request. You MUST use it to find current prices — do not recall prices from memory/training data.
2. For EVERY costed activity (attraction tickets, transit fares, typical meal prices, hotel/night rates), search for that specific item before writing its cost. Do not estimate from memory if a search is possible.
3. If a search genuinely returns no usable price for an item, do NOT invent one. Set "price_confidence": "Estimated" and state in "price_basis": "No current search result found; figure is a general regional estimate, not sourced."
4. "price_source" must name the actual source you found via search (the site, publisher, or official page name) — never a generic label like "Official Ticket" or "Menu Avg" with no real anchor behind it.
5. Do not fabricate deep links to specific hotels, restaurants, or attractions anywhere in the output. The ONLY links allowed anywhere in this JSON are the three fixed "booking_partners" URLs given below, unchanged. If you don't have a verified link, omit it — never guess one.
6. Prefer official/primary sources (venue's own site, government tourism site, transit authority) over blogs or aggregators when search results offer a choice.
7. For "attraction", "dining", and "accommodation" activities only, search for the venue's real opening hours and put them in "hours" (e.g. "9:00 AM – 6:00 PM" or "Open until 9:00 PM today"). If search doesn't confidently confirm real hours, leave "hours" as an empty string — never guess or invent them. Leave "hours" empty for "transport"/"exploration"/"other" activities, which aren't a single bookable venue.

CRITICAL BUDGET PRIORITY RULES:
1. Flights & Transit (Priority 1) and Stay & Accommodation (Priority 2) MUST BE ALLOCATED FIRST!
2. Allocate realistic funds for Flights (~40-50%) and Stay (~30-35%).
3. Stay (Accommodation) budget MUST NEVER be near zero or under 25% of total budget unless flights alone exceed 70% or total budget is an ultra-saver amount.
4. Food & Dining (~10-15%) and Activities (~5-10%) share the remaining budget.

CRITICAL PRICE JUSTIFICATION RULES:
1. Every non-zero cost MUST cite a concrete, named reference point found via search — never a vague category.
2. "price_basis" MUST state the actual anchor rate/figure found and any currency conversion applied, in one sentence.
3. Add "price_confidence" to every costed activity, one of:
   - "Fixed" — official/published rate confirmed via search (museum tickets, train fares, park entry).
   - "Typical" — well-established market rate with some variance, confirmed via search (metered taxi, chain hotel breakfast, common street food).
   - "Estimated" — no reliable search result found, or inherently variable (ride-hail surge, informal bargaining, seasonal swings) — must name what could move the price.
4. Self-honesty rule: these labels reflect genuine confidence based on what search actually returned, not how official something sounds. Do not label something "Fixed" without a real search result backing it.
5. Round to sensible increments (nearest 1, 5, or 10 in local currency) unless an official rate is exact. Never fabricate false precision (e.g. "23.47").
6. For "dining" activities, "restaurants" entries should be real, findable venues confirmed via search, or realistic venue *types* for the area if no specific venue is confirmed — never fabricated proper names presented as fact.
7. The sum of all activity costs must match the "food" + "activities" portions of budget_breakdown. Recompute if they drift.

Return ONLY a JSON object with EXACTLY this shape:
{{
  "title": "Evocative 2-4 word trip name",
  "destination": "{destination}",
  "days": {days},
  "nights": {nights},
  "currency": "{currency}",
  "summary": "1-2 sentence overview matching the '{mood}' style.",
  "budget_split": "Short split, e.g. '35% Stay - 45% Transit - 12% Food - 8% Activities'",
  "budget_breakdown": {{
    "stay": 0,
    "transit": 0,
    "food": 0,
    "activities": 0,
    "total": {int(budget)}
  }},
  "visa": {{
    "status": "needed | available | not_needed | unknown",
    "processing_days_min": 0,
    "processing_days_max": 0,
    "note": "One sentence on the requirement/process, specific to this nationality and destination.",
    "confidence": "Fixed | Typical | Estimated"
  }},
  "biggest_risk": "One sentence (under 20 words) naming the single biggest risk/watch-out specific to this trip — peak-season crowding, monsoon/weather timing, visa processing lead time, etc. Do not just restate the visa note.",
  "logistics": ["3-5 short practical tips: transport, money, SIM, entry fees, timing"],
  "practical_info": {{
    "money": "1-2 sentences: cash vs card norms, ATM availability, typical tipping.",
    "connectivity": "1-2 sentences: local SIM/eSIM options or WiFi availability.",
    "safety": "1-2 sentences: general safety notes or areas needing caution.",
    "customs": "1-2 sentences: key local etiquette to respect."
  }},
  "booking_partners": [
    {{ "name": "Booking.com", "type": "hotels", "url": "https://www.booking.com" }},
    {{ "name": "Viator", "type": "tours", "url": "https://www.viator.com" }},
    {{ "name": "Skyscanner", "type": "transit", "url": "https://www.skyscanner.com" }}
  ],
  "day_plans": [
    {{
      "day": 1,
      "theme": "Short day theme",
      "activities": [
        {{
          "time": "09:00",
          "name": "Place or activity name",
          "tip": "Short practical tip",
          "hours": "Real opening hours if attraction/dining/accommodation and confirmed via search, else ''",
          "cost": "{currency} amount or 'Free'",
          "price_source": "Named source actually found via search (site/publisher/official page)",
          "price_basis": "1-sentence statement of the actual anchor rate/figure found and any conversion applied",
          "price_confidence": "Fixed | Typical | Estimated",
          "type": "transport|attraction|dining|exploration|accommodation|other",
          "restaurants": [
            {{
              "name": "Restaurant Name",
              "cuisine": "Cuisine type (e.g. Seafood, Italian, Local)",
              "price_range": "{currency} 25 - 45 or $$",
              "rating": "4.6 ★",
              "tip": "Short booking tip or signature dish"
            }}
          ]
        }}
      ]
    }}
  ]
}}

Rules for "type" field in each activity:
- "transport": Travel/transit between locations. Cost = estimated fare.
- "attraction": Ticketed landmarks, museums, temples, parks. Cost = ticket price.
- "dining": Meals (Breakfast, Lunch, Dinner). Cost = estimated meal cost. MUST include "restaurants" array with 2-4 real top-rated dining suggestions with name, cuisine, price_range, rating, and tip. For non-dining activities, keep "restaurants": [].
- "exploration": Free self-guided walking, public markets, viewpoints. Cost = "Free".
- "accommodation": Hotel check-in/check-out. Cost = "Free" (room cost lives in budget_breakdown).
- "other": Any other activity.

General rules:
- Produce exactly {days} entries in "day_plans", each with 3-5 activities.
- Keep the SUM of all activity costs within the "activities" and "food" budget portion of {int(budget)} {currency}.
- Use real, recognisable places in and around {dest_anchor}.
- Be concise; tips under ~12 words.
"""


async def _call_gemini(
    prompt: str,
    api_key: str,
    max_tokens: int = 4096,
    thinking_budget=None,
    use_grounding: bool = False,
) -> tuple[str, list[dict]]:
    """Call Gemini with optional Google Search grounding.

    Returns (text, grounding_chunks) where grounding_chunks is a list of
    {"title": ..., "uri": ...} dicts extracted from the response's
    groundingMetadata. Empty list when grounding is disabled or absent.
    """
    api_key = (api_key or "").strip().strip('"').strip("'")
    base_generation_config = {
        "temperature": 0.8,
        "maxOutputTokens": max_tokens,
    }
    # Google Gemini API strictly rejects responseMimeType: 'application/json' when tools/grounding are active (HTTP 400).
    if not use_grounding:
        base_generation_config["responseMimeType"] = "application/json"
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    # Odyssey is a one-shot background job, so a single 503 would permanently
    # fail it. Rotate through the model chain twice (with a short backoff
    # between passes) so a model that's overloaded right now is bypassed for
    # one that's currently healthy.
    data = None
    attempts = _MODELS * 2
    # Grounded calls may take longer due to live search; use extended timeout
    timeout = 90.0 if use_grounding else 45.0
    async with httpx.AsyncClient(timeout=timeout) as client:
        for i, model in enumerate(attempts):
            generation_config = dict(base_generation_config)
            # Only gemini-2.5+ models support thinkingConfig; 1.5/2.0 reject it
            if thinking_budget is not None and ("2.5" in model or "thinking" in model):
                generation_config["thinkingConfig"] = {"thinkingBudget": thinking_budget}

            body = {
                "contents": [{"parts": [{"text": prompt}]}],
                "system_instruction": {"parts": [{"text": _SYSTEM}]},
                "generationConfig": generation_config,
            }

            # Attach Google Search grounding tool when requested.
            # This tells Gemini to actually search Google for real-time data
            # (prices, opening hours, etc.) instead of relying on training data.
            if use_grounding:
                body["tools"] = [{"google_search": {}}]

            try:
                sku = "gemini_flash_grounded" if use_grounding else "gemini_flash_generate"
                async with telemetry.track(
                    "gemini", f"odyssey_generate:{model}",
                    sku=sku,
                ) as t:
                    resp = await client.post(_model_url(model), json=body, headers=headers)
                    t.upstream(resp)
                if resp.status_code != 200 and i < len(attempts) - 1:
                    logger.warning(
                        "Gemini status %s for %s — falling through to next model (details: %s)",
                        resp.status_code, model, resp.text[:200],
                    )
                    # Brief pause once we've cycled the whole chain once (skip pause if 404)
                    if (i + 1) % len(_MODELS) == 0 and resp.status_code != 404:
                        await asyncio.sleep(1)
                    continue
                resp.raise_for_status()
                data = resp.json()
                break
            except Exception as e:
                if i < len(attempts) - 1:
                    logger.warning("Gemini exception for %s — falling through: %s", model, e)
                    continue
                raise e

    candidates = data.get("candidates") or []
    if not candidates:
        raise ValueError(f"Gemini returned no candidates (feedback={data.get('promptFeedback')})")
    cand = candidates[0]
    parts = (cand.get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    if not text.strip():
        raise ValueError(f"Gemini returned no text (finishReason={cand.get('finishReason')})")

    # Extract grounding chunks from the response metadata.
    # These are the real, verifiable sources Gemini actually searched.
    grounding_chunks = _extract_grounding_chunks(cand) if use_grounding else []

    return text, grounding_chunks


def _extract_grounding_chunks(candidate: dict) -> list[dict]:
    """Pull verified sources from Gemini's groundingMetadata.

    The REST API returns them at:
        candidate.groundingMetadata.groundingChunks[].web.{title, uri}
    """
    chunks = []
    try:
        metadata = candidate.get("groundingMetadata") or {}
        for chunk in metadata.get("groundingChunks") or []:
            web = chunk.get("web") or {}
            uri = web.get("uri") or ""
            title = web.get("title") or ""
            if uri:
                chunks.append({"title": title, "uri": uri})
    except (AttributeError, TypeError):
        pass
    return chunks


def _deduplicate_grounding_chunks(chunks: list[dict]) -> list[dict]:
    """Deduplicate grounding chunks by URI, preserving order."""
    seen = set()
    unique = []
    for chunk in chunks:
        uri = chunk.get("uri", "")
        if uri and uri not in seen:
            seen.add(uri)
            unique.append(chunk)
    return unique


def _parse_json(raw: str) -> dict:
    raw = (raw or "").strip()
    # Strip markdown code fences if present
    if raw.startswith("```"):
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)
        raw = raw.strip()
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end > start:
        try:
            parsed = json.loads(raw[start:end + 1])
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass
    # Attempt repair for truncated JSON cut off near token limits
    if start != -1:
        candidate = raw[start:]
        for suffix in ["}", "\n}", "\n]}", "\n]}}", "\n}]}}"]:
            try:
                parsed = json.loads(candidate + suffix)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass
    raise ValueError("Gemini did not return a JSON object")


def _logistics_text(raw) -> str:
    if isinstance(raw, str):
        return raw
    if isinstance(raw, list):
        return "\n".join(f"{i + 1}. {step}" for i, step in enumerate(raw))
    return ""


def _practical_info(raw) -> dict:
    d = raw if isinstance(raw, dict) else {}
    return {k: str(d.get(k) or "").strip() for k in ("money", "connectivity", "safety", "customs")}


_VISA_STATUSES = {"needed", "available", "not_needed", "already_have", "unknown"}


def _parse_visa_info(raw, *, nationality: str, final_start_date: str, has_visa: bool = False) -> dict:
    """Structured visa guidance for the traveler's nationality vs. the destination."""
    if has_visa:
        return {
            "status": "already_have",
            "processing_days_min": 0,
            "processing_days_max": 0,
            "note": "Visa already acquired — you are ready to travel!",
            "confidence": "Confirmed",
            "recommended_apply_by": None,
            "dates_too_tight": False,
        }

    if isinstance(raw, dict):
        status = str(raw.get("status") or "unknown").strip().lower()
        processing_days_min = _as_int(raw.get("processing_days_min"), 0)
        processing_days_max = _as_int(raw.get("processing_days_max"), 0)
        note = str(raw.get("note") or "").strip()
        confidence = str(raw.get("confidence") or "Estimated").strip()
    elif isinstance(raw, str) and raw.strip():
        status, processing_days_min, processing_days_max = "unknown", 0, 0
        note, confidence = raw.strip(), "Estimated"
    else:
        status, processing_days_min, processing_days_max = "unknown", 0, 0
        note, confidence = "", "Estimated"

    if status not in _VISA_STATUSES:
        status = "unknown"
    if not nationality and status != "already_have":
        status = "unknown"

    recommended_apply_by = None
    dates_too_tight = False
    if status == "needed" and processing_days_max > 0 and final_start_date:
        try:
            from datetime import date as _date, timedelta as _timedelta
            start_d = _date.fromisoformat(final_start_date)
            apply_by_d = start_d - _timedelta(days=processing_days_max)
            recommended_apply_by = apply_by_d.isoformat()
            dates_too_tight = apply_by_d < _date.today()
        except (ValueError, TypeError):
            pass

    return {
        "status": status,
        "processing_days_min": processing_days_min,
        "processing_days_max": processing_days_max,
        "note": note,
        "confidence": confidence,
        "recommended_apply_by": recommended_apply_by,
        "dates_too_tight": dates_too_tight,
    }


def _assemble_booking_plan(
    *,
    primary_flight: dict | None,
    primary_hotel: dict | None,
    booking_partners: list,
    visa_info: dict,
) -> list[dict]:
    """Turns already-generated flight/hotel/partner data into a priority-ordered
    checklist. No LLM call — everything here was already fetched or generated."""
    visa_required = visa_info.get("status") == "needed"
    visa_reason = visa_info.get("note") or "A visa is required for this trip."
    booking_label = "BOOK AFTER VISA" if visa_required else "BOOK NOW"

    plan: list[dict] = []
    if visa_required:
        plan.append({
            "label": "BOOK AFTER VISA",
            "item": "Any non-refundable booking",
            "reason": visa_reason,
            "url": "",
        })
    if primary_flight and (primary_flight.get("title") or primary_flight.get("name")):
        plan.append({
            "label": booking_label,
            "item": str(primary_flight.get("title") or primary_flight.get("name") or "Flight"),
            "reason": visa_reason if visa_required else "Confirmed live fare — prices move, lock it in early.",
            "url": str(primary_flight.get("booking_url") or ""),
        })
    if primary_hotel and primary_hotel.get("name"):
        plan.append({
            "label": booking_label,
            "item": str(primary_hotel.get("name") or "Hotel"),
            "reason": visa_reason if visa_required else "Confirmed live rate — lock it in early.",
            "url": str(primary_hotel.get("booking_url") or primary_hotel.get("serpapi_link") or ""),
        })
    for p in booking_partners:
        if not isinstance(p, dict):
            continue
        p_type = str(p.get("type") or "").strip().lower()
        if p_type == "tours":
            label, reason = "BOOK CLOSER TO TRAVEL", "Tours and activities are usually flexible closer to the date."
        elif p_type == "transit":
            label, reason = "CAN WAIT", "Local transit is easy to arrange on arrival."
        else:
            continue
        plan.append({
            "label": label,
            "item": str(p.get("name") or ""),
            "reason": reason,
            "url": str(p.get("url") or ""),
        })
    return plan


def _as_int(value, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _extract_price_bounds(price_str) -> tuple[float, float] | None:
    """Parses "USD 200 - 400" into (200.0, 400.0), or "USD 300" into (300.0, 300.0).

    Legacy path only: strategies carrying structured `price_per_traveler` never
    go through string parsing. Kept because two parsers used to disagree on the
    same string — this one is the single definition of what a range means.
    """
    if not price_str:
        return None
    cleaned = re.sub(r"[^\d.\-\s]", " ", str(price_str))
    numbers = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", cleaned)]
    if not numbers:
        return None
    return (min(numbers), max(numbers))


def _extract_lowest_price(price_str: str) -> float:
    """Extracts the lowest numeric value from a price range or price string."""
    if not price_str:
        return 0.0
    cleaned = re.sub(r"[^\d.\-\s]", "", str(price_str))
    numbers = re.findall(r"\d+(?:\.\d+)?", cleaned)
    if numbers:
        try:
            return float(numbers[0])
        except ValueError:
            pass
    return 0.0


async def generate_replacement_partner(
    *,
    destination: str,
    partner_name: str,
    partner_type: str,
    reason: str,
    avoid_names: list[str],
    api_key: str,
) -> dict:
    avoid = ", ".join(avoid_names) or "(none)"
    why = reason.strip() or "the traveler wants a different option"
    
    prompt = f"""A traveler is on a trip to "{destination}".
They want to replace the booking platform/app "{partner_name}" of type "{partner_type}" because: {why}.

These platforms/apps are already used or rejected for this trip - do NOT suggest any of them:
{avoid}

Suggest exactly ONE other real, popular travel website, booking platform, or local app commonly used for "{destination}" of type "{partner_type}" (hotels, tours, or transit) that is different from the avoided list.
- For Russia: Use Yandex Travel, Ostrovok, or Aviasales. Do not use Booking.com or Skyscanner for Russia.
- For Sri Lanka: Use Booking.com, PickMe, Klook, or similar.
- For general South-East Asia: Use Agoda, Grab, or Klook.
- For Western Europe / Americas: Use Booking.com, Viator, Skyscanner.

Return ONLY a JSON object with this exact shape:
{{ "name": "Platform Name", "type": "{partner_type}", "url": "Search or landing URL for this platform in {destination}" }}
"""
    text, _ = await _call_gemini(prompt, api_key, max_tokens=1024, thinking_budget=0)
    data = _parse_json(text)
    return {
        "name": str(data.get("name") or "").strip(),
        "type": partner_type,
        "url": str(data.get("url") or "").strip(),
    }
