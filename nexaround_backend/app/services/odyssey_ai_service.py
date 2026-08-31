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
import urllib.parse
import httpx
from app.services import telemetry, trip_cost_floor
from app.services.serpapi_service import (
    SerpApiService,
    format_flight_results_for_gemini,
    format_hotel_results_for_gemini,
    extract_hotel_strategies_from_serpapi,
    extract_flight_strategies_from_serpapi,
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


def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_SYSTEM = (
    "You are NexAround's expert local travel designer. "
    "You craft realistic, budget-aware, day-by-day trip blueprints. You always "
    "reply with a single JSON object that matches the requested schema exactly - "
    "no markdown, no commentary, no code fences."
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
) -> dict:
    """The `odyssey_meta` header stored as items[0]. Used both for the initial
    'generating' placeholder and for the finished plan."""
    return {
        "kind": "odyssey_meta",
        "destination": destination,
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


async def _resolve_airport_code(place: str, country: str, api_key: str) -> str:
    """Resolve a place name to an IATA code SerpApi will accept.

    Static table first (free and instant, covers the common routes), then one
    small Gemini lookup for anything unknown, cached per process. Returns ""
    when nothing usable comes back, which tells the caller to skip the live
    search rather than burn a SerpApi credit on a request that will 400.
    """
    raw = (place or "").strip()
    if not raw:
        return ""

    # A city we know wins over anything else — "London" must expand to its
    # four airports rather than being taken at face value.
    key = raw.lower().split(",")[0].strip()
    if key in _AIRPORT_CODES:
        return _AIRPORT_CODES[key]

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
    prompt = (
        f'Which airports serve "{location}"? Answer with IATA airport codes ONLY, '
        f"comma-separated, most important first, maximum 3. If the city has several airports "
        f"list them all (e.g. London -> LHR,LGW,STN). If the place has no airport of its own, "
        f"give the nearest major international airport. Never answer with a metropolitan area "
        f"code such as LON or NYC. No other text."
    )
    try:
        text, _ = await _call_gemini(prompt, api_key, max_tokens=32, thinking_budget=0)
        codes = re.findall(r"\b([A-Z]{3})\b", (text or "").upper())
        # Metro codes are silently rejected by Google Flights — drop any that
        # slipped through rather than shipping a search that returns nothing.
        codes = [c for c in dict.fromkeys(codes) if c not in _METRO_CODES][:3]
        if codes:
            code = ",".join(codes)
            _airport_code_cache[cache_key] = code
            logger.info("Resolved airport code for '%s' -> %s", location, code)
            return code
    except Exception as e:
        logger.warning(f"Airport code lookup failed for '{location}': {e}")

    return ""


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

        # Extract origin & destination airport/city from route (e.g. "CMB → LHR")
        route_str = str(strat.get("route") or "")
        route_origin = departure_city
        route_dest = destination
        if route_str:
            r_parts = [p.strip() for p in route_str.replace("->", "→").split("→") if p.strip()]
            if r_parts:
                route_origin = r_parts[0]
            if len(r_parts) > 1:
                route_dest = r_parts[-1]

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

    # ── Primary path: SerpApi direct extraction ──────────────────────────────
    if serpapi_key:
        try:
            # SerpApi needs airport codes, not place names — resolve first so
            # the search doesn't 400 and drop us into estimation.
            origin_code, dest_code = await asyncio.gather(
                _resolve_airport_code(departure_city, departure_country, api_key),
                _resolve_airport_code(destination, "", api_key),
            )
            if not origin_code or not dest_code:
                raise ValueError(
                    f"could not resolve airport codes ({departure_city!r} -> {origin_code!r}, "
                    f"{destination!r} -> {dest_code!r})"
                )

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
- In the "route" field, always use real IATA airport codes (e.g., CMB, BKK, KUL, NRT, LHR). If the departure city (e.g., Kinniya) does not have an airport, use the nearest major airport (e.g., CMB for Colombo).
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
- "route": Short IATA airport code route (e.g., "CMB → KUL").
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
      "route": "CMB → KUL",
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
      "route": "CMB → KUL",
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
      "route": "CMB → KUL",
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
    
    Option A: Uses SerpAPI results directly with 4.0★ minimum rating filter.
    Gemini is NOT used for hotel selection — prices, ratings, and hotel names
    come straight from Google Hotels via SerpAPI for 100% accuracy.
    
    Falls back to Gemini-based generation only if SerpAPI returns no results.
    """

    # ── Primary path: SerpAPI direct extraction ──────────────────────────────
    if serpapi_key:
        try:
            logger.info("Fetching live hotel data via SerpApi (Google Hotels) with 4.0★ min rating...")
            serp = SerpApiService(serpapi_key)
            serp_result = await serp.search_hotels(
                destination=destination,
                check_in_date=hotel_check_in_date,
                check_out_date=hotel_check_out_date,
                adults=travelers,
                currency=currency,
                min_rating=4.0,  # Only 4★+ hotels
            )

            properties = serp_result.get("properties") or []
            if properties:
                logger.info(f"SerpAPI returned {len(properties)} hotels rated 4.0★+ for {destination}")
                result = extract_hotel_strategies_from_serpapi(
                    serp_result,
                    destination=destination,
                    currency=currency,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    travelers=travelers,
                    max_hotels=4,
                )
                return result
            else:
                logger.warning(f"SerpAPI returned 0 hotels after 4.0★ filter for {destination}. "
                              "Trying with 3.5★ minimum...")
                # Retry with slightly lower threshold
                serp_result = await serp.search_hotels(
                    destination=destination,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    adults=travelers,
                    currency=currency,
                    min_rating=3.5,
                )
                properties = serp_result.get("properties") or []
                if properties:
                    logger.info(f"SerpAPI returned {len(properties)} hotels rated 3.5★+ for {destination}")
                    result = extract_hotel_strategies_from_serpapi(
                        serp_result,
                        destination=destination,
                        currency=currency,
                        check_in_date=hotel_check_in_date,
                        check_out_date=hotel_check_out_date,
                        travelers=travelers,
                        max_hotels=4,
                    )
                    return result

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
        return data
    except Exception as e:
        logger.error(f"Failed to generate hotel strategies: {e}")
        return {}


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
    flight_start_date: str = "",
    flight_end_date: str = "",
    include_hotels: bool = False,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
    start_date: str = "",
    end_date: str = "",
) -> tuple[str, list[dict]]:
    """Generate the plan. Returns (title, items) ready to store on an Itinerary."""
    final_destination = str(destination)

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
        if include_flights and departure_city:
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
                )
            except Exception as e:
                logger.error(f"Flight strategy sub-job failed: {e}")
                return {}
        return {}

    async def _get_hotels():
        if include_hotels:
            try:
                return await generate_hotel_strategies(
                    destination=final_destination,
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

    # Extract primary recommended hotel entity from confirmed SerpAPI results
    primary_hotel = None
    if hotel_strategies and isinstance(hotel_strategies.get("strategies"), list):
        for s in hotel_strategies["strategies"]:
            if isinstance(s, dict) and s.get("name"):
                primary_hotel = s
                break

    # Extract primary flight entity if available.
    # Flight strategies key their label as "title"; only hotels use "name".
    # Testing for "name" here (copied from the hotel block above) meant
    # primary_flight was always None, so the flight rules never reached the
    # itinerary prompt and the flight never appeared in the booking checklist.
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
        confirmed_hotel=primary_hotel,
        confirmed_flight=primary_flight,
        nationality=nationality,
    )
    text, grounding_chunks = await _call_gemini(
        prompt, api_key, max_tokens=8192, thinking_budget=0, use_grounding=True,
    )
    plan = _parse_json(text)

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

    cheapest_hotel_cost = 0.0
    if hotel_strategies and isinstance(hotel_strategies.get("strategies"), list):
        h_costs = [
            _extract_lowest_price(s.get("total_estimated_cost") or s.get("price_per_night"))
            for s in hotel_strategies["strategies"]
            if isinstance(s, dict) and _extract_lowest_price(s.get("total_estimated_cost") or s.get("price_per_night")) > 0
        ]
        if h_costs:
            cheapest_hotel_cost = min(h_costs)

    # Base budget allocation. Parameterized on `total` so the same waterfall
    # can price out Minimum/Comfortable scenarios below without a second
    # Gemini call. `flight_cost` now varies per scenario: each budget scenario
    # is priced against *its own* flight tier, so the Budget tab and the
    # Flights tab quote the same transit figure. `cheapest_hotel_cost` stays
    # fixed (hotels are not tiered the same way) while `total` scales.
    def _waterfall(total: float, flight_cost: float = 0.0) -> dict:
        tot_ = total if total > 0 else 1.0
        flight_cost_ = flight_cost if flight_cost > 0 else cheapest_flight_cost

        if flight_cost_ > 0:
            transit_amt_ = min(flight_cost_, round(tot_ * 0.85, 2))
        else:
            transit_amt_ = round(tot_ * 0.30, 2)

        rem_after_transit_ = max(tot_ - transit_amt_, round(tot_ * 0.15, 2))

        if cheapest_hotel_cost > 0:
            stay_amt_ = min(cheapest_hotel_cost, round(rem_after_transit_ * 0.60, 2))
        else:
            stay_amt_ = round(rem_after_transit_ * 0.45, 2)

        rem_for_food_act_ = max(tot_ - (transit_amt_ + stay_amt_), round(tot_ * 0.05, 2))
        food_amt_ = round(rem_for_food_act_ * 0.60, 2)
        activities_amt_ = round(tot_ - (stay_amt_ + transit_amt_ + food_amt_), 2)

        return {
            "stay": stay_amt_,
            "transit": transit_amt_,
            "food": food_amt_,
            "activities": activities_amt_,
            "total": tot_,
        }

    final_currency = str(plan.get("currency") or currency)
    visa_info = _parse_visa_info(
        plan.get("visa"), nationality=nationality, final_start_date=final_start_date,
    )

    # Verdict: "is the budget realistic" is answered deterministically by the
    # same cost floor that already gates generation in itineraries.py — no
    # need to ask Gemini to judge it. Only "biggest_risk" comes from the model.
    floor = trip_cost_floor.minimum_budget(
        destination=final_destination,
        days=g_days,
        travelers=travelers,
        currency=final_currency,
        departure_country=departure_country,
        include_flights=include_flights,
    )
    min_days = floor.get("min_days", 2) if floor else 2
    duration_short = floor is not None and g_days < min_days
    budget_short = floor is not None and budget < floor["minimum"]
    feasible = floor is None or (not budget_short and not duration_short)
    minimum_required = floor["minimum"] if floor else None

    tot = float(budget) if budget > 0 else 1.0
    # The headline breakdown is the Recommended scenario, so the Budget tab and
    # the Recommended flight tier quote the same transit figure.
    budget_breakdown = _waterfall(tot, _tier_flight_cost("recommended"))
    stay_amt = budget_breakdown["stay"]
    transit_amt = budget_breakdown["transit"]
    food_amt = budget_breakdown["food"]
    activities_amt = budget_breakdown["activities"]

    # If the user's budget is already at or near the realistic cost floor,
    # we don't invent an impossible lower "minimum" scenario.
    # The user's budget IS the minimum viable tier (Recommended).
    is_near_minimum_floor = False
    if floor is not None and floor.get("minimum"):
        min_floor = float(floor["minimum"])
        if tot <= min_floor * 1.25:
            is_near_minimum_floor = True
    if (cheapest_flight_cost + cheapest_hotel_cost) > (tot * 0.75):
        is_near_minimum_floor = True

    budget_scenarios = {}
    if not is_near_minimum_floor:
        budget_scenarios["minimum"] = _waterfall(
            tot * _SCENARIO_MULTIPLIERS["minimum"], _tier_flight_cost("minimum")
        )
    budget_scenarios["recommended"] = budget_breakdown
    budget_scenarios["comfortable"] = _waterfall(
        tot * _SCENARIO_MULTIPLIERS["comfortable"], _tier_flight_cost("comfortable")
    )

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

    if floor is None:
        budget_tightness = "unknown"
    elif budget_short or (budget - floor["minimum"]) / floor["minimum"] < 0.2:
        budget_tightness = "tight"
    else:
        budget_tightness = "comfortable"

    if budget_short and duration_short:
        recommendation = (
            f"Reconsider — a trip to {final_destination} realistically requires at least {min_days} days "
            f"and about {final_currency} {minimum_required:,.0f} to cover return flights and standard stay."
        )
    elif duration_short:
        recommendation = (
            f"Caution on timing — {g_days} days is short for {final_destination}; "
            f"at least {min_days} days is recommended to account for travel time and sightseeing."
        )
    elif budget_short:
        recommendation = (
            f"Reconsider — raise the budget to at least {final_currency} "
            f"{minimum_required:,.0f} to realistically cover this trip."
        )
    elif budget_tightness == "tight":
        recommendation = "Proceed, but budget is tight — there's little buffer for extras."
    else:
        recommendation = "Proceed — budget and timing look workable."

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
        mood=mood,
        budget=budget,
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

            # 3. Strictly reconcile accommodation stops with confirmed primary hotel
            if is_acc and primary_hotel:
                has_accommodation = True
                hotel_name = primary_hotel.get("name", "Hotel")
                hotel_url = primary_hotel.get("booking_url") or primary_hotel.get("serpapi_link", "")
                hotel_rating = primary_hotel.get("rating", "4.5 ★")
                hotel_rate = primary_hotel.get("price_per_night", "")
                hotel_total_cost = primary_hotel.get("total_estimated_cost", "")

                if is_first_day:
                    act_dict["name"] = f"Check into {hotel_name}"
                    act_dict["tip"] = f"Check in and unpack at {hotel_name}. Rated {hotel_rating} on Google Hotels."
                elif is_last_day and ("check out" in name_lower or "check-out" in name_lower):
                    act_dict["name"] = f"Hotel Check-out at {hotel_name}"
                    act_dict["tip"] = f"Complete check-out and luggage drop at {hotel_name} before departure."
                else:
                    if "hotel" in name_lower or "resort" in name_lower:
                        act_dict["name"] = f"Rest & Freshen Up at {hotel_name}"

                act_dict["type"] = "accommodation"
                act_dict["cost"] = "Included in Stay"
                act_dict["price_source"] = "Google Hotels"
                act_dict["price_basis"] = f"Confirmed stay rate: {hotel_rate} / night ({hotel_total_cost} total stay)"
                act_dict["price_confidence"] = "Fixed"
                if hotel_url:
                    act_dict["booking_url"] = hotel_url
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
        if is_first_day and primary_hotel and not has_accommodation:
            hotel_name = primary_hotel.get("name", "Hotel")
            hotel_url = primary_hotel.get("booking_url") or primary_hotel.get("serpapi_link", "")
            hotel_rating = primary_hotel.get("rating", "4.5 ★")
            hotel_rate = primary_hotel.get("price_per_night", "")
            hotel_total_cost = primary_hotel.get("total_estimated_cost", "")
            activities.insert(0, {
                "time": "14:00",
                "name": f"Check into {hotel_name}",
                "tip": f"Check in and unpack at {hotel_name}. Rated {hotel_rating} on Google Hotels.",
                "cost": "Included in Stay",
                "price_source": "Google Hotels",
                "price_basis": f"Confirmed stay rate: {hotel_rate} / night ({hotel_total_cost} total stay)",
                "price_confidence": "Fixed",
                "type": "accommodation",
                "booking_url": hotel_url,
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
    confirmed_hotel: dict | None = None,
    confirmed_flight: dict | None = None,
    nationality: str = "",
) -> str:
    nights = days - 1 if days > 1 else 0
    per_person = int(budget / travelers) if travelers > 0 else int(budget)

    hotel_rules = ""
    if confirmed_hotel and confirmed_hotel.get("name"):
        h_name = confirmed_hotel.get("name")
        h_rate = confirmed_hotel.get("price_per_night", "")
        h_total = confirmed_hotel.get("total_estimated_cost", "")
        h_rating = confirmed_hotel.get("rating", "4.5 ★")
        h_url = confirmed_hotel.get("booking_url") or confirmed_hotel.get("serpapi_link", "")
        hotel_rules = f"""
CRITICAL — CONFIRMED ACCOMMODATION (STRICTLY BIND THIS HOTEL, ZERO HALLUCINATIONS):
- Primary Confirmed Hotel: "{h_name}"
- Provider: Google Hotels
- Star Rating: {h_rating}
- Confirmed Nightly Rate: {h_rate}
- Total Stay Cost: {h_total}
- Direct Booking Link: {h_url}

Accommodation Scheduling Rules:
1. Day 1 MUST include check-in: "name": "Check into {h_name}", "type": "accommodation", "cost": "Included in Stay", "price_source": "Google Hotels", "price_basis": "Confirmed live rate: {h_rate} / night ({h_total} total stay)", "price_confidence": "Fixed", "booking_url": "{h_url}", "tip": "Check in at {h_name}. Rated {h_rating} on Google Hotels."
2. Day {days} (Final Day) MUST include check-out: "name": "Hotel Check-out at {h_name}", "type": "accommodation", "cost": "Included in Stay", "price_source": "Google Hotels", "booking_url": "{h_url}"
3. STRICTLY use "{h_name}" for all hotel references in the plan.
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

    return f"""Design a {days}-day travel Odyssey for a group of {travelers} traveler(s).

Trip brief:
- Destination: {destination}
- Travel style / mood: {mood}
- Group size: {travelers} traveler(s)
- Total budget: {int(budget)} {currency} for the whole group of {travelers} (hard cap for the entire trip; about {per_person} {currency} per person)
- Currency to use in all costs: {currency}
- Traveler nationality (passport held): {nationality or "not provided"}
{hotel_rules}
{flight_rules}
CRITICAL — VISA GUIDANCE RULES:
1. Use the google_search tool to check the actual, current visa policy the destination applies to a traveler holding the "{nationality or "not provided"}" passport — do not recall this from memory/training data, visa policy changes.
2. If nationality is "not provided", set "visa".status to "unknown" and "visa".note to "Add your nationality in your profile to get visa guidance for this trip." — do not guess a nationality.
3. "visa".status must be exactly one of: "needed" (an advance visa application is required — e-visas that still take real processing time count as "needed"), "available" (visa on arrival, or an e-visa/ETA that is normally issued within a day or two), "not_needed" (visa-free entry, or the trip is domestic).
4. Only when status is "needed", set "visa".processing_days_min/processing_days_max to a realistic real-world range for that nationality/destination pair (e.g. an Indian passport applying for a Schengen visa is commonly 30-40 days) — found via search, not invented. Leave both at 0 for "available"/"not_needed"/"unknown".
5. "visa".confidence follows the same Fixed/Typical/Estimated scale used for prices below — "Fixed" only when search returned an authoritative government/embassy source.

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
- Use real, recognisable places near "{destination}".
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


_VISA_STATUSES = {"needed", "available", "not_needed", "unknown"}


def _parse_visa_info(raw, *, nationality: str, final_start_date: str) -> dict:
    """Structured visa guidance for the traveler's nationality vs. the destination.

    `raw` is whatever Gemini put under the "visa" key. The prompt asks for an
    object (status/processing_days_min/processing_days_max/note/confidence),
    but a plain string is still handled — either because the model ignored
    the schema, or because this is parsing a plan generated before this field
    became structured (`odyssey.dart`'s Flutter side needs the same fallback
    for the same reason: already-saved itineraries).

    `recommended_apply_by` is computed here, not asked of the model — Gemini
    is unreliable at exact date arithmetic, so only the day-count estimate is
    trusted to it, the same split `generate_odyssey`'s `verdict` already uses
    for budget feasibility.
    """
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
    if not nationality:
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
