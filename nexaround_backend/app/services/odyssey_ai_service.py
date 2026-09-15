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
import math
import re
from dataclasses import dataclass, field
import urllib.parse
import httpx
from app.services import cover_photo_service, geo_resolver, place_cache_service, telemetry, trip_cost_floor
from app.services.serpapi_service import (
    SerpApiService,
    _MIN_GOOGLE_HOTEL_CLASS,
    property_hotel_class as serpapi_property_hotel_class,
    attach_return_leg,
    rerank_tiers,
    format_flight_results_for_gemini,
    format_hotel_results_for_gemini,
    extract_hotel_strategies_from_serpapi,
    extract_flight_strategies_from_serpapi,
    extract_open_jaw_strategies_from_serpapi,
    rooms_for as serpapi_rooms_for,
    _card_title as serpapi_card_title,
    no_results as serpapi_no_results,
    _candidate_metrics as serpapi_candidate_metrics,
    _format_duration as serpapi_format_duration,
    convert_from_search_currency,
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
    one_way: bool = False,
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
        kind = "one way flights" if one_way else "flights"
        search_q = f"{kind} from {origin} to {dest}" if origin else f"{kind} to {dest}"
        if airlines and len(airlines) > 0:
            search_q += f" with {', '.join(airlines[:2])}"
        if start_date and end_date and not one_way:
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

# The cheap chain, for calls whose output is short, structured or purely
# cosmetic: an IATA code, a card's marketing copy, an estimate that is already
# labelled an estimate. Flash-lite is roughly a quarter of Flash's token price
# and answers these identically; Flash stays behind it so a bad minute on
# lite still produces an Odyssey. The itinerary itself, the route plan and the
# user-facing activity swap stay on the full chain.
_LITE_MODELS = ("gemini-2.5-flash-lite", "gemini-2.5-flash")

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
#
# This is a *capacity* filter — "a room that sleeps two" — not a statement that
# two travellers share one. `rooms_for` bills one room per traveller, so each
# traveller is charged a standard room. Pricing a single occupant at that rate
# overstates a little, and that is the direction a budget should err in: the
# party can share and come in under, never the reverse. Searching `adults=1`
# would quote singles more exactly but invalidates every cached hotel search
# and changes which properties Google returns at all.
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

# Class floors to try when a search comes back empty: the trip's own floor,
# then no filter at all. The intermediate 2-star rung used to sit between
# them, and on a small town where Google classifies nothing it bought a third
# search per city to return the same empty list — up to 20 searches on one
# five-city Odyssey. The unfiltered rung now does that rung's job, preferring
# classed properties among what it gets back (see _prefer_classed).
_HOTEL_CLASS_FALLBACKS = [0]

# How far a named place may sit from the city whose day it is. A generous day
# trip — the Church of the Intercession on the Nerl is 12 km outside Vladimir,
# Versailles 20 km outside Paris — while still far short of a namesake city on
# another continent.
_PLACE_ANCHOR_KM = 150

# How far a hotel may sit from the city it is supposed to be in. Generous
# enough for an airport hotel or a hill-station property spread along a valley,
# tight enough that a namesake city on another continent cannot survive it.
_HOTEL_MAX_KM = 60.0

# How many classed (2-star+) properties the unfiltered rung must find before
# it drops the unclassed ones. Below this the traveller is better served by
# four real guesthouses than by one hotel.
_MIN_CLASSED_RESULTS = 3


def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_SYSTEM = (
    "You are NexAround's expert local travel designer. "
    "You craft realistic, budget-aware, day-by-day trip blueprints. You always "
    "reply with a single JSON object that matches the requested schema exactly - "
    "no markdown, no commentary, no code fences. Your JSON is MINIFIED: one "
    "line, no indentation, no line breaks between keys. A machine parses it, "
    # Said here as well as in the prompt because a grounded call ignores
    # responseMimeType and largely ignores a formatting rule buried under
    # forty lines of trip constraints. Pretty-printing a 6,000-token
    # itinerary is billed like any other output.
    "and every space is billed. "
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
    inter_city_flights: list[dict] = None,
    hotel_strategies: dict = None,
    start_date: str = "",
    end_date: str = "",
    departure_city: str = "",
    budget_breakdown: dict = None,
    budget_advisory: str = "",
    budget_notes: dict = None,
    plan_advisory: str = "",
    verified_sources: list[dict] = None,
    verdict: dict = None,
    budget_scenarios: dict = None,
    budget_basis: dict = None,
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
        # The legs flown between cities, priced live and separately: the main
        # flight section covers only the journey to the country and home.
        "inter_city_flights": inter_city_flights or [],
        "hotel_strategies": hotel_strategies or {},
        "start_date": start_date,
        "end_date": end_date,
        "departure_city": departure_city,
        "budget_breakdown": budget_breakdown or {},
        "budget_advisory": budget_advisory,
        # Set only when the model wrote fewer days than the trip asked for. The
        # plan is kept and this says so; empty on every complete plan.
        "plan_advisory": plan_advisory,
        # What each budget line was priced from, in the traveller's words:
        # `summary` for the one line the card always shows, `stay` and
        # `transit` for the sheet behind its info tap. A sibling key rather
        # than entries inside `budget_breakdown`, whose values the app coerces
        # to double — a string there lands as 0.0 and adds a phantom category.
        "budget_notes": budget_notes or {},
        "verified_sources": verified_sources or [],
        "verdict": verdict or {},
        "budget_scenarios": budget_scenarios or {},
        "budget_basis": budget_basis or {},
        "practical_info": practical_info or {},
        "booking_plan": booking_plan or [],
        # The cities the trip sleeps in, with each leg's nights and dates.
        # Absent on every Odyssey generated before city legs existed, so every
        # reader must treat an empty list as "one leg covering the whole trip"
        # rather than as "no accommodation".
        "legs": legs or [],
        "generation_params": generation_params or {},
    }


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
    # ── Countries ────────────────────────────────────────────────────────────
    # A country is a destination travellers really do pick, and resolving it
    # here returns before both the Gemini lookup and the Places verification —
    # so the common cases cost no API call at all rather than the one Gemini
    # plus three Places calls they used to spend to produce nothing.
    #
    # Only names that cannot be mistaken for a city or a region are listed.
    # "Georgia" is deliberately absent: it is a US state as often as a country,
    # and this table is consulted on the raw typed string, before any geocoding
    # has had a chance to disambiguate it.
    "australia": "SYD,MEL,BNE", "new zealand": "AKL,CHC",
    "china": "PEK,PVG,CAN", "japan": "HND,NRT,KIX",
    "south korea": "ICN,GMP", "taiwan": "TPE",
    "thailand": "BKK,HKT", "vietnam": "SGN,HAN",
    "indonesia": "CGK,DPS", "malaysia": "KUL", "philippines": "MNL",
    "cambodia": "PNH,SAI", "india": "DEL,BOM,MAA", "nepal": "KTM",
    "pakistan": "KHI,LHE,ISB", "bangladesh": "DAC",
    "united arab emirates": "DXB,AUH", "uae": "DXB,AUH",
    "qatar": "DOH", "oman": "MCT", "saudi arabia": "RUH,JED",
    "jordan": "AMM", "israel": "TLV", "turkey": "IST,AYT",
    "türkiye": "IST,AYT",
    "united kingdom": "LHR,LGW,MAN", "france": "CDG,ORY,NCE",
    "germany": "FRA,MUC,BER", "italy": "FCO,MXP", "spain": "MAD,BCN",
    "portugal": "LIS,OPO", "netherlands": "AMS", "belgium": "BRU",
    "switzerland": "ZRH,GVA", "austria": "VIE", "czechia": "PRG",
    "czech republic": "PRG", "greece": "ATH", "poland": "WAW",
    "hungary": "BUD", "ireland": "DUB", "iceland": "KEF",
    "norway": "OSL", "sweden": "ARN", "denmark": "CPH", "finland": "HEL",
    "croatia": "ZAG", "romania": "OTP", "bulgaria": "SOF",
    "russia": "SVO,DME,LED",
    "united states": "JFK,LAX,ORD", "united states of america": "JFK,LAX,ORD",
    "usa": "JFK,LAX,ORD", "canada": "YYZ,YVR,YUL", "mexico": "MEX,CUN",
    "brazil": "GRU,GIG", "argentina": "EZE,AEP", "chile": "SCL",
    "peru": "LIM", "colombia": "BOG",
    "egypt": "CAI", "morocco": "CMN", "kenya": "NBO",
    "south africa": "JNB,CPT", "tanzania": "DAR,ZNZ",
    "ethiopia": "ADD", "nigeria": "LOS", "ghana": "ACC",
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

# How far an airport may sit from the destination before we call it the wrong
# airport. Sized for a city: generous enough for a place served by a hub in the
# next region, tight enough to catch the wrong country entirely. It is
# deliberately NOT applied to a whole-country destination — see
# _verify_airport_codes.
_AIRPORT_MAX_KM = 1000.0


async def _verify_airport_codes(
    codes: list[str],
    latitude: float | None,
    longitude: float | None,
    country_code: str,
    *,
    max_km: float | None = _AIRPORT_MAX_KM,
    budget=None,
) -> list[str]:
    """Drop airports that are not where the trip is.

    `max_km=None` keeps the country check and drops the distance one. That is
    the right shape for a whole-country destination, where the coordinates are
    a centroid and distance from it carries no information.

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
    is_country: bool = False,
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

    # A country needs no country suffix — "Australia, Australia" reads worse
    # to the model than the bare name and adds nothing.
    location = f"{raw}, {country}" if country and not is_country else raw
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
        text, _ = await _call_gemini(
            prompt, api_key, max_tokens=32, thinking_budget=0, models=_LITE_MODELS,
        )
        codes = re.findall(r"\b([A-Z]{3})\b", (text or "").upper())
        # Metro codes are silently rejected by Google Flights — drop any that
        # slipped through rather than shipping a search that returns nothing.
        codes = [c for c in dict.fromkeys(codes) if c not in _METRO_CODES][:3]
        # Only the model's answers are verified — the static table above is
        # curated, and the live SerpApi path never reaches here at all.
        if codes and country_code:
            # A country destination resolves to its centroid, which for a wide
            # country sits over 1000km from every airport that actually serves
            # it — the radius check rejected all three and the traveller got no
            # Flights section at all. The country check below is the correct
            # guard there and still catches the wrong-country answer this
            # verification exists to stop.
            codes = await _verify_airport_codes(
                codes, latitude, longitude, country_code,
                max_km=None if is_country else _AIRPORT_MAX_KM,
                budget=budget,
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


def _enforce_route_destination(
    data: dict, dest_code: str, origin_code: str = "", return_code: str = "",
) -> dict:
    """Rewrite each strategy's `route` to the airports we actually resolved.

    Only touches the AI-estimate path: on the live SerpApi path the route is
    built from the flight legs Google returned, so it is already correct. The
    model, by contrast, invents this string, and it is the string the booking
    link and the Flights card are both read from — so a wrong arrival airport
    there is visible and clickable. Codes we resolved beat codes it imagined.

    `return_code` is the airport the trip flies home from; when given, the
    return route is pinned the same way (home from there, back to the origin).
    """
    strategies = data.get("strategies")
    if not isinstance(strategies, list) or not dest_code:
        return data

    dest_first = dest_code.split(",")[0].strip().upper()
    origin_first = (origin_code or "").split(",")[0].strip().upper()
    return_first = (return_code or dest_code).split(",")[0].strip().upper()
    for strat in strategies:
        if not isinstance(strat, dict):
            continue
        route_str = str(strat.get("route") or "")
        parts = [p.strip() for p in route_str.replace("->", "→").split("→") if p.strip()]
        left = origin_first or (parts[0].upper() if parts else "")
        if not left:
            continue
        strat["route"] = f"{left} → {dest_first}"
        if strat.get("trip_type") != "one_way":
            strat["return_route"] = f"{return_first} → {left}"
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
        open_jaw = strat.get("trip_type") == "open_jaw"
        strat["booking_url"] = _build_deep_booking_url(
            provider="Google Flights",
            item_name=strat.get("title") or destination,
            destination=route_dest,
            start_date=flight_start_date,
            end_date=flight_end_date,
            travelers=travelers,
            is_flight=True,
            origin_city=route_origin,
            # An open-jaw trip is two tickets: the card's main link books the
            # outbound; the return leg gets its own below.
            one_way=open_jaw,
        )
        outbound = strat.get("outbound")
        if isinstance(outbound, dict):
            outbound["booking_url"] = strat["booking_url"]
        ret = strat.get("return")
        if isinstance(ret, dict):
            ret_str = str(strat.get("return_route") or "")
            r_parts = [p.strip() for p in ret_str.replace("->", "→").split("→") if p.strip()]
            ret_origin = r_parts[0].upper() if r_parts and _AIRPORT_CODE_RE.match(r_parts[0].upper()) else route_dest
            ret_dest = r_parts[-1].upper() if len(r_parts) > 1 and _AIRPORT_CODE_RE.match(r_parts[-1].upper()) else route_origin
            # On a round trip the one link above already covers both legs.
            ret["booking_url"] = _build_deep_booking_url(
                provider="Google Flights",
                item_name=strat.get("title") or destination,
                destination=ret_dest,
                start_date=flight_end_date,
                end_date="",
                travelers=travelers,
                is_flight=True,
                origin_city=ret_origin,
                one_way=True,
            ) if open_jaw else ""
    return data


def _same_country(departure_country: str, geo) -> bool:
    """True when home and destination sit in the same country.

    Only a domestic trip can be made by road or rail. "No flight, so take the
    bus" is sound advice for Kinniya to Colombo and nonsense for Colombo to
    Italy, so the ground-journey instructions below are gated on this.
    Unknown means False: silence beats sending someone overland to Rome.
    """
    home = str(departure_country or "").strip().lower()
    if not home or geo is None:
        return False
    there = {
        str(getattr(geo, "country", "") or "").strip().lower(),
        str(getattr(geo, "country_code", "") or "").strip().lower(),
    }
    there.discard("")
    return bool(there) and home in there


def _flights_unavailable(reason: str, message: str, origin_code: str = "") -> dict:
    """An empty flight section that explains itself.

    Three things end with no flight cards and they are not the same thing:
    Google has no route, the two cities share an airport, or we could not
    identify an airport at all. All three used to return a bare {}, which the
    app rendered as nothing at all — a traveller planning Kinniya to Colombo
    got an itinerary, a hotel list, and no word on how to make the journey.
    """
    return {
        "strategies": [],
        "more_options": [],
        "general_tips": [],
        "flights_available": False,
        "unavailable_reason": reason,
        "unavailable_message": message,
        "origin_airport": origin_code,
    }


def _no_flights_found(
    *, origin_code: str, dest_code: str, outbound_date: str,
    return_date: str = "", arrival_city: str = "",
) -> dict:
    """The flight section when Google says the journey cannot be booked.

    Not the same shape as a failure: `unavailable_reason` is "none_found", so
    the app can say so plainly instead of hiding the section, and nothing here
    carries a price. Previously both this and a timeout produced invented
    fares, and the traveller could not tell a route that does not exist from
    one we simply failed to look up.
    """
    where = arrival_city or dest_code
    dates = outbound_date + (f" - {return_date}" if return_date else "")
    return _flights_unavailable(
        "none_found",
        f"Google Flights has no route from {origin_code} to {where}"
        + (f" on {dates}" if dates else "")
        + ". Try different dates, or a nearby airport.",
        origin_code,
    )


def _structure_ai_flight_strategies(
    data: dict,
    *,
    currency: str,
    travelers: int,
    outbound_date: str,
    return_date: str,
    open_jaw: bool = False,
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
    if open_jaw and return_date:
        trip_type = "open_jaw"

    def _leg(route_str: str, date: str, airlines, stops, duration: str) -> dict | None:
        parts = [p.strip().upper() for p in str(route_str or "").replace("->", "→").split("→") if p.strip()]
        if len(parts) < 2:
            return None
        return {
            "origin": parts[0],
            "destination": parts[-1],
            "date": date or "",
            "departure_time": "",
            "arrival_time": "",
            "airlines": [str(a) for a in airlines] if isinstance(airlines, list) else [],
            "flight_numbers": [],
            "stops": _as_int(stops, 0),
            "duration_minutes": 0,
            "duration": str(duration or ""),
            "price_per_traveler": None,
            "segments": [],
            "booking_url": "",
        }

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
        s["outbound"] = _leg(
            s.get("route"), outbound_date, s.get("airlines"), s.get("stops"), s.get("total_duration"),
        )
        s["return"] = (
            _leg(
                s.get("return_route"), return_date, s.get("return_airlines") or s.get("airlines"),
                s.get("return_stops", s.get("stops")), s.get("return_duration"),
            )
            if trip_type != "one_way" else None
        )
        s.pop("return_airlines", None)
        s.pop("return_stops", None)
        s.pop("return_duration", None)
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

    # The same card copy contract as the live path. Without this the estimated
    # cards kept the model's own names — "Cheapest Budget Flights", "Best Value
    # Split Tickets", "Fastest Direct Option" — the exact verdicts the tier
    # titles were removed to stop, reappearing whenever SerpApi came back empty.
    for s in priced:
        out_leg, ret_leg = s.get("outbound") or {}, s.get("return") or {}
        out_min = _minutes_from_duration(out_leg.get("duration"))
        ret_min = _minutes_from_duration(ret_leg.get("duration")) if ret_leg else 0
        if out_leg:
            out_leg["duration_minutes"] = out_min
        if ret_leg:
            ret_leg["duration_minutes"] = ret_min
        s["outbound_duration_minutes"] = out_min
        s["return_duration_minutes"] = ret_min if ret_leg else None
        s["total_duration_minutes"] = out_min + ret_min
        s["title"] = serpapi_card_title(int(out_leg.get("stops") or 0), out_min + ret_min)
        s["estimated_savings"] = ""
        s["tip"] = ""

    cheapest = priced[0]["price_per_traveler"] if priced else 0
    dearest = priced[-1]["price_per_traveler"] if priced else 0
    if cheapest > 0 and (dearest - cheapest) / cheapest < 0.15:
        logger.warning(
            "AI flight tiers are within 15%% of each other (%s-%s %s) — tiers will "
            "look near-identical to the traveller.", cheapest, dearest, currency,
        )

    return data


# Which round-trip tiers get their return leg priced with a departure_token
# follow-up. One search per tier; the Recommended card is the one the
# itinerary is planned around, so it is the one that must show both legs.
_RETURN_LEG_TIERS = ("recommended", "minimum", "comfortable")
_RETURN_LEG_SEARCHES = 1


def _pick_return_tiers(strategies: list[dict], tokens: dict) -> list[dict]:
    """The strategies whose return leg is worth a follow-up search, in priority order."""
    by_tier = {s.get("tier"): s for s in strategies if isinstance(s, dict)}
    picked = []
    for tier in _RETURN_LEG_TIERS:
        strat = by_tier.get(tier)
        if strat is not None and tokens.get(tier):
            picked.append(strat)
        if len(picked) >= _RETURN_LEG_SEARCHES:
            break
    return picked


# A leg the route planner marks "arrive_by": "flight" is a real ticket the
# traveller has to buy, and until now it was the one flight nobody priced: the
# model invented a figure and attributed it to a site it had never asked. Two
# saved plans priced the same kind of one-hour Egyptian domestic hop at 10,000
# and 20,000 INR. One search each fixes that, and yields a booking link too.
def _apply_inter_city_fares(day_items: list[dict], hops: list[dict]) -> int:
    """Put the searched fare and booking link on the hop the model wrote.

    The prompt states the fare, but a prompt is a request; this is the
    guarantee. Gemini has never been allowed to produce a flight price on the
    main route and it is not allowed to here either — it writes the sentence,
    the number comes from Google. Returns how many hops were matched.
    """
    if not day_items or not hops:
        return 0
    by_day: dict[int, list] = {}
    for d in day_items:
        acts = d.get("activities")
        if isinstance(acts, list):
            by_day.setdefault(int(d.get("day") or 0), []).extend(acts)

    matched = 0
    for hop in hops:
        day_no = int(hop.get("day") or 0)
        to_city = str(hop.get("to_city") or "").strip().lower()
        to_code = str(hop.get("to_code") or "").strip().upper()
        target = None
        for a in by_day.get(day_no, []):
            if not isinstance(a, dict) or str(a.get("type") or "") != "transport":
                continue
            name = str(a.get("name") or "")
            blob = name.lower()
            if (to_city and to_city in blob) or (to_code and to_code in name):
                target = a
                break
        if target is None:
            logger.info(
                "No transport stop on day %d to carry the %s -> %s fare.",
                day_no, hop.get("from_city"), hop.get("to_city"),
            )
            continue
        currency = str(hop.get("currency") or "")
        target["cost"] = f"{currency} {hop.get('price_total', 0):,.0f}".strip()
        target["cost_per_person"] = hop.get("price_per_traveler")
        target["price_source"] = "Google Flights"
        target["price_confidence"] = "Fixed"
        target["price_basis"] = (
            f"{currency} {hop.get('price_per_traveler', 0):,.0f} each x "
            f"{hop.get('travelers', 1)} travellers, live Google Flights fare "
            f"for {hop.get('date')}."
        )
        if hop.get("booking_url"):
            target["booking_url"] = hop["booking_url"]
        matched += 1
    return matched


# What share of the food-and-activities money goes to food, when the plan
# itself has nothing to say. Only a starting point: `food_share_of_plan`
# replaces it with the plan's own split wherever the plan carries prices.
_DEFAULT_FOOD_SHARE = 0.60
# Neither line may collapse: a plan with no dining stop still needs a food
# budget, because people eat whether or not the itinerary lists a restaurant.
_MIN_LINE_SHARE = 0.25


def food_share_of_plan(plan: dict, travelers: int = 1) -> float:
    """How the day plan actually divides its money between food and activities.

    The waterfall used to split that money 60/40 no matter what the itinerary
    contained, and the card is what the traveller reads the plan against. Real
    plans divide it anywhere from 28/72 to 73/27, so the fixed ratio put one
    line over and the other far under on the same trip: a 14-day Peru plan for
    five listed 377,750 of activities against a 325,433 line while its food
    line sat at 0.67x, when the two together came to 0.87x of what they were
    allowed. Nothing was overspent - the money was in the wrong column.

    Returns a share in [0.25, 0.75]. Prices are never touched: this decides
    which line each one is counted under, not what anything costs.
    """
    day_plans = plan.get("day_plans") if isinstance(plan, dict) else None
    if not isinstance(day_plans, list):
        return _DEFAULT_FOOD_SHARE

    food = other = 0.0
    for day in day_plans:
        if not isinstance(day, dict):
            continue
        for a in day.get("activities") or []:
            if not isinstance(a, dict):
                continue
            kind = normalise_activity_type(a.get("type"))
            if kind in ("transport", "accommodation"):
                continue          # their own budget lines
            cost = _extract_lowest_price(a.get("cost_per_person"))
            if cost <= 0:
                continue
            if kind == "dining":
                food += cost
            else:
                other += cost

    total = food + other
    if total <= 0:
        return _DEFAULT_FOOD_SHARE
    return min(max(food / total, _MIN_LINE_SHARE), 1.0 - _MIN_LINE_SHARE)


def _drop_repeated_tips(day_items: list[dict]) -> int:
    """Keep the first use of a tip and clear every later repeat.

    The tip sits under the activity, so the same sentence four days running
    reads as though nobody wrote it. Mostly it is filler on the check-in rows -
    "Check in and settle into your accommodation." appeared five times in one
    14-day Turkey plan and four in a Spain one, on rows already called "Hotel
    Check-in" - and the model copies the phrasing onto every leg because the
    day-one row we insert ourselves uses it.

    Cleared, not rewritten: a tip that adds nothing is better absent than
    reworded into a second thing that adds nothing. Returns how many were
    dropped.
    """
    seen: set[str] = set()
    dropped = 0
    for day in sorted(
        (d for d in day_items if isinstance(d, dict)),
        key=lambda d: int(d.get("day") or 0),
    ):
        for a in day.get("activities") or []:
            if not isinstance(a, dict):
                continue
            tip = str(a.get("tip") or "").strip()
            if not tip:
                continue
            key = re.sub(r"[^a-z0-9]+", " ", tip.lower()).strip()
            if key in seen:
                a["tip"] = ""
                dropped += 1
            else:
                seen.add(key)
    return dropped


def _name_the_price_source(day_items: list[dict]) -> int:
    """Give a priced stop a source when it has a basis but no name for it.

    The app only shows `price_basis` when `price_source` is set, so a stop that
    carried a real explanation - "Estimated typical meal price in Kandy" - and
    no source name threw that explanation away and fell back to a bare
    "Estimated" chip. Six such stops across twelve generated plans.

    The source named here is what it honestly is: our own estimate, at the
    confidence the model already assigned. A stop with no basis either is left
    alone - there is nothing to reveal behind the chip.
    """
    named = 0
    for day in day_items:
        if not isinstance(day, dict):
            continue
        for a in day.get("activities") or []:
            if not isinstance(a, dict):
                continue
            if str(a.get("price_source") or "").strip():
                continue
            if _extract_lowest_price(a.get("cost_per_person")) <= 0:
                continue
            if not str(a.get("price_basis") or "").strip():
                continue
            confidence = str(a.get("price_confidence") or "").strip().lower()
            a["price_source"] = (
                "Typical local rate" if confidence == "typical" else "Estimated"
            )
            if not confidence:
                a["price_confidence"] = "Estimated"
            named += 1
    return named


def stretched_route_notice(
    route, days: int, entry_city: str = "", exit_city: str = "",
) -> str:
    """What to tell a traveller whose two chosen ends are far apart for the days.

    The planner keeps a trip inside one region so nobody spends half of it in
    transit, and an entry and exit the traveller picked themselves outrank that
    - they may have a flight already booked, or a wedding to get to. When the
    two pull the route further than the days comfortably allow, the route is
    still built, and this says so: the same choice the budget makes when it
    cannot cover the trip, rather than quietly dropping one end.

    Empty when nothing was asked for, when the ends are close enough, or when
    the planner did not manage to honour them - there is nothing to warn about
    a route that did not stretch.
    """
    legs = getattr(route, "legs", None) or []
    if not legs or not (entry_city and exit_city):
        return ""
    if entry_city.strip().lower() == exit_city.strip().lower():
        return ""

    first, last = legs[0], legs[-1]
    if not _leg_coords(first) or not _leg_coords(last):
        return ""
    (lat1, lng1), (lat2, lng2) = _leg_coords(first), _leg_coords(last)
    apart = geo_resolver.haversine_km(lat1, lng1, lat2, lng2)

    # Measured against the planner's own pace, not against the calendar: it is
    # told not to move city more often than every two days, and each hop runs
    # to about `_LEG_HOP_MAX_KM` by road. So a trip of `days` days covers
    # roughly `days // 2` hops before it is all transit.
    hops_available = max(int(days or 1) // 2, 1)
    reach = _LEG_HOP_MAX_KM * hops_available
    if apart <= reach:
        return ""

    hops_needed = max(int(round(apart / _LEG_HOP_MAX_KM)), 2)
    return (
        f"{first.get('city') or entry_city} and {last.get('city') or exit_city} are about "
        f"{apart:,.0f} km apart \u2014 further than {days} days comfortably covers, so "
        f"expect long journeys between stops, or an internal flight. Both were asked "
        f"for, so the route keeps them."
    )


def _apply_main_flight_details(
    day_items: list[dict], flight_strategies: dict | None, tier: str = "recommended",
) -> int:
    """Put the booking link on the two rows that carry the main flight.

    The inter-city hops have had this since they were priced live
    (`_apply_inter_city_fares`), and the flight into the country - the most
    expensive line on the whole plan - had nothing: day one read
    "Flight: CMB -> CAI" with a fare and a source and no way to book it, while
    a one-hour domestic hop three days later was one tap away. The link is on
    the Flights tab either way; what was missing is the link where the
    traveller is actually reading.

    The row home is a second problem of its own. The fare Google quotes is for
    the round trip and is already carried on day one, so this row must not
    repeat it or the day plan counts the flight twice - but it arrived with no
    cost and no source at all, which the app renders as free. It now says what
    it is: nothing more to pay, because the outbound fare covered it.

    Returns how many rows were matched.
    """
    if not day_items or not isinstance(flight_strategies, dict):
        return 0
    strategies = flight_strategies.get("strategies")
    if not isinstance(strategies, list) or not strategies:
        return 0

    chosen = next(
        (s for s in strategies if isinstance(s, dict) and s.get("tier") == tier), None,
    )
    if chosen is None:
        chosen = next((s for s in strategies if isinstance(s, dict)), None)
    if chosen is None:
        return 0

    out_url = str(chosen.get("booking_url") or "").strip()
    ret_url = str((chosen.get("return") or {}).get("booking_url") or "").strip() or out_url

    into = str((flight_strategies.get("arrival_airport") or {}).get("iata") or "").strip().upper()
    home = str(flight_strategies.get("origin_airport") or "").strip().upper()
    if not into and not home:
        return 0

    def _flight_row_to(acts, codes: list[str]) -> dict | None:
        """The transport row flying *to* one of these airports."""
        wanted = [c for c in codes if c]
        if not wanted:
            return None
        pattern = re.compile(
            r"(?:to|into|→|->)\s*(?:" + "|".join(re.escape(c) for c in wanted) + r")\b", re.I,
        )
        for a in acts:
            if not isinstance(a, dict) or str(a.get("type") or "") != "transport":
                continue
            if pattern.search(str(a.get("name") or "")):
                return a
        return None

    ordered = sorted(
        (d for d in day_items if isinstance(d, dict)),
        key=lambda d: int(d.get("day") or 0),
    )
    if not ordered:
        return 0

    matched = 0
    # The way in: the first day's flight to the arrival airport.
    arriving = _flight_row_to(ordered[0].get("activities") or [], into.split(","))
    if arriving is not None and out_url:
        arriving["booking_url"] = out_url
        matched += 1

    # The way home: the last day's flight back to where they started.
    leaving = _flight_row_to(ordered[-1].get("activities") or [], home.split(","))
    if leaving is not None:
        if ret_url:
            leaving["booking_url"] = ret_url
            matched += 1
        if not str(leaving.get("price_source") or "").strip():
            leaving["cost_per_person"] = 0
            leaving["cost"] = ""
            leaving["price_source"] = "Google Flights"
            leaving["price_confidence"] = "Fixed"
            leaving["price_basis"] = (
                "Included in the outbound fare shown on day 1 - nothing further to pay."
            )
    return matched


def _stop_label_text(stops: int) -> str:
    return "non-stop" if stops <= 0 else ("1 stop" if stops == 1 else f"{stops} stops")


def _date_for_day(start_date: str, day: int) -> str:
    """The calendar date of day N of the trip, or "" if the start is unusable."""
    try:
        from datetime import date as _date, timedelta as _timedelta
        return (
            _date.fromisoformat(str(start_date)[:10]) + _timedelta(days=max(day, 1) - 1)
        ).isoformat()
    except Exception:
        return ""


_MAX_HOP_SEARCHES = 3


async def generate_inter_city_flights(
    *,
    legs: list[dict],
    geo,
    currency: str,
    travelers: int,
    start_date: str,
    api_key: str,
    serpapi_key: str,
    geo_budget=None,
) -> list[dict]:
    """Live one-way fares for the legs the traveller flies between cities.

    One SerpApi search per flying leg, capped at `_MAX_HOP_SEARCHES` so a
    six-city itinerary cannot quietly spend the month's quota. Anything that
    cannot be resolved or priced is simply left out — the itinerary then
    describes the hop without a fare, which is the honest outcome and what it
    did before, minus the invented number.
    """
    if not legs or not serpapi_key or len(legs) < 2:
        return []

    country = str(getattr(geo, "country", "") or "")
    country_code = str(getattr(geo, "country_code", "") or "")

    async def _code(leg: dict) -> str:
        return await _resolve_airport_code(
            str(leg.get("city") or ""), country, api_key,
            latitude=leg.get("latitude"), longitude=leg.get("longitude"),
            country_code=country_code, budget=geo_budget,
        )

    serp = SerpApiService(serpapi_key)
    hops: list[dict] = []
    for i in range(1, len(legs)):
        if len(hops) >= _MAX_HOP_SEARCHES:
            logger.info("Inter-city flight search capped at %d.", _MAX_HOP_SEARCHES)
            break
        leg, prev = legs[i], legs[i - 1]
        if str(leg.get("arrive_by") or "").strip().lower() != "flight":
            continue

        from_code, to_code = await asyncio.gather(_code(prev), _code(leg))
        if not from_code or not to_code or set(from_code.split(",")) & set(to_code.split(",")):
            logger.info(
                "Skipping inter-city flight %s -> %s: codes %r / %r.",
                prev.get("city"), leg.get("city"), from_code, to_code,
            )
            continue

        date = _date_for_day(start_date, int(leg.get("start_day") or 1))
        try:
            data = await serp.search_flights(
                departure_city=from_code, destination=to_code,
                outbound_date=date, return_date="", one_way=True,
                adults=1, currency=currency, _operation="search_flights_hop",
            )
        except Exception as e:
            logger.warning("Inter-city flight search failed %s -> %s: %s", from_code, to_code, e)
            continue

        options = serpapi_candidate_metrics(data)
        if not options:
            logger.info("No inter-city flights %s -> %s on %s.", from_code, to_code, date)
            continue
        best = min(options, key=lambda c: (c["price"], c["duration"], c["stops"]))
        party = max(int(travelers or 1), 1)
        per = round(convert_from_search_currency(best["price"], currency), 2)
        hops.append({
            "day": int(leg.get("start_day") or 1),
            "from_city": prev.get("city") or from_code,
            "to_city": leg.get("city") or to_code,
            "from_code": best.get("origin_id") or from_code.split(",")[0],
            "to_code": best.get("dest_id") or to_code.split(",")[0],
            "date": date,
            "airlines": list(best.get("airlines") or []),
            "flight_numbers": list(best.get("flight_numbers") or []),
            "stops": int(best.get("stops") or 0),
            "duration": serpapi_format_duration(int(best.get("duration") or 0)),
            "duration_minutes": int(best.get("duration") or 0),
            "price_per_traveler": per,
            "price_total": round(per * party, 2),
            "currency": currency.upper(),
            "travelers": party,
            "is_live_price": True,
            "price_source": "google_flights_serpapi",
            "booking_url": _build_deep_booking_url(
                "Google Flights", "", leg.get("city") or to_code, date, "",
                travelers=party, is_flight=True,
                origin_city=prev.get("city") or from_code,
                airlines=list(best.get("airlines") or []), one_way=True,
            ),
        })
        logger.info(
            "Inter-city flight priced: %s -> %s on %s, %s %s pp.",
            from_code, to_code, date, currency.upper(), per,
        )
    return hops


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
    route_plan: "RoutePlan | None" = None,
) -> dict:
    """Generates tiered flight strategies from live SerpApi Google Flights data.

    Primary path mirrors generate_hotel_strategies' "Option A": SerpApi results
    are turned straight into Minimum / Recommended / Comfortable itineraries by
    extract_flight_strategies_from_serpapi, with no LLM in the pricing path.
    Gemini is then handed the already-priced itineraries and asked for prose
    only.

    Every price returned by either path is **per traveller, for the whole
    journey (both legs when a return date is known), in `currency`** — the
    convention documented in trip_cost_floor.py. `price_total` is always
    derived from it.

    Where the trip is entered and left comes from `route_plan` when the route
    planner decided it: fly into the gateway nearest the first leg, home from
    the one nearest the last. Different gateways make an open-jaw trip, priced
    as two one-way searches run together; the same gateway is a round trip,
    searched as before plus one follow-up for the return leg Google only
    reveals per outbound. Without a route plan the destination is resolved to
    an airport the way it always was.

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

    _dgeo = destination_geo
    arrival_code = (route_plan.arrival_code if route_plan is not None else "") or ""
    departure_code = (route_plan.departure_code if route_plan is not None else "") or ""
    if arrival_code:
        origin_code = await _resolve_airport_code(
            departure_city, dep_country, api_key,
            latitude=departure_latitude, longitude=departure_longitude,
        )
    else:
        # No planner gateway: the destination itself is resolved, on the same
        # footing as the origin. (Resolving it with country="" while the origin
        # got its country is the asymmetry that let an Andaman trip resolve to
        # Colombo.)
        origin_code, arrival_code = await asyncio.gather(
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
                is_country=(_dgeo.is_country if _dgeo is not None else False),
                budget=geo_budget,
            ),
        )
    if not departure_code:
        departure_code = arrival_code
    dest_code = arrival_code

    origin_set = set(origin_code.split(",")) if origin_code else set()
    if origin_set and (
        (arrival_code and origin_set & set(arrival_code.split(",")))
        or (departure_code and origin_set & set(departure_code.split(",")))
    ):
        logger.info(
            "No distinct flight route: '%s' and '%s' share airport(s) %s — "
            "skipping flight generation.",
            departure_city, destination, origin_code,
        )
        # Not a failure and not an empty route: the journey is simply a
        # domestic one. Kinniya and Colombo both resolve to CMB, and the
        # honest answer is the one locals already use — road or rail.
        #
        # Named by the first city the trip sleeps in rather than by
        # `destination`, which is whatever the traveller typed: a country name
        # there put a town and a country on the two sides of "served by the
        # same airport" — "Kinniya and Sri Lanka" — which is true and reads
        # like a mistake. Falls back to the gateway city, then to what they
        # typed, so a destination that never reached the planner still names
        # something.
        first_city = ""
        if route_plan is not None:
            first_city = str(
                (route_plan.legs[0].get("city") if route_plan.legs else "")
                or (route_plan.arrival or {}).get("city")
                or ""
            ).strip()
        going_to = first_city or destination
        return _flights_unavailable(
            "same_airport",
            f"{departure_city} and {going_to} are served by the same airport "
            f"({origin_code}), so there is no flight to book. Travel between them "
            f"by road or rail.",
            origin_code,
        )

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
        unknown = departure_city if not origin_code else destination
        return _flights_unavailable(
            "no_airport",
            f"No airport could be identified for {unknown}, so flights could not "
            f"be searched. Check the spelling, or plan the journey by road or rail.",
            origin_code,
        )

    is_open_jaw = set(arrival_code.split(",")) != set(departure_code.split(","))
    arrival_city = ((route_plan.arrival or {}).get("city") if route_plan is not None else "") or ""
    departure_gateway_city = ((route_plan.departure or {}).get("city") if route_plan is not None else "") or ""

    def _with_airports(data: dict, *, trip_type: str, home_code: str) -> dict:
        """Stamp the gateways the search actually used onto the result."""
        if not data:
            return data
        arrival = dict(route_plan.arrival) if route_plan is not None and route_plan.arrival else {}
        departure = dict(route_plan.departure) if route_plan is not None and route_plan.departure else {}
        if not arrival:
            arrival = {"iata": arrival_code.split(",")[0], "city": "", "name": ""}
        if not departure or home_code == arrival_code:
            departure = dict(arrival) if home_code == arrival_code else {
                "iata": home_code.split(",")[0], "city": "", "name": "",
            }
        data["arrival_airport"] = _public_airport(arrival)
        data["departure_airport"] = _public_airport(departure)
        data["origin_airport"] = origin_code
        data["trip_type"] = trip_type
        data.pop("_departure_tokens", None)
        return data

    async def _finish(direct: dict, *, trip_type: str, home_code: str) -> dict:
        # No prose pass. The card copy is templated from the fare's own numbers
        # in `serpapi_service._strategy_payload`; a model asked to "name the
        # option's character" wrote "Budget-Friendly Colombo to Moscow" over a
        # factual header and put "the best chance at securing your fare" in the
        # tip, which is the judgement the tier titles were removed to stop.
        direct = _apply_flight_booking_urls(
            direct,
            departure_city=departure_city,
            destination=destination,
            flight_start_date=outbound_date,
            flight_end_date=return_date,
            travelers=travelers,
        )
        return _with_airports(direct, trip_type=trip_type, home_code=home_code)

    # ── Primary path: SerpApi direct extraction ──────────────────────────────
    if serpapi_key and origin_code and dest_code:
        try:
            serp = SerpApiService(serpapi_key)
            serp_result: dict = {}

            if is_open_jaw and return_date:
                logger.info(
                    "Fetching live open-jaw flight data via SerpApi: %s → %s out, %s → %s home...",
                    origin_code, arrival_code, departure_code, origin_code,
                )
                out_result, ret_result = await asyncio.gather(
                    serp.search_flights(
                        departure_city=origin_code, destination=arrival_code,
                        outbound_date=outbound_date, one_way=True,
                        adults=1, currency=currency,
                    ),
                    serp.search_flights(
                        departure_city=departure_code, destination=origin_code,
                        outbound_date=return_date, one_way=True,
                        adults=1, currency=currency,
                    ),
                )
                serp_result = out_result
                direct = extract_open_jaw_strategies_from_serpapi(
                    out_result, ret_result,
                    departure_city=departure_city,
                    destination=destination,
                    currency=currency,
                    outbound_date=outbound_date,
                    return_date=return_date,
                    travelers=travelers,
                    arrival_city=arrival_city,
                    departure_gateway_city=departure_gateway_city,
                )
                if direct.get("strategies"):
                    logger.info(
                        "SerpAPI produced %d live open-jaw flight tiers for %s → %s / %s → %s",
                        len(direct["strategies"]), origin_code, arrival_code, departure_code, origin_code,
                    )
                    return await _finish(direct, trip_type="open_jaw", home_code=departure_code)

                # One direction came back empty. A round trip into the arrival
                # gateway is still a real, bookable answer; the itinerary is
                # told the trip must end back there.
                logger.warning(
                    "Open-jaw search had no usable pairing (%s → %s: %d options, %s → %s: %d); "
                    "falling back to a round trip via %s.",
                    origin_code, arrival_code,
                    len((out_result or {}).get("best_flights") or []) + len((out_result or {}).get("other_flights") or []),
                    departure_code, origin_code,
                    len((ret_result or {}).get("best_flights") or []) + len((ret_result or {}).get("other_flights") or []),
                    arrival_code,
                )
                is_open_jaw = False
                departure_code = arrival_code
                # The prompt's departure logistics read the route plan, so it
                # has to describe the flights actually found.
                if route_plan is not None:
                    route_plan.departure = dict(route_plan.arrival) if route_plan.arrival else None
                    route_plan.departure_code = arrival_code

            if not is_open_jaw:
                logger.info(
                    "Fetching live flight data via SerpApi (Google Flights) %s → %s...",
                    origin_code, dest_code,
                )
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
                    # The return leg Google only shows per outbound: one
                    # follow-up for the tier the plan is built around.
                    tokens = direct.get("_departure_tokens") or {}
                    for strat in _pick_return_tiers(direct["strategies"], tokens):
                        try:
                            ret_result = await serp.search_flights_return(
                                departure_city=origin_code,
                                destination=dest_code,
                                outbound_date=outbound_date,
                                return_date=return_date,
                                departure_token=tokens[strat["tier"]],
                                adults=1,
                                currency=currency,
                            )
                            if not attach_return_leg(
                                strat, ret_result, currency=currency, return_date=return_date,
                            ):
                                logger.info(
                                    "No return itineraries came back for the %s tier.", strat["tier"],
                                )
                        except Exception as e:
                            logger.warning("Return-leg lookup failed for %s tier: %s", strat.get("tier"), e)
                    # Pricing one card's return can move its fare past a card
                    # that was dearer when the names were handed out, so the
                    # names are handed out again against the fares now shown.
                    if rerank_tiers(direct["strategies"]):
                        logger.info(
                            "Flight tiers re-ranked after the return leg was priced: %s",
                            ", ".join(
                                f"{s.get('tier')} {s.get('price_per_traveler'):,.0f}"
                                for s in direct["strategies"]
                            ),
                        )
                    trip_type = "round_trip" if return_date else "one_way"
                    return await _finish(direct, trip_type=trip_type, home_code=dest_code)

                if serpapi_no_results(serp_result):
                    # Google answered, and the answer was that nothing flies
                    # this route on these dates. An estimate here would invent
                    # a fare for a journey that cannot be booked at any price,
                    # so the section comes back empty with a reason instead.
                    logger.info(
                        "Google has no flights %s → %s on %s; returning an empty "
                        "flight section rather than an estimate.",
                        origin_code, dest_code, outbound_date,
                    )
                    return _no_flights_found(
                        origin_code=origin_code, dest_code=dest_code,
                        outbound_date=outbound_date, return_date=return_date,
                        arrival_city=arrival_city or destination,
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
    if is_open_jaw and return_date:
        trip_basis = "open-jaw journey (outbound into one airport AND return home from another)"

    # Every worked example below used to be hard-coded "CMB → KUL". Five
    # Colombo literals in one prompt is a standing nudge toward Sri Lanka, and
    # an Andaman trip duly came back routed to CMB. Seed the examples with the
    # codes actually resolved for THIS trip; fall back to obviously-fake
    # placeholders rather than any real airport when nothing resolved.
    ex_o = (origin_code.split(",")[0].strip().upper() if origin_code else "AAA")
    ex_d = (dest_code.split(",")[0].strip().upper() if dest_code else "BBB")
    ex_r = (departure_code.split(",")[0].strip().upper() if departure_code else ex_d)
    ex_route = f"{ex_o} → {ex_d}"
    ex_return = f"{ex_r} → {ex_o}"
    return_rule = ""
    if return_date:
        return_rule = (
            f'- The return leg flies home from {ex_r}: "return_route" MUST be "{ex_return}". '
            f'Give its airlines, stop count and duration in "return_airlines", "return_stops" '
            f'and "return_duration".\n'
        )

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
{return_rule}- provider_name MUST be "Google Flights" for all strategies.
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
- "return_route": Short IATA airport code route for the way home — use exactly "{ex_return}" (omit for a one-way trip).
- "return_airlines", "return_stops", "return_duration": the return leg's carriers, stop count and duration (omit for a one-way trip).
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
      "return_route": "{ex_return}",
      "return_airlines": ["Airline A"],
      "return_stops": 0,
      "return_duration": "4h 40m",
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
        text, _ = await _call_gemini(
            prompt, api_key, max_tokens=4096, thinking_budget=0, models=_LITE_MODELS,
        )
        data = _parse_json(text)
        data = _structure_ai_flight_strategies(
            data,
            currency=currency,
            travelers=travelers,
            outbound_date=outbound_date,
            return_date=return_date,
            open_jaw=is_open_jaw,
        )
        # The model wrote these routes freehand. Where we resolved real codes,
        # they win — this is the last point before the route reaches the card
        # and the booking link.
        data = _enforce_route_destination(data, dest_code, origin_code, departure_code)
        for strat in data.get("strategies") or []:
            if not isinstance(strat, dict):
                continue
            for key, route_key in (("outbound", "route"), ("return", "return_route")):
                leg = strat.get(key)
                parts = [p.strip() for p in str(strat.get(route_key) or "").replace("->", "→").split("→") if p.strip()]
                if isinstance(leg, dict) and len(parts) >= 2:
                    leg["origin"], leg["destination"] = parts[0], parts[-1]
        data = _apply_flight_booking_urls(
            data,
            departure_city=departure_city,
            destination=destination,
            flight_start_date=outbound_date,
            flight_end_date=return_date,
            travelers=travelers,
        )
        trip_type = "open_jaw" if (is_open_jaw and return_date) else ("round_trip" if return_date else "one_way")
        return _with_airports(data, trip_type=trip_type, home_code=departure_code)
    except Exception as e:
        logger.error(f"Failed to generate flight strategies: {e}")
        return {}


def _prefer_classed(serp_result: dict, destination: str) -> dict:
    """On the unfiltered rung, keep the classed hotels when there are enough.

    This is what the old 2-star rung bought a whole extra search for: Google
    ranks unclassed guesthouses alongside hotels once `hotel_class` is gone,
    and a trip that could afford 3-star should not be shown four hostels. But
    in a town where almost nothing is classified, dropping the unclassed ones
    would leave one lonely card — so the filter only applies when at least
    `_MIN_CLASSED_RESULTS` classed properties came back.
    """
    properties = serp_result.get("properties") or []
    classed = [
        p for p in properties
        if isinstance(p, dict) and serpapi_property_hotel_class(p) >= _MIN_GOOGLE_HOTEL_CLASS
    ]
    if len(classed) < _MIN_CLASSED_RESULTS:
        return serp_result
    if len(classed) < len(properties):
        logger.info(
            "Unfiltered search for %s: keeping %d classed of %d properties",
            destination, len(classed), len(properties),
        )
    return {**serp_result, "properties": classed}


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
    country: str = "",
    country_code: str = "",
    latitude: float | None = None,
    longitude: float | None = None,
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
            attempts = [c for c in _HOTEL_CLASS_FALLBACKS if c < min_hotel_class]
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
                    # Which Saint Petersburg. See search_hotels' docstring.
                    country=country,
                    country_code=country_code,
                    latitude=latitude,
                    longitude=longitude,
                    max_km=_HOTEL_MAX_KM,
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
                        "; dropping the class filter" if attempt + 1 < len(attempts) else "",
                    )
                    continue

                if not class_floor:
                    serp_result = _prefer_classed(serp_result, destination)
                    properties = serp_result.get("properties") or []

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
        text, _ = await _call_gemini(
            prompt, api_key, max_tokens=4096, thinking_budget=0, models=_LITE_MODELS,
        )
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


# Values a model writes when it means "nothing here". The app renders
# `price_source` and `price_basis` whenever they are non-empty, so "N/A"
# reaches the traveller as the printed source of the price.
_NOT_A_SOURCE = {
    "n/a", "n/a.", "na", "none", "none.", "no source", "unknown", "unknown.",
    "-", "--", "not applicable", "not available", "tbd", "tba", "free", "n.a.",
}


def _sourced(value) -> str:
    """The text, or "" when it is one of the ways a model writes "nothing"."""
    text = str(value or "").strip()
    return "" if text.lower().strip(" .") in {s.strip(" .") for s in _NOT_A_SOURCE} else text


def _is_free(cost) -> bool:
    """True when a cost line names no money — "Free", "Free (chairs extra)", ""."""
    text = str(cost or "").strip().lower()
    if not text:
        return True
    if re.search(r"\d", text.split("(")[0]):
        return False
    return text.startswith("free") or text in _NOT_A_SOURCE


def _rooms_for(travelers: int) -> int:
    """Rooms a party needs, at one room per traveller.

    Accommodation used to ignore party size entirely — it reached SerpApi as
    `adults=` and never became rooms — so three travellers were budgeted one
    room's worth of nights. It then went to two travellers per room, which
    still halved the stay line of every party trip; see `serpapi.rooms_for`.

    Delegates to `serpapi_service.rooms_for`, which the Stays tab's own stay
    totals are built from: a second copy of this rule here is how the budget's
    stay line and the Stays tab came to quote different totals for one stay.
    """
    return serpapi_rooms_for(travelers)


def _tier_index(count: int, tier: str) -> int:
    """Which rank a tier reads, once the options are ordered cheapest first.

    Split out so a list of rates and a list of (rate, property) pairs can be
    ranked by the same rule. `stay_cost_lines` has to name the property whose
    rate the budget took, and re-deriving "which one is the middle" beside
    `_rate_for_tier` is exactly how the sheet and the bar would drift apart.
    """
    if count <= 0:
        return 0
    if tier == "minimum":
        return 0
    if tier == "comfortable":
        return count - 1
    return count // 2


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
    return sorted(rates)[_tier_index(len(rates), tier)]


# The ways a model says a figure is for one traveller, and for the whole party.
_PER_PERSON_RE = re.compile(r"(/\s*(person|pax|adult|head)|\bper\s+(person|pax|adult|head)\b|\bpp\b|\beach\b)", re.I)
_PARTY_OF_RE = re.compile(
    r"\bfor\s+(two|three|four|five|six|2|3|4|5|6)\s+(adults?|people|persons?|travell?ers?)\b", re.I)
_WORD_COUNT = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6}


def _minutes_from_duration(text) -> int:
    """Minutes out of "14h 30m", "14h", "870m" or "" — 0 when unreadable.

    The estimated-fare path carried duration only as the model's own string and
    left `duration_minutes` at 0, so those cards could not state a journey time
    and nothing could rank them by it.
    """
    s = str(text or "").strip()
    if not s:
        return 0
    hours = re.search(r"(\d+)\s*h", s, re.I)
    mins = re.search(r"(\d+)\s*m(?!s)", s, re.I)
    if hours or mins:
        return (int(hours.group(1)) * 60 if hours else 0) + (int(mins.group(1)) if mins else 0)
    bare = re.search(r"\d+", s)
    return int(bare.group()) if bare else 0


def _party_cost(activity: dict, currency: str, travelers: int) -> tuple[str, float | None]:
    """(what the card shows, one adult's share) for a single stop.

    Everything the traveller reads is what the party pays, because the budget
    they set is a party budget and the budget lines beside it are party totals.

    Across nine live plans, 69% of priced stops said nothing about which unit
    they used, 23% buried it in the small print and 8% put it on the card. A
    couple reading "INR 1,800" for the Bahia Palace was really looking at
    INR 3,600; a family of four at four times the number on screen. The model
    is now asked for one adult's price as a bare number and the arithmetic and
    the wording happen here, so the unit cannot drift again.

    Returns ("", None) when there is nothing to price.
    """
    party = max(int(travelers or 1), 1)
    code = str(currency or "").upper()

    raw = activity.get("cost_per_person")
    per: float | None = None
    if raw is not None and str(raw).strip() != "":
        if _is_free(raw):
            return "Free", 0.0
        value = _extract_lowest_price(str(raw))
        if value > 0:
            per = value
        elif re.search(r"\d", str(raw)):
            # An explicit zero is free, not a missing answer.
            return "Free", 0.0

    if per is None:
        # Fallback for a model that answered with the old free-text field.
        text = str(activity.get("cost") or "")
        if not text.strip():
            return "", None
        if _is_free(text):
            return "Free", 0.0
        value = _extract_lowest_price(text)
        if value <= 0:
            return text, None
        basis = str(activity.get("price_basis") or "")
        stated_party = _PARTY_OF_RE.search(text) or _PARTY_OF_RE.search(basis)
        if _PER_PERSON_RE.search(text) or _PER_PERSON_RE.search(basis):
            per = value
        elif stated_party:
            token = stated_party.group(1).lower()
            named = _WORD_COUNT.get(token, int(token) if token.isdigit() else party)
            per = value / max(named, 1)
        else:
            # Unmarked and unexplained: take it at face value as the party
            # total. Never inflate a figure we are only guessing about.
            return f"{code} {value:,.0f}" if code else text, (value / party if party else value)

    total = per * party
    return (f"{code} {total:,.0f}" if code else f"{total:,.0f}"), per


def _align_legs_to_itinerary(
    city_legs: list[dict], day_plans, days: int, hops: list[dict] | None = None,
) -> list[str]:
    """Move each leg boundary to the day the itinerary actually travels.

    The legs are planned before the itinerary is written and the hotel nights
    are booked from them; the day plans are what the traveller follows. When
    the two disagree, the traveller sleeps in the next city with a room booked
    in the last one.

    Seen live on a Rome/Florence/Venice/Milan trip: the Rome->Florence train
    ran on day 5 while the Florence leg began on day 6, and the same one-day
    slip repeated on all three changes — over-booking Rome by a night and
    under-booking Milan by one. Seven of the eight plans generated that day
    were correct, so this is the model missing the instruction occasionally
    rather than a rule nobody wrote down.

    The itinerary wins, because it is the thing the traveller reads and the
    thing every activity is already written against. Mutates `city_legs` and
    returns a note per leg moved.
    """
    if not city_legs or len(city_legs) < 2 or not isinstance(day_plans, list):
        return []

    # A hop we priced ourselves tells us the destination's airport code, and
    # the model writes the row with whichever of the two it copied. The prompt
    # asks for "Flight: <from city> -> <to city>" and the confirmed-hop line
    # above it reads "Cairo (CAI) -> Luxor (LXR)", so it often writes
    # "Flight: CAI -> LXR" instead - which this could not see, so a 14-day
    # Egypt plan flew to Cairo on day 13 with the Aswan leg still holding five
    # nights and the Cairo leg holding none.
    codes_for: dict[str, set[str]] = {}
    for h in hops or []:
        if not isinstance(h, dict):
            continue
        city = str(h.get("to_city") or "").strip().lower()
        code = str(h.get("to_code") or "").strip()
        if city and code:
            codes_for.setdefault(city, set()).add(code)

    by_day: dict[int, list] = {}
    for d in day_plans:
        if isinstance(d, dict) and isinstance(d.get("day"), int):
            acts = d.get("activities")
            by_day[d["day"]] = acts if isinstance(acts, list) else []

    def _travel_day(city: str, after: int = 0) -> int | None:
        """First day after `after` that a transport stop travels to `city`.

        The city, or the airport code of a hop that lands there.

        `after` is what makes a repeated city work. A trip that opens and
        closes in the same place - Cairo, Delhi, Bangkok - has a day-1 transfer
        into it, and searching from the start found that one for the closing
        leg too: the Egypt plan's return to Cairo on d13 was read as d1 and
        refused for leaving Aswan no nights. Each leg only looks past the day
        its predecessor began.
        """
        if not city:
            return None
        targets = [re.escape(city)]
        targets += [re.escape(c) for c in sorted(codes_for.get(city.strip().lower(), ()))]
        pattern = re.compile(
            rf"(?:to|into|→|->)\s*(?:{'|'.join(targets)})\b", re.I,
        )
        for day in sorted(d for d in by_day if d > after):
            for a in by_day[day]:
                if not isinstance(a, dict):
                    continue
                if str(a.get("type") or "").strip().lower() != "transport":
                    continue
                if pattern.search(str(a.get("name") or "")):
                    return day
        return None

    notes: list[str] = []
    for i in range(1, len(city_legs)):
        leg, prev = city_legs[i], city_legs[i - 1]
        found = _travel_day(
            str(leg.get("city") or ""), after=int(prev.get("start_day") or 0),
        )
        if found is None:
            continue
        start = int(leg.get("start_day") or 0)
        if found == start:
            continue
        # A boundary may move, but never so far that the previous city loses
        # every night or the leg runs past its own end.
        if not (int(prev.get("start_day") or 1) < found <= int(leg.get("end_day") or days)):
            notes.append(
                f"{leg.get('city')}: itinerary travels on d{found}, left at d{start} — "
                f"moving it would leave {prev.get('city')} with no nights"
            )
            continue
        leg["start_day"] = found
        prev["end_day"] = found - 1
        notes.append(f"{leg.get('city')} d{start} -> d{found}, {prev.get('city')} now ends d{found - 1}")

    # Nights follow the boundaries: you sleep in a city on every day of its
    # leg, except the last leg, whose final day is the flight home.
    last = len(city_legs) - 1
    for i, leg in enumerate(city_legs):
        s, e = int(leg.get("start_day") or 1), int(leg.get("end_day") or 1)
        leg["nights"] = max(0, (e - s) if i == last else (e - s + 1))
    return notes


def _reprice_stays(hotel_strategies: dict | None, city_legs: list[dict], currency: str) -> None:
    """Re-total every hotel after a leg boundary moved.

    Same arithmetic both hotel paths already use — nightly x nights x rooms —
    so the Stays tab and the budget's stay line stay the single figure they
    are tested to be.
    """
    strategies_ = (hotel_strategies or {}).get("strategies")
    if not isinstance(strategies_, list) or not city_legs:
        return
    by_index = {i: leg for i, leg in enumerate(city_legs)}
    by_city = {str(leg.get("city") or "").lower(): leg for leg in city_legs}
    for s in strategies_:
        if not isinstance(s, dict):
            continue
        leg = by_index.get(s.get("leg_index")) or by_city.get(str(s.get("city") or "").lower())
        if not leg:
            continue
        nights = int(leg.get("nights") or 0)
        s["nights"] = nights
        rooms = max(int(s.get("rooms") or 1), 1)
        nightly = _extract_lowest_price(s.get("price_per_night") or "")
        if nightly > 0 and nights > 0:
            s["total_estimated_cost"] = f"{currency.upper()} {nightly * nights * rooms:,.0f}"


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
    figure. Whichever tier, the rate is drawn from properties at
    `_BASE_HOTEL_CLASS` or above wherever the leg has any — see the star floor
    below — so "cheapest" never means a 2-star room the search never asked for.

    The figure this replaced was a single `min()` over one trip-wide hotel
    search, so a four-city trip was budgeted one city's stay, party size never
    became rooms, and — when no dates reached SerpApi — a single night stood in
    for the whole trip.

    Module-level rather than a closure inside `generate_odyssey` so it can be
    tested against the Stays tab's totals directly, which is the only way to
    catch the two drifting apart again.
    """
    return round(
        sum(
            line["amount"]
            for line in stay_cost_lines(
                hotel_strategies, city_legs, travelers, tier,
            )
        ),
        2,
    )


def stay_cost_lines(
    hotel_strategies: dict | None,
    city_legs: list[dict],
    travelers: int,
    tier: str = "minimum",
) -> list[dict]:
    """The same arithmetic, one line per city the trip sleeps in.

    `required_stay_cost` is the sum of these, so the Stay sheet in Budget
    Allocation can print its own working and cannot disagree with the bar it
    sits under. That is why the derivation lives here rather than being redone
    in Dart from `hotel_strategies`: the star-floor fallback and the pooling
    below are not obvious, and a second implementation of them would drift.

    Each line carries how its rate was found, in `basis`:
      "classed"   — a property at `_BASE_HOTEL_CLASS` or above, the normal case
      "unclassed" — the leg had nothing at that class, so every rate was open
      "pooled"    — the leg's own search came back empty and the trip's other
                    rates stood in for it
    """
    strategies_ = (hotel_strategies or {}).get("strategies")
    if not isinstance(strategies_, list) or not city_legs:
        return []
    rooms_ = _rooms_for(travelers)
    by_leg: dict[int, list[tuple[float, dict]]] = {}
    # The same rates again, keeping only properties at the star class the
    # search asked for. The ladder falls back to an unfiltered rung when a
    # class-filtered search comes back empty (`_HOTEL_CLASS_FALLBACKS`), so on
    # a town where Google classifies little, 2-star properties reach the list
    # — and a 2-star rate was then setting the budget's floor. Seen on a
    # 14-day Colombo plan, whose Minimum tier sat at 46,396 against the 50,926
    # its 3-star rooms actually cost.
    classed_by_leg: dict[int, list[tuple[float, dict]]] = {}
    for s in strategies_:
        if not isinstance(s, dict):
            continue
        rate = _extract_lowest_price(s.get("price_per_night"))
        if rate > 0:
            leg_key = int(s.get("leg_index") or 0)
            by_leg.setdefault(leg_key, []).append((rate, s))
            if int(s.get("hotel_class") or 0) >= _BASE_HOTEL_CLASS:
                classed_by_leg.setdefault(leg_key, []).append((rate, s))

    lines: list[dict] = []
    for leg_i, leg_ in enumerate(city_legs):
        nights_ = int(leg_.get("nights") or 0)
        if nights_ <= 0:
            continue
        # Below the star floor only when there is nothing at or above it. A leg
        # where the whole town is unclassed still has to be priced, and the
        # Gemini estimate path writes no `hotel_class` at all, so this falls
        # back to every rate rather than to nothing.
        basis_ = "classed"
        entries_ = classed_by_leg.get(leg_i)
        if not entries_:
            entries_ = by_leg.get(leg_i)
            basis_ = "unclassed"
        if not entries_:
            # A leg whose search came back empty still has to be slept in.
            # Carry the trip's known rates rather than pricing those nights at
            # zero, which is what made a budget look sufficient. Pooled across
            # legs, then tiered the same way, so an empty leg tracks the tier
            # instead of always falling back to the cheapest room.
            pool_ = classed_by_leg or by_leg
            if not pool_:
                continue
            entries_ = [e for ee in pool_.values() for e in ee]
            basis_ = "pooled"
        rate_, hotel_ = sorted(entries_, key=lambda e: e[0])[
            _tier_index(len(entries_), tier)
        ]
        # A pooled rate was borrowed from another city, so the property it
        # belongs to is not in this one. Carrying its name here printed
        # "Hakone · 3 nights — Kyoto Ryokan" on the Stay sheet: the rate is
        # a stand-in, and only the rate.
        pooled_ = basis_ == "pooled"
        lines.append({
            "leg_index": leg_i,
            "city": str(leg_.get("city") or hotel_.get("city") or ""),
            "nights": nights_,
            "rooms": rooms_,
            "nightly": round(rate_, 2),
            "hotel": "" if pooled_ else str(hotel_.get("name") or ""),
            "hotel_class": 0 if pooled_ else int(hotel_.get("hotel_class") or 0),
            # How many rooms this city actually offered. Two of them leave the
            # mid-priced and dearest tiers pricing the same room — see the
            # caveat `budget_basis` draws from this.
            "options": len(entries_),
            "basis": basis_,
            "amount": round(rate_ * nights_ * rooms_, 2),
        })
    return lines


def stay_priced_at_star_floor(
    hotel_strategies: dict | None, city_legs: list[dict],
) -> bool:
    """Did every slept-in leg price itself from a classed room?

    Only so the budget note can say "3-star" truthfully. `required_stay_cost`
    drops below the floor on a leg that has nothing at or above it, and the
    Gemini estimate path writes no `hotel_class` at all, so a plan may well be
    priced off unclassed rooms — claiming a star floor there would be the kind
    of confident, unearned sentence this whole section exists to stop printing.
    """
    strategies_ = (hotel_strategies or {}).get("strategies")
    if not isinstance(strategies_, list) or not city_legs:
        return False
    classed: set[int] = set()
    for s in strategies_:
        if not isinstance(s, dict):
            continue
        if (
            _extract_lowest_price(s.get("price_per_night")) > 0
            and int(s.get("hotel_class") or 0) >= _BASE_HOTEL_CLASS
        ):
            classed.add(int(s.get("leg_index") or 0))
    if not classed:
        return False
    return all(
        i in classed
        for i, leg_ in enumerate(city_legs)
        if int(leg_.get("nights") or 0) > 0
    )


def _flight_fare(s: dict) -> float:
    """What one traveller pays on this card, live price or estimate."""
    price = s.get("price_per_traveler")
    if isinstance(price, (int, float)) and price > 0:
        return float(price)
    return _extract_lowest_price(s.get("estimated_price_range"))


def _chosen_live_flight(
    flight_strategies: dict | None, tier: str = "recommended",
) -> dict | None:
    """The live-priced card the budget's transit line is describing.

    The named tier when the Flights tab has one, otherwise the cheapest live
    fare - the same fallback `transit_cost_lines` applies to the money, kept
    in one place so the sentence and the number cannot describe different
    cards.
    """
    if not (flight_strategies and isinstance(flight_strategies.get("strategies"), list)):
        return None
    live = [
        s for s in flight_strategies["strategies"]
        if isinstance(s, dict) and _flight_fare(s) > 0 and s.get("is_live_price")
    ]
    if not live:
        return None
    return next(
        (s for s in live if s.get("tier") == tier),
        min(live, key=_flight_fare),
    )


def effective_flight_tier(
    flight_strategies: dict | None, tier: str = "recommended",
) -> str:
    """The tier whose fare the budget actually took.

    The Pareto frontier can collapse to two cards: a live Colombo -> Hanoi
    plan shipped with Minimum and Comfortable and no Recommended at all. The
    transit figure was right - the fallback took the cheapest live fare - but
    the note beside it still read "best value", naming a card that was not on
    the Flights tab for the traveller to find.

    Returns the requested tier untouched when nothing is priced, so wording
    never turns on an empty search.
    """
    chosen = _chosen_live_flight(flight_strategies, tier)
    if chosen is None:
        return tier
    got = str(chosen.get("tier") or "").strip()
    return got if got in _TIER_WORDS else tier


def budget_flight_basis(
    flight_strategies: dict | None, tier: str = "recommended",
) -> str:
    """What kind of fare the budget priced itself from.

    One of "direct", "connecting", "estimated" or "none" — the four things the
    budget note can honestly say about the transit line. It exists because the
    client asked for the words "Based on Best Value Direct Flight", which hold
    on 2 of the 30 live routes held in cache; on the rest the note has to say
    something else, and on a route with no fare at all it must say nothing.

    Which fare: the named tier if the Flights tab has one, else the cheapest —
    mirroring `_tier_flight_cost`'s own fallback, so the sentence always
    describes the number beside it rather than a card the budget ignored.

    "estimated" is not a detail. `_structure_ai_flight_strategies` defaults a
    missing `stops` to 0, so a model that simply said nothing about connections
    would otherwise have the note announce a direct flight nobody checked for.

    Module-level for the same reason as `required_stay_cost`: a rule that
    decides what a printed sentence claims has to be testable against the
    payloads both flight paths actually produce, not only through a whole
    generation.
    """
    if not (flight_strategies and isinstance(flight_strategies.get("strategies"), list)):
        return "none"
    priced = [
        s for s in flight_strategies["strategies"]
        if isinstance(s, dict) and _flight_fare(s) > 0
    ]
    if not priced:
        return "none"
    chosen = _chosen_live_flight(flight_strategies, tier)
    if chosen is None:
        return "estimated"
    return "direct" if int(chosen.get("stops") or 0) == 0 else "connecting"


def transit_cost_lines(
    flight_strategies: dict | None, travelers: int, tier: str = "recommended",
) -> list[dict]:
    """The fare the transit line is built from, as one priced line.

    `tier_flight_cost` is the total of these, the same relationship
    `required_stay_cost` has with `stay_cost_lines`, so the Flights sheet
    always describes the card the budget actually took — including the
    fallback to the cheapest fare when the tier has no card of its own, which
    is the case a second implementation would quietly get wrong.

    Empty when nothing is priced: a domestic trip, a route Google has no fares
    for, or an Odyssey generated before fares were structured at all.
    """
    if not (flight_strategies and isinstance(flight_strategies.get("strategies"), list)):
        return []
    party = max(travelers, 1)
    priced: list[tuple[float, dict]] = []
    chosen: tuple[float, dict] | None = None
    for s in flight_strategies["strategies"]:
        if not isinstance(s, dict):
            continue
        price = s.get("price_per_traveler")
        if not isinstance(price, (int, float)) or price <= 0:
            # Legacy odysseys / AI fallback without structured pricing.
            price = _extract_lowest_price(s.get("estimated_price_range"))
        if price and price > 0:
            priced.append((float(price), s))
            if s.get("tier") == tier:
                chosen = (float(price), s)
    if not priced:
        return []
    tier_exact = chosen is not None
    if chosen is None:
        chosen = min(priced, key=lambda e: e[0])
    fare, strat = chosen
    stops = int(strat.get("stops") or 0)
    airlines = strat.get("airlines")
    carrier = (
        ", ".join(str(a) for a in airlines)
        if isinstance(airlines, list) and airlines else ""
    )
    return [{
        "label": str(strat.get("route") or strat.get("title") or "Air fare"),
        "airline": carrier,
        "stops": stops,
        "stops_label": (
            "non-stop" if stops == 0
            else ("1 stop" if stops == 1 else f"{stops} stops")
        ),
        "live": bool(strat.get("is_live_price")),
        "tier": str(strat.get("tier") or ""),
        "tier_exact": tier_exact,
        "per_traveler": round(fare, 2),
        "travelers": party,
        "amount": fare * party,
    }]


def tier_flight_cost(
    flight_strategies: dict | None, travelers: int, tier: str = "recommended",
) -> float:
    """Party-total flight cost for one tier, falling back to the cheapest."""
    lines = transit_cost_lines(flight_strategies, travelers, tier)
    return lines[0]["amount"] if lines else 0.0


def food_and_activities_room(
    *,
    budget: float,
    flight_strategies: dict | None,
    hotel_strategies: dict | None,
    city_legs: list[dict],
    travelers: int,
    on_ground: float = 0.0,
) -> float:
    """Roughly what is left for food and activities once flights and rooms are paid.

    The itinerary prompt used to hand the model the whole trip budget and a set
    of percentages - "Flights ~40-50%, Stay ~30-35%, Food ~10-15%, Activities
    ~5-10%" - and ask it to keep its activity costs inside its own guess. The
    backend then threw that guess away and rebuilt the split from the real
    fares and room rates. On a Colombo->Turkey plan the real flights took 48%
    of the budget, the waterfall left 74,362 for activities, and the day plan
    the model had already written listed 103,800 of them: a trip the traveller
    cannot afford by their own budget, shown as if they could.

    Both inputs are already in hand when the prompt is built, so the model can
    be told the figure instead of a percentage.

    Measured against the same floored total the waterfall will use, not
    against the budget as entered. A trip whose flights and rooms already break
    that budget leaves nothing by subtraction - a 14-day Peru plan for five
    came to LKR 6.8m against a 6m budget - and clamping that at zero sent the
    prompt back to a percentage of the budget while the waterfall went on
    allocating a share of the lifted total. The two disagreed by more than
    double, and the day plan came in at 2.3x the food line it was shown under.

    Deliberately approximate. Legs shift slightly after the plan comes back
    (`_align_legs_to_itinerary`), so this is guidance; the authoritative split
    is still the waterfall's, computed afterwards.
    """
    party = max(int(travelers or 1), 1)
    flight = 0.0
    strategies = (flight_strategies or {}).get("strategies")
    if isinstance(strategies, list):
        fares = []
        for s in strategies:
            if not isinstance(s, dict):
                continue
            price = s.get("price_per_traveler")
            if not (isinstance(price, (int, float)) and price > 0):
                price = _extract_lowest_price(s.get("estimated_price_range"))
            if price and price > 0:
                fares.append(float(price))
        if fares:
            # The middle card is the one the budget prices itself from.
            chosen = next(
                (float(s["price_per_traveler"]) for s in strategies
                 if isinstance(s, dict) and s.get("tier") == "recommended"
                 and isinstance(s.get("price_per_traveler"), (int, float))
                 and s["price_per_traveler"] > 0),
                min(fares),
            )
            flight = chosen * party

    stay = required_stay_cost(hotel_strategies, city_legs, travelers, "recommended")

    # `_scenario_total`'s floor, mirrored: the headline never sits below what
    # the tier costs, so that is the figure the split is carved out of.
    tier_cost = flight + stay + max(float(on_ground or 0), 0.0)
    total = float(budget or 0)
    if tier_cost > 0:
        total = max(total, round(tier_cost * 1.05, 2))
    return max(round(total - flight - stay, 2), 0.0)


# How each tier ranks the rooms and fares it prices itself from, in words.
#
# The client supplied "Based on best value price" for the stay line while
# asking for the *cheapest* hotel, and his 15 Sep follow-up ("lowest cost but
# hi star rated hotel", "lowest cost flight") settled that the words should
# follow the arithmetic. "Best value" survives on the Recommended tier, which
# is the one it was always true of.
_TIER_WORDS = {
    "minimum": ("Cheapest", "the lowest-priced", "lowest-priced"),
    "recommended": ("Mid-priced", "the mid-priced", "best value"),
    "comfortable": ("Dearest", "the highest-priced", "highest-priced"),
}


def _budget_notes(
    *,
    rooms: int,
    at_star_floor: bool,
    flight_basis: str,
    no_airfare: bool,
    tier: str = "recommended",
    flight_tier: str = "",
) -> dict:
    """What the Stay and Transit lines were priced from, in one line and two.

    Requested by the client, who supplied the wording: "Based on Best Value
    Direct Flight" and "Based on best value price. Individual rooms assumed for
    each pax." Both are printed where they are true, and neither is printed
    where it is not — a note is only worth having if the traveller can rely on
    it, and "Direct Flight" holds on 2 of the 30 live routes in cache.

    Written per tier. The card used to carry one note computed for Recommended
    and show it on every tab, so on Minimum it described a room and a fare that
    were not the ones on screen — which is what made it look as though the
    cheapest-room rule had never been applied at all.

    `summary` is the single line the Budget Allocation card always shows;
    `stay` and `transit` sit behind the tap on their own bars.
    """
    rank_label, rank_phrase, _ = _TIER_WORDS.get(
        tier, _TIER_WORDS["recommended"],
    )
    # The room wording follows the tab the traveller is looking at; the flight
    # wording follows the card the fare was actually read from, which is not
    # always the same tier - see `effective_flight_tier`.
    fare_tier = flight_tier or tier
    _, _, fare_rank = _TIER_WORDS.get(
        fare_tier, _TIER_WORDS.get(tier, _TIER_WORDS["recommended"]),
    )
    room_words = "3-star+ room" if at_star_floor else "room"
    stay_phrase = f"{rank_label} {room_words}"
    if rooms > 1:
        stay_phrase += ", 1 per person"

    stay_note = f"Based on {rank_phrase} {room_words}."
    notes = {
        "stay": (
            stay_note + " Individual rooms assumed for each pax."
            if rooms > 1 else stay_note
        ),
    }

    if no_airfare:
        # Nothing flies this route; `budget_advisory` already says so in full.
        notes["summary"] = f"{stay_phrase} · ground transport only"
        return notes

    if flight_basis == "none":
        # No fare of any kind reached the budget — a domestic trip, or a route
        # whose search returned nothing. Describing a flight here would invent
        # one; the stay line is all there is to explain.
        notes["summary"] = stay_phrase
        return notes

    notes["transit"], flight_phrase = {
        # The client's own wording, kept verbatim on the tier it describes.
        "direct": (
            "Based on Best Value Direct Flight"
            if fare_tier == "recommended"
            else f"Based on the {fare_rank} direct flight.",
            f"{fare_rank} direct flight",
        ),
        "connecting": (
            f"Based on the {fare_rank} flight. "
            "No direct flight is offered on this route.",
            f"{fare_rank} flight",
        ),
        "estimated": (
            "Based on an estimated fare — no live price was available for this route.",
            "estimated fare",
        ),
    }[flight_basis]
    notes["summary"] = f"{stay_phrase} · {flight_phrase}"
    return notes


def _money(currency: str, value: float) -> str:
    """One amount the way the card prints it: "INR 526,410"."""
    return f"{str(currency or '').upper()} {value:,.0f}".strip()


def budget_basis(
    *,
    tier: str,
    breakdown: dict,
    flight_strategies: dict | None,
    hotel_strategies: dict | None,
    city_legs: list[dict],
    travelers: int,
    days: int,
    currency: str,
    food_share: float,
    no_airfare: bool,
    at_star_floor: bool,
) -> dict:
    """How every line of one Budget Allocation tab was arrived at.

    The client asked for each category to open and explain itself. The
    explanation is built here, beside the arithmetic it describes, and the app
    only draws it: `stay` is `stay_cost_lines`, `transit` is
    `transit_cost_lines`, and `food`/`activities` are the waterfall's own
    subtraction written out. Deriving any of it in Dart instead would mean a
    second implementation of the star floor, the leg pooling and the 85%
    transit cap, and the sheet would eventually contradict the bar above it —
    the "budget split does not add up" report, reopened from the other side.

    Where a line is priced from nothing — no fares on the route, no room rates
    for the trip — the block says the figure is a share of the budget instead
    of inventing a derivation for it.
    """
    rooms = _rooms_for(travelers)
    party = max(int(travelers or 1), 1)
    notes = _budget_notes(
        rooms=rooms,
        at_star_floor=at_star_floor,
        flight_basis=budget_flight_basis(flight_strategies, tier),
        no_airfare=no_airfare,
        tier=tier,
        flight_tier=effective_flight_tier(flight_strategies, tier),
    )
    total = float(breakdown.get("total") or 0)
    stay_total = float(breakdown.get("stay") or 0)
    transit_total = float(breakdown.get("transit") or 0)
    food_total = float(breakdown.get("food") or 0)
    activities_total = float(breakdown.get("activities") or 0)
    rank_phrase = _TIER_WORDS.get(tier, _TIER_WORDS["recommended"])[1]

    def _nights(n: int) -> str:
        return f"{n} night" if n == 1 else f"{n} nights"

    # ── Stay: one line per city, exactly what the bar sums ──────────────
    lines = stay_cost_lines(hotel_strategies, city_legs, travelers, tier)
    stay_items: list[dict] = []
    for line in lines:
        room_word = "room" if line["rooms"] == 1 else "rooms"
        detail = [b for b in (
            line["hotel"],
            f"{line['hotel_class']}-star" if line["hotel_class"] else "",
        ) if b]
        detail.append(
            f"{_money(currency, line['nightly'])}/night"
            f" × {_nights(line['nights'])}"
            f" × {line['rooms']} {room_word}"
        )
        stay_items.append({
            "label": f"{line['city']} · {_nights(line['nights'])}".lstrip(" ·"),
            "detail": " · ".join(detail),
            "amount": line["amount"],
        })

    stay_caveat = ""
    if any(ln["basis"] == "pooled" for ln in lines):
        stay_caveat = (
            "One city's own hotel search came back empty; those nights are "
            "priced from the rest of the trip's rooms."
        )
    elif any(ln["basis"] == "unclassed" for ln in lines):
        stay_caveat = (
            "Some cities list nothing at 3 stars or above, so their nights are "
            "priced from whatever is listed there."
        )
    elif tier != "minimum" and any(ln.get("options", 0) < 3 for ln in lines):
        # With two rooms to choose from, the middle one and the dearest are the
        # same room, so this tab and another quote the same figure. Saying so
        # is the difference between a thin market and an app that looks broken
        # — the client has already reported the silent version of this.
        stay_caveat = (
            "Some cities list only one or two rooms, so this tab prices the "
            "same room as another."
        )
    if not stay_items and stay_total > 0:
        stay_items = [{
            "label": "Estimated share of the budget",
            "detail": "No room rates came back for this trip.",
            "amount": stay_total,
        }]

    rooms_word = "room" if rooms == 1 else "rooms"
    stay_formula = (
        f"{rank_phrase.capitalize()} "
        f"{'3-star+ room' if at_star_floor else 'room'} in each city"
        f" × {rooms} {rooms_word}"
        f"{' (one per traveller)' if rooms > 1 else ''}"
        f" × nights there"
    )

    # ── Transit: the one fare the budget took ──────────────────────────
    fare_lines = transit_cost_lines(flight_strategies, party, tier)
    transit_items: list[dict] = []
    transit_caveat = ""
    if fare_lines:
        fare = fare_lines[0]
        detail = [b for b in (fare["airline"], fare["stops_label"]) if b]
        detail.append(
            f"{_money(currency, fare['per_traveler'])} per traveller"
            f" × {fare['travelers']}"
        )
        transit_items.append({
            "label": fare["label"],
            "detail": " · ".join(detail),
            "amount": fare["amount"],
        })
        if not fare["live"]:
            transit_caveat = (
                "No live fare came back for this route, so this is an estimate."
            )
        elif not fare["tier_exact"]:
            transit_caveat = (
                "This tier had no fare of its own, so the cheapest one was used."
            )
        # `_waterfall` caps the transit line at 85% of the total. When that
        # bites, the fare above is not what the bar shows, and saying so is
        # the only honest way to print both.
        if abs(fare["amount"] - transit_total) > 1:
            transit_items.append({
                "label": "Held at 85% of the trip total",
                "detail": "The fare alone would take almost the whole budget.",
                "amount": transit_total,
            })
    elif no_airfare:
        transit_items.append({
            "label": "Ground transport only",
            "detail": "Nothing flies this route — trains, coaches and transfers.",
            "amount": transit_total,
        })
    elif transit_total > 0:
        transit_items.append({
            "label": "Estimated share of the budget",
            "detail": "No fares came back for this route.",
            "amount": transit_total,
        })

    transit_formula = (
        "Ground transport, as a share of the trip" if no_airfare
        else f"{rank_phrase.capitalize()} fare × {party} "
             f"{'traveller' if party == 1 else 'travellers'}"
    )

    # ── Food and activities: what is left, and how it divides ──────────
    remainder = round(total - (transit_total + stay_total), 2)
    food_pct = round(max(min(food_share, 1.0), 0.0) * 100)
    ladder = [
        {"label": "Trip total", "detail": f"{tier.capitalize()} plan",
         "amount": total},
        {"label": "less Flights & Transit", "detail": "", "amount": -transit_total},
        {"label": "less Stay", "detail": "", "amount": -stay_total},
        {"label": "Left for food and activities", "detail": "",
         "amount": remainder},
    ]

    def _per_day(amount: float) -> str:
        span = party * max(int(days or 0), 0)
        if span <= 0 or amount <= 0:
            return ""
        return f"About {_money(currency, amount / span)} per person per day."

    residual_formula = (
        "What is left after flights and rooms, split the way the day plan "
        "splits it"
    )

    return {
        "summary": notes.get("summary", ""),
        "stay": {
            "formula": stay_formula,
            "items": stay_items,
            "total": stay_total,
            "note": notes.get("stay", ""),
            "caveat": stay_caveat,
        },
        "transit": {
            "formula": transit_formula,
            "items": transit_items,
            "total": transit_total,
            "note": notes.get("transit", ""),
            "caveat": transit_caveat,
        },
        "food": {
            "formula": residual_formula,
            "items": ladder + [{
                "label": "Dining share of the day plan",
                "detail": f"{food_pct}% — read from the meals and activities planned",
                "amount": food_total,
            }],
            "total": food_total,
            "note": _per_day(food_total),
            "caveat": "",
        },
        "activities": {
            "formula": residual_formula,
            "items": ladder + [{
                "label": "Everything else in the day plan",
                "detail": f"{100 - food_pct}% — entry fees, tours, experiences",
                "amount": activities_total,
            }],
            "total": activities_total,
            "note": _per_day(activities_total),
            "caveat": "",
        },
    }


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
    geo=None,
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

    # A leg nobody sleeps on has nothing to book. The last leg of a trip that
    # flies home the day it arrives somewhere is the usual case - a 14-day Peru
    # plan closed "Paracas d12-13 -> Lima d14", and Lima was searched anyway
    # and shown four hotels priced for a night that is not in the trip. The
    # budget already skips these legs; the Stays tab did not, and the search
    # was bought regardless.
    stayed = [
        (i, leg) for i, leg in enumerate(legs)
        if int(leg.get("nights") or 0) > 0
    ]
    if not stayed:
        stayed = list(enumerate(legs))
    skipped = len(legs) - len(stayed)
    if skipped:
        logger.info(
            "Skipping hotels for %d leg(s) with no nights: %s",
            skipped,
            ", ".join(
                str(l.get("city")) for i, l in enumerate(legs)
                if int(l.get("nights") or 0) <= 0
            ),
        )

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
            # Which country this city is in, and where it is. Without them
            # "Saint Petersburg" is a US search. The country comes from the
            # Places-verified destination rather than the leg's own field,
            # which the model wrote and could have invented.
            country=(geo.country if geo is not None and geo.resolved else ""),
            country_code=(geo.country_code if geo is not None and geo.resolved else ""),
            latitude=leg.get("latitude"),
            longitude=leg.get("longitude"),
        )
        for _, leg in stayed
    ]
    results = await asyncio.gather(*searches, return_exceptions=True)

    merged: list[dict] = []
    tips: list[str] = []
    areas: list[str] = []
    # `index` is the leg's position in the original list, not in the filtered
    # one: the budget, the Stays tab and `_reprice_stays` all group by it.
    for (index, leg), result in zip(stayed, results):
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


# How the traveller reaches a leg's city. Anything else the model writes is
# dropped rather than stored, so the prompt never quotes an invented mode.
_ARRIVE_BY_MODES = ("flight", "train", "bus", "car", "ferry", "none")


def _geo_leg(leg: dict, entry: dict) -> None:
    """Carry the planner's optional geography onto a validated leg.

    Coordinates, arrival mode and distance are what the route check and the
    arrival/departure rules in the prompt read. Every field is optional and
    silently omitted when unparseable: a leg without coordinates is still a
    valid leg, it just cannot be distance-checked.
    """
    for key in ("latitude", "longitude"):
        try:
            value = float(entry.get(key))
        except (TypeError, ValueError):
            continue
        limit = 90.0 if key == "latitude" else 180.0
        if math.isfinite(value) and abs(value) <= limit:
            leg[key] = round(value, 4)
    arrive_by = str(entry.get("arrive_by") or "").strip().lower()
    if arrive_by in _ARRIVE_BY_MODES:
        leg["arrive_by"] = arrive_by
    try:
        km = int(float(entry.get("from_previous_km")))
    except (TypeError, ValueError):
        return
    if km >= 0:
        leg["from_previous_km"] = km


def _leg_coords(leg: dict | None) -> tuple[float, float] | None:
    if not isinstance(leg, dict):
        return None
    lat, lng = leg.get("latitude"), leg.get("longitude")
    if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
        return float(lat), float(lng)
    return None


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
        _geo_leg(leg, entry)
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


# Geographic drift detection lived here: a free regex scan over generated
# place names plus up to three Places geocodes, and one corrective
# regeneration when the plan had relocated to the wrong country. Removed
# 2026-09-14 — the team lead's decision is that the prompt's per-city
# coordinates and the model's own google_search checking are sufficient,
# and that the backend should not verify the model's output. The prompt
# side of that grounding is in `_build_prompt` (DESTINATION IDENTITY and
# the route table); `geo_resolver.foreign_place_hits` and `verify_place`
# are still there if the decision is ever revisited.


# ── Route planning ─────────────────────────────────────────────────────────
#
# Where the trip goes AND how it is entered and left, decided in one call
# before anything is searched. The flight search used to start in parallel
# with the leg planner, so the arrival airport was chosen for the destination
# *string* ("India" -> DEL) while the legs were chosen with no idea where the
# traveller lands. A wildlife itinerary duly opened 1,000 km from the airport
# with no word on how to get there, and the return was priced from an airport
# the trip never came back to. The planner now names the gateways for the
# route it actually drew, and the flights are searched for those.

# How far the first/last leg may sit from its gateway before the plan is sent
# back for one more attempt. A regional hop or an overnight train covers this;
# anything further is a different region and wants a different gateway.
_GATEWAY_MAX_KM = 400.0

# Consecutive legs further apart than this need a flagged flight/train hop —
# "car" between two cities 900 km apart is a day lost on the road.
_LEG_HOP_MAX_KM = 600.0

# Below this the gateway city and the first leg are the same place: no
# transfer activity is demanded, an airport taxi is part of check-in.
_SAME_PLACE_KM = 40.0

# Airports do not move. Verified coordinates are kept for a month so the
# gateway check on a popular route costs no Places lookup at all.
_AIRPORT_GEO_TTL_S = 30 * 24 * 60 * 60

# One re-plan, ever, when the route comes back incoherent. Same shape as the
# geographic-drift regeneration below: a straight line, not a loop.
_MAX_ROUTE_RETRIES = 1

_AIRPORT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "iata": {"type": "STRING"},
        "city": {"type": "STRING"},
        "name": {"type": "STRING"},
    },
    "required": ["iata", "city"],
    "propertyOrdering": ["iata", "city", "name"],
}

# Gemini `responseSchema` for the route planner. Constrained decoding is what
# makes this call machine-readable without a parse-and-repair pass; the
# coherence checks in `_validate_route` are still the real guard.
_ROUTE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "region": {"type": "STRING"},
        "legs": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "city": {"type": "STRING"},
                    "country": {"type": "STRING"},
                    "start_day": {"type": "INTEGER"},
                    "end_day": {"type": "INTEGER"},
                    "latitude": {"type": "NUMBER"},
                    "longitude": {"type": "NUMBER"},
                    "arrive_by": {"type": "STRING", "enum": list(_ARRIVE_BY_MODES)},
                    "from_previous_km": {"type": "INTEGER"},
                },
                "required": [
                    "city", "country", "start_day", "end_day",
                    "latitude", "longitude", "arrive_by", "from_previous_km",
                ],
                "propertyOrdering": [
                    "city", "country", "start_day", "end_day",
                    "latitude", "longitude", "arrive_by", "from_previous_km",
                ],
            },
        },
        "arrival_airport": _AIRPORT_SCHEMA,
        "departure_airport": _AIRPORT_SCHEMA,
    },
    "required": ["region", "legs", "arrival_airport", "departure_airport"],
    "propertyOrdering": ["region", "legs", "arrival_airport", "departure_airport"],
}


@dataclass
class RoutePlan:
    """The cities the trip sleeps in and the airports it enters and leaves by.

    `arrival_code` / `departure_code` are what SerpApi is given (comma-separated
    where a gateway city has several airports). Empty means "not decided here":
    the flight search then resolves the destination the way it always did.
    """
    legs: list[dict]
    arrival: dict | None = None
    departure: dict | None = None
    arrival_code: str = ""
    departure_code: str = ""
    region: str = ""
    source: str = "fallback"        # "planner" | "fallback"
    reasons: list[str] = field(default_factory=list)

    @property
    def trip_type(self) -> str:
        if not self.arrival_code or not self.departure_code:
            return ""
        same = set(self.arrival_code.split(",")) == set(self.departure_code.split(","))
        return "round_trip" if same else "open_jaw"

    def arrival_km(self) -> float | None:
        return _airport_leg_km(self.arrival, self.legs[0] if self.legs else None)

    def departure_km(self) -> float | None:
        return _airport_leg_km(self.departure, self.legs[-1] if self.legs else None)

    def as_meta(self) -> dict:
        """The additive keys stored on `flight_strategies` for the app."""
        return {
            "arrival_airport": _public_airport(self.arrival),
            "departure_airport": _public_airport(self.departure),
            "trip_type": self.trip_type,
        }


def _public_airport(airport: dict | None) -> dict:
    if not airport:
        return {}
    return {
        "iata": airport.get("iata", ""),
        "city": airport.get("city", ""),
        "name": airport.get("name", ""),
    }


def _airport_leg_km(airport: dict | None, leg: dict | None) -> float | None:
    a = _leg_coords(airport)
    b = _leg_coords(leg)
    if a is None or b is None:
        return None
    return geo_resolver.haversine_km(a[0], a[1], b[0], b[1])


def _parse_airport(raw) -> dict | None:
    """A planner airport entry with a usable IATA code, or None."""
    if not isinstance(raw, dict):
        return None
    code = str(raw.get("iata") or "").strip().upper()
    if len(code) != 3 or not code.isalpha() or code in _METRO_CODES:
        return None
    return {
        "iata": code,
        "city": str(raw.get("city") or "").strip(),
        "name": str(raw.get("name") or "").strip(),
    }


def _validate_route(
    parsed, destination: str, days: int, start_date: str = "", geo=None,
) -> tuple[RoutePlan, list[str]]:
    """Coerce a planner response into a RoutePlan and list what is wrong with it.

    Legs go through the same structural gate as before (`_validate_legs`), so
    an unusable leg list still degrades to a single leg. The reasons returned
    are the *coherence* problems worth one re-plan: a leg-to-leg hop too long
    for the mode claimed, or a gateway that is not a real code. Gateway
    distance is checked by the caller once the airport has been located.
    """
    data = parsed if isinstance(parsed, dict) else {}
    legs = _validate_legs(data.get("legs"), destination, days, start_date, geo)
    plan = RoutePlan(
        legs=legs,
        arrival=_parse_airport(data.get("arrival_airport")),
        departure=_parse_airport(data.get("departure_airport")),
        region=str(data.get("region") or "").strip(),
        source="planner",
    )

    reasons: list[str] = []
    for prev, cur in zip(legs, legs[1:]):
        km = _airport_leg_km(prev, cur)
        if km is None:
            continue
        mode = cur.get("arrive_by", "")
        if km > _LEG_HOP_MAX_KM and mode not in ("flight", "train"):
            reasons.append(
                f"Leg '{cur['city']}' is about {km:,.0f} km from '{prev['city']}' but "
                f"arrive_by is '{mode or 'unset'}' — either cluster the route more tightly "
                f"or mark the hop as a flight or train."
            )
    for label, raw in (("arrival_airport", data.get("arrival_airport")),
                       ("departure_airport", data.get("departure_airport"))):
        if raw is not None and _parse_airport(raw) is None:
            reasons.append(
                f"{label} '{(raw or {}).get('iata') if isinstance(raw, dict) else raw}' is not a "
                f"real 3-letter IATA airport code (metropolitan codes like LON/NYC are not accepted)."
            )
    return plan, reasons


async def _airport_geo(code: str, geo, budget=None, city: str = "") -> dict | None:
    """Where an airport is, from Places, cached for a month.

    Returns {"latitude", "longitude", "country_code", "name"} or None when the
    lookup could not run (no budget, no key, no result). None means "unknown",
    never "wrong" — the caller keeps the code, as `_verify_airport_codes` does.

    The query carries the destination country, and the city when the caller
    knows it. A bare "RAK airport" resolves to Ras Al Khaimah in the UAE, so a
    Morocco plan rejected Marrakesh's own airport as foreign and flew the
    traveller into Casablanca, 197 km from the first city. The country is part
    of the cache key for the same reason: one bad lookup used to stand for that
    code for a month, across every destination.
    """
    country = str(getattr(geo, "country", "") or "").strip()
    cc = str(getattr(geo, "country_code", "") or "").strip().upper()
    cache_key = f"geo:airport:v2:{cc or '??'}:{code}"
    try:
        cached = await place_cache_service.get_raw(cache_key)
        if cached:
            data = json.loads(cached)
            if isinstance(data, dict) and data.get("latitude") is not None:
                return data
    except Exception:
        pass

    if geo is None or not geo.resolved:
        return None
    query = " ".join(p for p in (str(city or "").strip(), code, "airport", country) if p)
    check = await geo_resolver.verify_place(
        query,
        near=geo_resolver.DestinationContext(query=code, country_code=geo.country_code),
        max_km=None,
        budget=budget,
    )
    if not check.checked or check.latitude is None or check.longitude is None:
        return None
    data = {
        "latitude": check.latitude,
        "longitude": check.longitude,
        "country_code": check.country_code,
        "name": check.resolved_name,
    }
    try:
        await place_cache_service.set_raw(cache_key, json.dumps(data), ttl=_AIRPORT_GEO_TTL_S)
    except Exception:
        pass
    return data


async def _locate_gateway(airport: dict | None, geo, budget=None) -> tuple[dict | None, str]:
    """Attach coordinates to a planner gateway; reject one in the wrong country.

    Returns (airport, reason). A rejected airport comes back as None with the
    reason; an unverifiable one is kept as-is with no coordinates.
    """
    if not airport:
        return None, ""
    located = await _airport_geo(airport["iata"], geo, budget, city=airport.get("city") or "")
    if located is None:
        return airport, ""
    if (
        geo is not None and geo.resolved and located.get("country_code")
        and located["country_code"] != geo.country_code
    ):
        return None, (
            f"Airport {airport['iata']} is in {located['country_code']}, not in "
            f"{geo.country or geo.country_code} — choose an airport inside the country."
        )
    enriched = dict(airport)
    enriched["latitude"] = located["latitude"]
    enriched["longitude"] = located["longitude"]
    if not enriched.get("name") and located.get("name"):
        enriched["name"] = located["name"]
    return enriched, ""


def _gateway_distance_reason(label: str, airport: dict | None, leg: dict | None) -> str:
    """A leg too far from its gateway, unless the planner flagged a flight there."""
    km = _airport_leg_km(airport, leg)
    if km is None or km <= _GATEWAY_MAX_KM:
        return ""
    if label == "arrival" and leg.get("arrive_by") == "flight":
        return ""
    verb = "lands at" if label == "arrival" else "flies home from"
    return (
        f"The traveller {verb} {airport['iata']} but the {'first' if label == 'arrival' else 'last'} "
        f"leg '{leg['city']}' is about {km:,.0f} km away. Pick the gateway airport nearest "
        f"'{leg['city']}' instead, or move the {'first' if label == 'arrival' else 'last'} "
        f"leg within {_GATEWAY_MAX_KM:.0f} km of {airport['iata']}."
    )


def _search_code_for(airport: dict | None) -> str:
    """The comma-separated code list SerpApi is given for a gateway.

    A verified single code is widened to the whole city where the static
    table knows the city has several airports: London means LHR, LGW, STN and
    LTN, and searching all four is what surfaces the cheaper one.
    """
    if not airport:
        return ""
    code = airport["iata"]
    city_key = (airport.get("city") or "").strip().lower().split(",")[0].strip()
    table = _AIRPORT_CODES.get(city_key, "") if city_key else ""
    if table and code in table.split(","):
        return table
    return code


def _route_prompt(
    *,
    destination: str,
    days: int,
    mood: str,
    travelers: int,
    geo,
    origin_line: str,
    correction: str = "",
    entry_city: str = "",
    exit_city: str = "",
    entry_latlng: tuple[float | None, float | None] = (None, None),
    exit_latlng: tuple[float | None, float | None] = (None, None),
) -> str:
    # This call is where the hotel search's city strings come from, so an
    # invented country here is expensive: it books rooms in the wrong place.
    geo_line = ""
    country = ""
    is_country = False
    if geo is not None and geo.resolved:
        country = geo.country or geo.country_code
        is_country = bool(getattr(geo, "is_country", False))
        geo_line = (
            f"\n{destination} is in {country}"
            + (f", {geo.admin_area}" if geo.admin_area else "")
            + (f", at {geo.latitude:.4f}, {geo.longitude:.4f}" if geo.has_coords else "")
            + (" — it is a whole country, not a city." if is_country else "")
            + "\n"
        )

    country_rule = ""
    if country:
        country_rule = (
            f"- EVERY leg must be a real city or town in {country}, and the \"country\" "
            f"field of every leg MUST be exactly \"{geo.country_code}\". Both airports MUST "
            f"be in {country}. If the destination's name resembles a place in another "
            f"country, ignore the resemblance.\n"
        )

    region_rule = (
        f"- {destination} is a whole country. Choose ONE coherent region sized to "
        f"{days} days — the cities a traveller with this style would actually combine "
        f"in one trip — and stay inside it. Do not scatter legs across the country.\n"
        if is_country else
        f"- If {destination} is a single city, return exactly one leg for it, and its own "
        f"(or nearest) airport as both arrival_airport and departure_airport.\n"
    )

    # Where the traveller asked to start and finish. Optional and independent:
    # either may be given alone, and the planner chooses the other end.
    #
    # These outrank the clustering rule below, because the traveller has said
    # something about their own trip the model cannot know - a flight already
    # booked into one city, a wedding in another. A route stretched as a result
    # is not corrected; it is explained, the way a budget that will not cover
    # the trip is explained rather than quietly trimmed.
    def _at(latlng) -> str:
        """" at 7.2906, 80.6337", or nothing when the app did not send it.

        Worth stating rather than leaving to inference: the app picked the place
        from Google and knows where it is, while the model would work it out
        from the name - and its answer becomes that leg's coordinates, which the
        hotel search and every distance check downstream are measured against.
        A wrong guess there is not one wrong line, it is the trip.
        """
        pair = latlng if isinstance(latlng, (tuple, list)) and len(latlng) == 2 else (None, None)
        lat, lng = pair
        if lat is None or lng is None:
            return ""
        try:
            return f" at {float(lat):.4f}, {float(lng):.4f}"
        except (TypeError, ValueError):
            return ""

    entry_at, exit_at = _at(entry_latlng), _at(exit_latlng)

    ends = []
    if entry_city:
        ends.append(
            f'- THE TRAVELLER STARTS AT {entry_city}{entry_at}. The FIRST leg\'s "city" MUST be '
            f'"{entry_city}"{", with exactly those coordinates" if entry_at else ""}, whatever the clustering rule below would otherwise prefer. '
            f'"arrival_airport" MUST be the airport with scheduled flights nearest '
            f'{entry_city} - if {entry_city} has none of its own, the nearest one that '
            f'has, and the traveller reaches {entry_city} from it by road.'
        )
    if exit_city:
        ends.append(
            f'- THE TRAVELLER FINISHES AT {exit_city}{exit_at}. The LAST leg\'s "city" MUST be '
            f'"{exit_city}"{", with exactly those coordinates" if exit_at else ""}, and "departure_airport" MUST be the airport nearest it.'
        )
    if entry_city and exit_city and entry_city.strip().lower() != exit_city.strip().lower():
        ends.append(
            f'- Order the cities between {entry_city} and {exit_city} so the route runs '
            f'from one to the other without backtracking. If the two are far apart for '
            f'{days} days, use fewer stops and longer hops rather than dropping either '
            f'end - both were asked for.'
        )
    if ends and country:
        # The country rule below is absolute, and these are requests. The app
        # holds the exit search to the entry's country so the pair should
        # always agree, but the API can be called without it - and an end in
        # the wrong country must be dropped rather than drag a leg out of the
        # country the whole trip is planned in.
        ends.append(
            f'- If either of those two places is not in {country}, ignore that one '
            f'and choose that end yourself. A trip starts and finishes in the same '
            f'country, and the country rule below outranks both.'
        )
    ends_rule = ("\n".join(ends) + "\n") if ends else ""

    correction_rules = ""
    if correction:
        correction_rules = f"""
CRITICAL — YOUR PREVIOUS ROUTE WAS NOT WORKABLE:
{correction}
Redraw the route so that every problem above is fixed. Keep the same trip length.
"""

    return f"""Plan the city-by-city route for a {days}-day trip to {destination}, including the airport the traveller should fly INTO and the airport they should fly HOME FROM.
{geo_line}{origin_line}Group: {travelers} traveller(s). Travel style: {mood or "balanced"}.
{correction_rules}
Return ONLY this JSON:
{{"region": "...", "legs": [{{"city": "...", "country": "<ISO 2-letter>", "start_day": 1, "end_day": 3, "latitude": 0.0, "longitude": 0.0, "arrive_by": "flight|train|bus|car|ferry|none", "from_previous_km": 0}}], "arrival_airport": {{"iata": "XXX", "city": "...", "name": "..."}}, "departure_airport": {{"iata": "XXX", "city": "...", "name": "..."}}}}

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
{ends_rule}{region_rule}- CLUSTER THE ROUTE: order the legs so the trip never backtracks, and keep each
  leg within about {_LEG_HOP_MAX_KM:.0f} km by road of the previous one unless "arrive_by"
  for that leg is "flight" or "train".
- "latitude"/"longitude": the city's coordinates to 2 decimal places.
- "arrive_by": how the traveller reaches this leg's city — from the arrival
  airport for the first leg, from the previous city for the others. Use "none"
  only when the first leg IS the arrival airport's own city.
- "from_previous_km": approximate travel distance in km for that hop (0 when
  arrive_by is "none").
- "arrival_airport": the airport with scheduled commercial flights that is
  NEAREST to the FIRST leg's city — not the capital and not the country's
  biggest hub by default. The first leg's city must be within about
  {_GATEWAY_MAX_KM:.0f} km of it. If the nearest airport with international
  service is further away than that, still name the closest airport with
  scheduled flights and set the first leg's arrive_by to "flight".
- "departure_airport": the airport with scheduled flights NEAREST to the LAST
  leg's city. When the last leg's city is within about {_GATEWAY_MAX_KM:.0f} km
  of the arrival airport, use the arrival airport again — a round trip is
  cheaper than flying home from somewhere else.
- "iata": the real 3-letter IATA airport code (e.g. DEL, NAG, LHR). Never a
  metropolitan area code such as LON, NYC, PAR or TYO.
{country_rule}- No commentary, no markdown."""


async def plan_route(
    *,
    destination: str,
    days: int,
    mood: str,
    travelers: int,
    api_key: str,
    start_date: str = "",
    geo=None,
    departure_city: str = "",
    departure_country: str = "",
    departure_latitude: float | None = None,
    departure_longitude: float | None = None,
    include_flights: bool = True,
    geo_budget=None,
    entry_city: str = "",
    exit_city: str = "",
    entry_latlng: tuple[float | None, float | None] = (None, None),
    exit_latlng: tuple[float | None, float | None] = (None, None),
) -> RoutePlan:
    """Decide the cities the trip sleeps in and the airports it uses, in one call.

    Runs before flights and hotels are bought: the per-leg hotel search needs
    the cities, and the flight search needs the gateways — which only make
    sense once the route is known. Coherence (leg spacing, gateway distance,
    airport country) is checked here, with one corrective re-plan; a route
    that is merely imperfect after that is kept and explained to the traveller
    by the arrival/departure rules in the itinerary prompt, never silently
    collapsed to a single leg.

    Deliberately ungrounded: `_call_gemini` can only ask for JSON mode when no
    search tool is attached, and a reliable machine-readable answer matters
    more here than live facts — the grounded itinerary pass still checks the
    places themselves.
    """
    days = max(int(days or 1), 1)
    if not api_key or days < 2:
        return RoutePlan(legs=_single_leg(destination, days, start_date, geo))

    # Where the traveller starts, so the gateway can be judged from their
    # side too. The app sends the literal word "Nearby" when its reverse
    # geocode fails; the coordinates still say which country they are in.
    origin_line = ""
    dep_name = "" if _is_non_place(departure_city) else (departure_city or "").strip()
    dep_ctry = "" if _is_non_place(departure_country) else (departure_country or "").strip()
    has_dep_coords = departure_latitude is not None and departure_longitude is not None
    if dep_name or dep_ctry or has_dep_coords:
        where = ", ".join(x for x in (dep_name, dep_ctry) if x) or "their home location"
        if has_dep_coords:
            where += f" (coordinates {departure_latitude:.4f}, {departure_longitude:.4f})"
        origin_line = f"The traveller starts from {where} and flies in.\n"

    async def _attempt(correction: str) -> tuple[RoutePlan, list[str]]:
        prompt = _route_prompt(
            entry_city=entry_city, exit_city=exit_city,
            entry_latlng=entry_latlng, exit_latlng=exit_latlng,
            destination=destination, days=days, mood=mood, travelers=travelers,
            geo=geo, origin_line=origin_line, correction=correction,
        )
        raw, _ = await _call_gemini(
            prompt, api_key, max_tokens=3072, thinking_budget=1024,
            use_grounding=False, response_schema=_ROUTE_SCHEMA, operation="odyssey_route",
        )
        plan, reasons = _validate_route(_parse_json(raw), destination, days, start_date, geo)

        # Locate the gateways (Places, budgeted, cached) and judge their distance
        # from the legs they serve. Only worth paying for when a flight will be
        # searched for them.
        if include_flights:
            arrival, why = await _locate_gateway(plan.arrival, geo, geo_budget)
            plan.arrival = arrival
            if why:
                reasons.append(why)
            departure, why = await _locate_gateway(plan.departure, geo, geo_budget)
            plan.departure = departure
            if why:
                reasons.append(why)
            for label, airport, leg in (
                ("arrival", plan.arrival, plan.legs[0] if plan.legs else None),
                ("departure", plan.departure, plan.legs[-1] if plan.legs else None),
            ):
                why = _gateway_distance_reason(label, airport, leg)
                if why:
                    reasons.append(why)
        return plan, reasons

    try:
        plan, reasons = await _attempt("")
    except Exception as e:
        logger.warning(f"Route planning failed, using a single leg: {e}")
        return RoutePlan(legs=_single_leg(destination, days, start_date, geo))

    if reasons:
        logger.warning(
            "Route for %s is incoherent: %s", destination, " | ".join(reasons),
        )
        for _ in range(_MAX_ROUTE_RETRIES):
            try:
                retry_plan, retry_reasons = await _attempt("\n".join(reasons))
            except Exception as e:
                logger.warning("Route re-plan failed, keeping the first route: %s", e)
                break
            # Keep the retry only when it is actually better.
            if len(retry_reasons) < len(reasons):
                plan, reasons = retry_plan, retry_reasons
            break
        if reasons:
            logger.warning(
                "Route for %s still incoherent after re-plan: %s",
                destination, " | ".join(reasons),
            )
    plan.reasons = list(reasons)

    # A gateway the planner got wrong is replaced by the resolver's answer for
    # the leg it should serve — the same lookup the destination used to get,
    # now aimed at the right city.
    if include_flights:
        for attr, leg in (("arrival", plan.legs[0]), ("departure", plan.legs[-1])):
            if getattr(plan, attr) is None and leg:
                coords = _leg_coords(leg)
                code = await _resolve_airport_code(
                    leg["city"],
                    (geo.country if geo is not None and geo.resolved else ""),
                    api_key,
                    latitude=coords[0] if coords else None,
                    longitude=coords[1] if coords else None,
                    country_code=(geo.country_code if geo is not None else ""),
                    budget=geo_budget,
                )
                if code:
                    first = code.split(",")[0]
                    setattr(plan, attr, {"iata": first, "city": leg["city"], "name": "", "_codes": code})
        plan.arrival_code = (plan.arrival or {}).get("_codes") or _search_code_for(plan.arrival)
        plan.departure_code = (plan.departure or {}).get("_codes") or _search_code_for(plan.departure)
        for airport in (plan.arrival, plan.departure):
            if airport:
                airport.pop("_codes", None)

    logger.info(
        "Planned %d city leg(s) for %s: %s | in via %s, out via %s (%s)",
        len(plan.legs), destination,
        ", ".join(f"{l['city']} d{l['start_day']}-{l['end_day']}" for l in plan.legs),
        plan.arrival_code or "?", plan.departure_code or "?", plan.trip_type or "no flights",
    )
    return plan


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
    """The city legs alone — `plan_route` for callers that only need the cities."""
    plan = await plan_route(
        destination=destination, days=days, mood=mood, travelers=travelers,
        api_key=api_key, start_date=start_date, geo=geo, include_flights=False,
    )
    return plan.legs


async def _reconcile_gateways(
    route, flight_strategies: dict, primary_flight: dict | None, geo=None, budget=None,
) -> None:
    """Point the trip's gateways at the airports the chosen flight actually uses.

    Mutates both `route` (read by the itinerary prompt) and the
    `flight_strategies` header (read by the app) so the two cannot disagree.
    Only the primary flight can speak for the trip: tiers may land at different
    airports, and each tier already carries its own `outbound`/`return`.

    Anything we cannot read is left alone — a strategy without leg objects (the
    AI-estimate path) keeps the planner's gateways rather than losing them.
    """
    if not isinstance(primary_flight, dict) or not isinstance(flight_strategies, dict):
        return

    async def _swap(attr: str, leg_key: str, field: str) -> None:
        leg = primary_flight.get(leg_key)
        if not isinstance(leg, dict):
            return
        # Outbound is named by where it lands; the return by where it leaves.
        code = str(leg.get("destination" if leg_key == "outbound" else "origin") or "").strip().upper()
        if not _AIRPORT_CODE_RE.match(code):
            return
        planned = dict(getattr(route, attr, None) or flight_strategies.get(field) or {})
        if planned.get("iata") == code:
            return
        logger.info(
            "Gateway %s: planner said %s, the booked flight uses %s — using the flight.",
            attr, planned.get("iata") or "?", code,
        )
        # The city carries over — LGW and LHR are both London — but the name
        # and the coordinates described the old airport, so they are re-fetched
        # for the new one. Without that the transfer distance would still be
        # measured from Heathrow for a flight landing at Gatwick, which is the
        # whole reason this function exists. Airport coordinates are cached for
        # a month, so this is free on any route seen before.
        resolved = {"iata": code, "city": planned.get("city", ""), "name": ""}
        located = await _airport_geo(code, geo, budget, city=resolved["city"])
        if located:
            resolved["latitude"] = located["latitude"]
            resolved["longitude"] = located["longitude"]
            if located.get("name"):
                resolved["name"] = located["name"]
        setattr(route, attr, resolved)
        # The app reads only the public three; coordinates stay internal.
        flight_strategies[field] = _public_airport(resolved)

    await _swap("arrival", "outbound", "arrival_airport")
    await _swap("departure", "return", "departure_airport")

    trip_type = primary_flight.get("trip_type")
    if trip_type:
        flight_strategies["trip_type"] = trip_type


# Output budget for the day-by-day plan, scaled to the trip. A fixed 8192 cap
# was enough for a week and silently truncated a fortnight: a 14-day, five-city
# plan with priced, sourced activities runs to ~16k tokens, and the response
# came back cut off mid-object and failed to parse — reported as a "failed"
# Odyssey. Gemini 2.5 Flash allows far more; output is billed per token used,
# so a larger ceiling costs nothing on the trips that never reach it.
_ITINERARY_TOKENS_BASE = 6144
_ITINERARY_TOKENS_PER_DAY = 1200
_ITINERARY_TOKENS_MAX = 32768


def _itinerary_token_budget(days: int) -> int:
    return min(_ITINERARY_TOKENS_MAX, _ITINERARY_TOKENS_BASE + _ITINERARY_TOKENS_PER_DAY * max(int(days or 1), 1))


def _itinerary_timeout_s(days: int) -> float:
    """Long plans stream for longer; ~12 s per day with a floor of 90 s."""
    return max(90.0, 12.0 * max(int(days or 1), 1))


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
    entry_city: str = "",
    exit_city: str = "",
    entry_latitude: float | None = None,
    entry_longitude: float | None = None,
    exit_latitude: float | None = None,
    exit_longitude: float | None = None,
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

    # 1. Cover photo first (it needs only the destination), then the route,
    # then flights and hotels concurrently. Flights used to start alongside
    # the route planner, which is exactly how they came to land the traveller
    # at an airport the route never went near: the gateways are an output of
    # the route now, so the flight search waits the planner's 2-7 s for them.
    async def _get_cover():
        # Through the shared cache, so this is the *same* photo the list
        # endpoint already put on the placeholder while the plan was being
        # written — and, since that poll fires first, usually a Redis hit
        # rather than a second lookup.
        try:
            return await cover_photo_service.cover_for_destination(
                final_destination, unsplash_api_key or ""
            )
        except Exception as e:
            logger.error(f"Cover photo fetch failed: {e}")
            return ""

    cover_task = asyncio.create_task(_get_cover())

    # Coordinates alone are enough: the country recovered from them gives a
    # real origin airport, where the name may only have been "Nearby".
    _has_departure = bool(str(departure_city or "").strip()) or (
        departure_latitude is not None and departure_longitude is not None
    )
    search_flights = include_flights and _has_departure

    # Which cities the trip sleeps in and which airports it enters and leaves
    # by, decided before anything is bought: the per-leg hotel search needs
    # the cities, the flight search needs the gateways, and the itinerary that
    # would otherwise name them is not written until further down.
    try:
        route = await plan_route(
            destination=final_destination,
            days=days,
            mood=mood,
            travelers=travelers,
            api_key=api_key,
            start_date=hotel_check_in_date or start_date or "",
            geo=geo,
            departure_city=departure_city,
            departure_country=departure_country,
            departure_latitude=departure_latitude,
            departure_longitude=departure_longitude,
            include_flights=search_flights,
            geo_budget=geo_budget,
            entry_city=entry_city,
            exit_city=exit_city,
            entry_latlng=(entry_latitude, entry_longitude),
            exit_latlng=(exit_latitude, exit_longitude),
        )
    except BaseException:
        # plan_route has its own fallback and should not raise, but if it
        # does (or this task is cancelled) the in-flight lookup must not be
        # left running with nobody to collect it.
        cover_task.cancel()
        raise
    city_legs = route.legs

    async def _get_flights():
        if search_flights:
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
                    route_plan=route,
                )
            except Exception as e:
                logger.error(f"Flight strategy sub-job failed: {e}")
                return {}
        return {}

    async def _get_hotels():
        if include_hotels:
            try:
                return await generate_hotel_strategies_for_legs(
                    legs=city_legs,
                    geo=geo,
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

    async def _get_hops():
        """Live fares for the legs the traveller flies between cities.

        Runs beside the main flight and hotel searches, not after: it is the
        same kind of lookup and there is no reason for the traveller to wait
        for it in sequence.
        """
        if not (search_flights and include_flights):
            return []
        try:
            return await generate_inter_city_flights(
                legs=city_legs, geo=geo, currency=currency, travelers=travelers,
                start_date=start_date or flight_start_date or "",
                api_key=api_key, serpapi_key=serpapi_key, geo_budget=geo_budget,
            )
        except Exception as e:
            logger.error(f"Inter-city flight sub-job failed: {e}")
            return []

    cover_url, flight_strategies, hotel_strategies, inter_city_flights = await asyncio.gather(
        cover_task, _get_flights(), _get_hotels(), _get_hops()
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
    hotel_price_range, hotel_range_by_leg = nightly_ranges(hotel_strategies, currency)

    # Extract primary flight entity if available — the Recommended tier when
    # there is one, since that is the card the traveller is steered to and the
    # one whose return leg was priced; otherwise the first usable strategy.
    # Flight strategies key their label as "title"; only hotels use "name".
    primary_flight = None
    if flight_strategies and isinstance(flight_strategies.get("strategies"), list):
        usable = [
            s for s in flight_strategies["strategies"]
            if isinstance(s, dict) and (s.get("title") or s.get("name"))
        ]
        primary_flight = next(
            (s for s in usable if s.get("tier") == "recommended"), usable[0] if usable else None,
        )

    # The gateways the planner named were a starting point for the search, not
    # a result of it. A city we know by several airports is searched across all
    # of them — "london" expands to LHR,LGW,STN,LTN, which is how Gatwick turns
    # up ~40,000 INR cheaper than Heathrow — so the airport on the ticket is
    # routinely not the one the planner guessed. Everything downstream reads
    # these fields: the app's "Land at ..." line, and the arrival/departure
    # transfer instructions in the prompt below, whose distances would
    # otherwise be measured from the wrong airport (MXP and BGY are 45 km
    # apart, NRT and HND 60, ARN and NYO 100).
    await _reconcile_gateways(route, flight_strategies, primary_flight, geo, geo_budget)

    # 2. Build grounded prompt using confirmed live inventory
    # What the itinerary itself has left to spend, from the real fares and room
    # rates rather than a percentage the model guesses at. See the helper.
    spend_room = food_and_activities_room(
        budget=budget,
        flight_strategies=flight_strategies,
        hotel_strategies=hotel_strategies,
        city_legs=city_legs,
        travelers=travelers,
        on_ground=trip_cost_floor.on_ground_floor(
            destination=final_destination,
            days=days,
            travelers=travelers,
            currency=currency,
        ) or 0.0,
    )

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
        route_plan=route,
        inter_city_flights=inter_city_flights,
        spend_room=spend_room,
    )
    plan_tokens = _itinerary_token_budget(days)
    plan_timeout = _itinerary_timeout_s(days)
    try:
        text, grounding_chunks = await _call_gemini(
            prompt, api_key, max_tokens=plan_tokens, thinking_budget=0, use_grounding=True,
            timeout_s=plan_timeout,
        )
        plan = _parse_json(text)
        # A response that parses but carries no days — or only some of them —
        # is as useless as one that does not parse, and it used to travel
        # another 500 lines before dying as "Generated plan had no days", past
        # the one retry that could have saved it. Raising here puts both on the
        # same footing as a parse error.
        _require_days(plan, text, days)
    except Exception as e:
        logger.warning(
            "Grounded Gemini generation/parsing failed (%s) — falling back to standard ungrounded generation",
            e,
        )
        text, grounding_chunks = await _call_gemini(
            prompt, api_key, max_tokens=plan_tokens, thinking_budget=0, use_grounding=False,
            timeout_s=plan_timeout,
        )
        plan = _parse_json(text)
        # Empty still fails. Short does not: two of three days beats no plan at
        # all, which is the rule this pipeline has always followed. What it
        # never did was say so — a six-day header, six-day dates and a six-day
        # budget sat over three days of itinerary and nothing on screen
        # mentioned it. The notice below is the half that was missing.
        _require_days(plan, text)

    notices = [
        _short_plan_notice(plan, days),
        stretched_route_notice(route, days, entry_city, exit_city),
    ]
    plan_advisory = " ".join(n for n in notices if n)
    if plan_advisory:
        logger.warning("%s", plan_advisory)

    # The itinerary is written against the legs, but the model sometimes moves
    # a day early. The legs book the hotels, so they follow the itinerary here
    # rather than the other way round — before the stay cost, the budget and
    # the meta block are all computed from them below.
    moved = _align_legs_to_itinerary(
        city_legs, plan.get("day_plans"), days, inter_city_flights,
    )
    if moved:
        logger.info("Leg boundaries realigned to the itinerary: %s", "; ".join(moved))
        _reprice_stays(hotel_strategies, city_legs, currency)

    # ── Geographic grounding ───────────────────────────────────────────────
    # The itinerary's geography rests entirely on the prompt: each leg's own
    # coordinates are stated in the route table and in DESTINATION IDENTITY,
    # and the model is told to confirm every place it names against that day's
    # coordinates with the google_search tool before writing it.
    #
    # A backstop used to run here — it sampled three generated place names,
    # geocoded them through Places, and regenerated once if two resolved
    # abroad. Removed 2026-09-14 by the team lead's decision that the model's
    # own checking is sufficient and the backend should not re-check it. The
    # flags are still written so the field keeps its shape for readers and so
    # a later change of mind is visible in the data rather than silent.
    geo_check: dict = {"status": "not_checked", "regenerated": False, "reasons": []}
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
        return tier_flight_cost(flight_strategies, travelers, tier)

    cheapest_flight_cost = _tier_flight_cost("minimum")

    # Google answered that nothing flies this route. With no airfare to hold,
    # the transit line must not keep the 30% of the budget it reserves when a
    # fare is merely unknown, or the total quietly includes a flight that
    # cannot be bought. It covers ground transport only, and says so.
    no_airfare = bool(
        isinstance(flight_strategies, dict)
        and flight_strategies.get("flights_available") is False
    )

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

    # How this itinerary divides its own food and activity spending. Read once
    # from the plan Gemini already returned, so every scenario splits the same
    # way — a Comfortable tab that reallocated the columns differently from the
    # Recommended one would be describing a different trip.
    food_share = food_share_of_plan(plan, travelers)
    if abs(food_share - _DEFAULT_FOOD_SHARE) > 0.01:
        logger.info(
            "Food/activities split taken from the itinerary: %.0f/%.0f (default %.0f/%.0f).",
            food_share * 100, (1 - food_share) * 100,
            _DEFAULT_FOOD_SHARE * 100, (1 - _DEFAULT_FOOD_SHARE) * 100,
        )

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
        elif no_airfare:
            # Ground transport only: inter-city trains and coaches, local
            # transfers. No seat on any aircraft is being budgeted for.
            transit_amt_ = round(tot_ * 0.12, 2)
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
        # Split the way the itinerary does, not 60/40 regardless — see
        # `food_share_of_plan`.
        food_amt_ = round(rem_for_food_act_ * food_share, 2)
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
        # ...unless the Recommended tier costs more than they entered.
        #
        # The headline used to be left exactly as typed while its four parts
        # were computed from the real fares and room rates, so a trip whose
        # recommended room outran the budget showed a split that did not add
        # up. Client report, 7-day Italy plan for three: "90% Stay - 64%
        # Transit - 3% Food - 0% Activities" against a total of INR 339,000 —
        # 157%, with Activities at zero and the card still calling the trip
        # feasible.
        #
        # Feasibility is measured against the *cheapest* room, which that
        # budget did cover; the card prices the *middle* one, which it did not.
        # The total now covers its own parts, and `overran` below says so
        # rather than leaving the traveller to add the bars up.
        rec_total = _scenario_total(tot, "recommended")
        overran = rec_total > tot + 1
        tot = rec_total
        budget_breakdown = _waterfall(
            tot,
            _tier_flight_cost("recommended"),
            _tier_stay_cost("recommended"),
        )

        # A Minimum tier on every plan, not only where there was 25% of
        # headroom below the budget. The card now opens on Minimum — the
        # client's "start at the minimum spend required" — and a plan whose
        # budget was merely *close* to the floor would otherwise have opened on
        # Recommended, which is the one case where starting at the cheapest
        # version matters most.
        budget_scenarios = {
            "minimum": _waterfall(
                _scenario_total(
                    tot * _SCENARIO_MULTIPLIERS["minimum"], "minimum",
                ),
                _tier_flight_cost("minimum"),
                _tier_stay_cost("minimum"),
            ),
        }
        budget_scenarios["recommended"] = budget_breakdown
        budget_scenarios["comfortable"] = _waterfall(
            _scenario_total(
                tot * _SCENARIO_MULTIPLIERS["comfortable"], "comfortable",
            ),
            _tier_flight_cost("comfortable"),
            _tier_stay_cost("comfortable"),
        )
        # The trip is feasible — at the cheapest room, which is what
        # `real_minimum_cost` prices and what the Minimum tab shows. It is the
        # Recommended tier the entered budget will not buy, and the banner has
        # to say so or the lifted total reads as the app ignoring the number
        # they typed.
        feasible = not overran
        if overran:
            budget_tightness = "insufficient"
        elif real_minimum_cost > 0 and (tot - real_minimum_cost) / real_minimum_cost < 0.2:
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

    at_star_floor = stay_priced_at_star_floor(hotel_strategies, city_legs)

    # The flat note stays computed for Recommended: app builds that predate
    # `budget_basis` open on that tab and read this, and handing them a note
    # written for a tier they never show is the bug this release is fixing.
    budget_notes = _budget_notes(
        rooms=_rooms_for(travelers),
        at_star_floor=at_star_floor,
        flight_basis=budget_flight_basis(flight_strategies),
        flight_tier=effective_flight_tier(flight_strategies),
        no_airfare=no_airfare,
    )

    # What every line of every tab was priced from — the client's "make each
    # category clickable to explain how the budget was arrived at".
    budget_basis_blocks = {
        tier_: budget_basis(
            tier=tier_,
            breakdown=bd_,
            flight_strategies=flight_strategies,
            hotel_strategies=hotel_strategies,
            city_legs=city_legs,
            travelers=travelers,
            days=g_days,
            currency=final_currency,
            food_share=food_share,
            no_airfare=no_airfare,
            at_star_floor=at_star_floor,
        )
        for tier_, bd_ in budget_scenarios.items()
    }

    verified_sources = _deduplicate_grounding_chunks(grounding_chunks)
    if verified_sources:
        logger.info(
            "Google Search grounding: %d verified sources attached to itinerary",
            len(verified_sources),
        )

    # What the card can actually offer, either side of what they typed.
    recommended_total = round(
        float(budget_scenarios.get("recommended", {}).get("total") or tot), 2,
    )
    minimum_total = round(
        float(budget_scenarios.get("minimum", {}).get("total") or 0), 2,
    )

    # The old banner named neither figure — "increase your budget to the
    # recommended amount" without saying what that amount was, or what the trip
    # costs at its cheapest — and it stayed red above a Minimum tab the
    # traveller could well afford, which is what the client was looking at when
    # he asked for the card to start at the minimum.
    if not feasible and minimum_total > 0 and user_budget + 1 < minimum_total:
        recommendation = (
            f"Even the cheapest version of this trip costs "
            f"{_money(final_currency, minimum_total)} — "
            f"{_money(final_currency, minimum_total - user_budget)} more than "
            "your budget. Shorten the trip, or raise the budget."
        )
    elif not feasible and minimum_total > 0:
        recommendation = (
            "Your budget doesn't stretch to the Recommended plan "
            f"({_money(final_currency, recommended_total)}). What you're "
            "seeing is the cheapest version of this trip — "
            f"{_money(final_currency, minimum_total)}."
        )
    elif not feasible:
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
        # Both figures the banner names, so the app never has to recompute one
        # of them out of the scenarios to write a sentence.
        "minimum_total": minimum_total,
        "recommended_total": recommended_total,
        "entered_budget": round(user_budget, 2),
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
        inter_city_flights=inter_city_flights,
        hotel_strategies=hotel_strategies,
        start_date=final_start_date,
        end_date=final_end_date,
        departure_city=departure_city or "",
        budget_breakdown=budget_breakdown,
        budget_advisory=(
            (
                str((flight_strategies or {}).get("unavailable_message") or "")
                + " The budget below covers ground transport only — no airfare is included."
            ).strip()
            if no_airfare else ""
        ),
        budget_notes=budget_notes,
        plan_advisory=plan_advisory,
        verified_sources=verified_sources,
        verdict=verdict,
        budget_scenarios=budget_scenarios,
        budget_basis=budget_basis_blocks,
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
        # Same expression the append below uses, read once so the hotel range
        # and the stored day number cannot disagree about which day this is.
        day_no = _as_int(d.get("day"), len(day_items) + 1)
        stay_range, stay_city = stay_basis_for_day(
            day_no, city_legs, hotel_range_by_leg, hotel_price_range,
        )

        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            act_type = normalise_activity_type(a.get("type"))
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
                "cost": str(a.get("cost") or ""),   # replaced below by the party total
            }

            # 3. Reconcile accommodation stops with a price range across the
            # hotel options found — never a single named property, so the
            # itinerary can't contradict (or pre-empt) the actual choices
            # shown on the Stays tab.
            if is_acc and has_hotel_data:
                has_accommodation = True
                display_cost, display_basis = stay_cost_row(stay_range, stay_city)

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
                act_dict["price_basis"] = display_basis
                act_dict["price_confidence"] = "Estimated"
            else:
                # What the card shows is what the party pays. The model gives
                # one adult's price; the multiplication and the wording are
                # ours, so the unit cannot drift between stops or plans.
                party_total, per_head = _party_cost(a, currency, travelers)
                act_dict["cost"] = party_total
                if per_head is not None and per_head > 0:
                    act_dict["cost_per_person"] = round(per_head, 2)

                price_source = _sourced(a.get("price_source"))
                price_basis = _sourced(a.get("price_basis"))
                if per_head is not None and per_head > 0 and travelers > 1:
                    split = f"{currency.upper()} {per_head:,.0f} each x {travelers} travellers"
                    price_basis = f"{split}. {price_basis}".strip() if price_basis else split
                price_confidence = _sourced(a.get("price_confidence"))
                booking_url = str(a.get("booking_url") or "").strip()
                # Nothing was priced, so nothing sourced it. Free stops came
                # back carrying "price_source": "N/A" — which the app prints
                # verbatim — and one free market visit was attributed to
                # "Vietnam Airlines".
                if _is_free(act_dict["cost"]):
                    price_source = price_basis = price_confidence = ""
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

            hours = usable_hours(a.get("hours"))
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

        # Guarantee Day 1 Check-in activity if not present. It goes after a
        # leading transport activity — the transfer in from the airport has to
        # happen before anyone can check in anywhere.
        if is_first_day and has_hotel_data and not has_accommodation:
            at = 1 if activities and activities[0].get("type") == "transport" else 0
            activities.insert(at, {
                "time": "14:00",
                "name": "Hotel Check-in",
                "tip": "Check in and settle into your accommodation.",
                "cost": stay_cost_row(stay_range, stay_city)[0],
                "price_source": "Google Hotels",
                "price_basis": stay_cost_row(stay_range, stay_city)[1],
                "price_confidence": "Estimated",
                "type": "accommodation",
            })

        day_items.append({
            "kind": "day",
            "day": day_no,
            "theme": str(d.get("theme") or ""),
            "activities": activities,
        })

    if not day_items:
        raise ValueError("Generated plan had no days")

    # Tips that say the same thing twice, and prices whose explanation the app
    # would otherwise discard. Both run over the finished days, so they see
    # every row the traveller will.
    repeats = _drop_repeated_tips(day_items)
    if repeats:
        logger.info("Cleared %d repeated tip(s).", repeats)
    sourced = _name_the_price_source(day_items)
    if sourced:
        logger.info("Named the price source on %d estimated stop(s).", sourced)

    # The flight into the country and the one home: link them where they are
    # read, and stop the row home looking free.
    linked = _apply_main_flight_details(day_items, flight_strategies)
    if linked:
        logger.info("Main flight details applied to %d itinerary row(s).", linked)

    # The fare is Google's, not the model's — see `_apply_inter_city_fares`.
    if inter_city_flights:
        fixed = _apply_inter_city_fares(day_items, inter_city_flights)
        logger.info(
            "Inter-city fares applied to %d of %d flown legs.",
            fixed, len(inter_city_flights),
        )

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
    city: str = "",
    latitude: float | None = None,
    longitude: float | None = None,
    country: str = "",
) -> dict:
    """Generate ONE replacement activity with restaurants."""
    prompt = _build_swap_prompt(
        city=city,
        latitude=latitude,
        longitude=longitude,
        country=country,
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

    act_type = normalise_activity_type(data.get("type"))
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
    city: str = "",
    latitude: float | None = None,
    longitude: float | None = None,
    country: str = "",
) -> str:
    avoid = ", ".join(n for n in existing_names if n) or "(none)"
    why = reason.strip() or "the traveler wants a different option"
    slot = time_slot or "this time slot"

    # Where the day actually is. Without it this asked for somewhere "near
    # {destination}" — near Sri Lanka, near India — and the replacement could
    # land anywhere in the country or on a namesake abroad. The main itinerary
    # prompt has pinned every place to its leg's coordinates since the
    # Saint-Petersburg-to-Florida report; a swapped stop had no such rule, and
    # it replaces a place on a day the traveller is already committed to.
    here = city or destination
    where = f'"{here}"'
    if country and country.lower() not in here.lower():
        where += f", {country}"

    anchor = ""
    if latitude is not None and longitude is not None:
        anchor = (
            f"\n- {here} is at {latitude:.4f}, {longitude:.4f}. The place you name MUST "
            f"be within about {_PLACE_ANCHOR_KM} km of that point and reachable from it "
            f"in the {slot} slot. A place of the same name somewhere else is the wrong "
            f"answer — if you cannot confirm it sits near those coordinates, name "
            f"something else you can."
        )

    return f"""A traveler is on a {mood} trip to {destination} (total budget {int(budget)} {currency}).

On Day {day_no} ("{theme}"), one stop needs replacing. That day is spent in {where}.
- Stop to replace: "{old_name}" (scheduled for {slot})
- Why replace it: {why}

These places are ALREADY in the trip - do NOT suggest any of them again:
{avoid}

Suggest exactly ONE different, real, well-known place or activity in or near {where} that:{anchor}
- fits the day's "{theme}" theme and the "{slot}" time slot,
- matches the "{mood}" travel style,
- keeps within the overall {int(budget)} {currency} budget,
- is NOT in the avoid-list above.

Return ONLY a JSON object with this exact shape (no markdown, no commentary):
{{ "time": "{slot}", "name": "Place or activity name", "tip": "Short practical tip under ~12 words", "cost_per_person": "ONE adult's price as a bare number in {currency}, digits only, 0 when free", "type": "transport|attraction|dining|exploration|accommodation|other", "restaurants": [] }}
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
    route_plan: "RoutePlan | None" = None,
    inter_city_flights: list[dict] | None = None,
    spend_room: float = 0.0,
) -> str:
    nights = days - 1 if days > 1 else 0
    # What the day plan may actually spend. The percentage split below is a
    # guess; this is the real one, from the fares and room rates already
    # searched. Stated only when there is something behind it — the estimate
    # paths reach here with nothing priced, and a fabricated ceiling would be
    # worse than the rule of thumb it replaced.
    spend_cap = int(spend_room) if spend_room > 0 else int(budget * 0.20)
    spend_rule = (
        f"4. Flights and rooms for this trip come to about "
        f"{int(budget - spend_room)} {currency} of the {int(budget)} {currency} total. "
        f"That leaves about {int(spend_room)} {currency} for food and activities across "
        f"{days} days for the whole group. The sum of every cost_per_person x "
        f"{travelers} MUST stay inside {int(spend_room)} {currency} - this is the "
        f"figure the traveller's budget screen will show, so a plan that exceeds it "
        f"is one they cannot afford."
        if spend_room > 0 else
        "4. Food & Dining (~10-15%) and Activities (~5-10%) share the remaining budget."
    )
    per_person = int(budget / travelers) if travelers > 0 else int(budget)
    legs = legs or (route_plan.legs if route_plan is not None else None)

    # Where the traveller actually lands and takes off, relative to the
    # first and last places they sleep. Only meaningful once a flight is
    # confirmed: without one there is nothing to transfer from.
    arrival_airport = route_plan.arrival if (route_plan is not None and confirmed_flight) else None
    departure_airport = route_plan.departure if (route_plan is not None and confirmed_flight) else None
    arrival_km = route_plan.arrival_km() if arrival_airport else None
    departure_km = route_plan.departure_km() if departure_airport else None
    first_leg = legs[0] if legs else None
    last_leg = legs[-1] if legs else None

    def _needs_transfer(airport, leg, km) -> bool:
        if not airport or not leg:
            return False
        if km is not None:
            return km > _SAME_PLACE_KM
        a = (airport.get("city") or "").strip().lower()
        return bool(a) and a != (leg.get("city") or "").strip().lower()

    arrival_transfer = _needs_transfer(arrival_airport, first_leg, arrival_km)
    departure_transfer = _needs_transfer(departure_airport, last_leg, departure_km)

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
        anchored = [l for l in (legs or []) if _leg_coords(l)]
        if anchored:
            # The route's own cities are the anchors that mean something. For a
            # country this is the only sane reading — its coordinates are a
            # centroid, and for Russia that is empty Siberia — but a region is
            # no different: one point plus a radius says nothing about which of
            # four cities a given day belongs to.
            anchors = "; ".join(
                f"{l['city']} ({l['latitude']:.2f}, {l['longitude']:.2f})" for l in anchored
            )
            coord_line = (
                f"- The route's cities are at: {anchors}. Everything you name must be "
                f"within roughly {_PLACE_ANCHOR_KM} km of the coordinates of the city "
                f"whose day it is.\n"
            )
        elif geo.has_coords:
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
- CHECK EVERY PLACE BEFORE YOU WRITE IT. Many place names exist in more than
  one country - Saint Petersburg, Moscow, Birmingham, Cambridge, Odessa,
  Naples and Athens all name somewhere in the United States as well. For each
  attraction, restaurant, market, station and neighbourhood you are about to
  name, confirm with the google_search tool that it is the one near that day's
  coordinates listed above, not a namesake elsewhere. If you cannot confirm it
  sits near those coordinates, do not write it - search for a real place that
  does.
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
    if legs and (len(legs) > 1 or arrival_transfer or departure_transfer):
        def _row(i: int, l: dict) -> str:
            span = (
                f"Day {l['start_day']}-{l['end_day']}" if l["start_day"] != l["end_day"]
                else f"Day {l['start_day']}"
            )
            # The coordinates ride on the row itself, so the anchor for a day
            # is on the same line as the day rather than in a block above it.
            where = (
                f" at {l['latitude']:.2f}, {l['longitude']:.2f}" if _leg_coords(l) else ""
            )
            row = f"  {span}: {l['city']}{where} (sleep in {l['city']})"
            hop = ""
            if i > 0:
                mode = l.get("arrive_by") or ""
                km = l.get("from_previous_km")
                if km is None:
                    d = _airport_leg_km(legs[i - 1], l)
                    km = int(round(d)) if d is not None else None
                bits = [f"by {mode}" if mode and mode != "none" else "", f"~{km:,} km" if km else ""]
                hop = ", ".join(b for b in bits if b)
                if hop:
                    row += f" — arrive from {legs[i - 1]['city']} {hop}"
            return row
        table = "\n".join(_row(i, l) for i, l in enumerate(legs))
        route_rules = f"""
CRITICAL - FIXED ROUTE (do not change it, do not add or drop a city):
{table}

- Every activity on a day must be in, or a day trip from, that day's city
  above, and within roughly {_PLACE_ANCHOR_KM} km of that city's coordinates.
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
    arrival_rules = ""
    departure_rules = ""

    # Legs the traveller flies between cities, priced live. Before this the
    # model wrote its own figure and credited it to a site nobody had asked:
    # two saved plans put the same one-hour Egyptian hop at 10,000 and 20,000.
    hop_rules = ""
    if inter_city_flights:
        lines = []
        for h in inter_city_flights:
            carriers = ", ".join(h.get("airlines") or []) or "the operating carrier"
            stops = _stop_label_text(int(h.get("stops") or 0))
            party = int(h.get("travelers") or 1)
            fare = (
                f"{h.get('currency','')} {h.get('price_per_traveler', 0):,.0f} per traveller"
                f" ({h.get('currency','')} {h.get('price_total', 0):,.0f} for {party})"
            )
            lines.append(
                f"- Day {h.get('day')}: {h.get('from_city')} ({h.get('from_code')}) -> "
                f"{h.get('to_city')} ({h.get('to_code')}) on {h.get('date')}, {carriers}, "
                f"{stops}, {h.get('duration') or 'duration n/a'}. Fare {fare}."
            )
        hop_rules = f"""
CRITICAL - CONFIRMED INTER-CITY FLIGHTS (live Google Flights; these are booked facts):
{chr(10).join(lines)}
- Each of those days MUST OPEN with a "transport" activity named
  "Flight: <from city> -> <to city>" carrying exactly the airline, the stop count,
  the duration and the fare above. Do not substitute another airline, another
  time, or another price, and do not write a train or a bus for these legs.
- Set "price_source": "Google Flights" and "price_confidence": "Fixed" on them.
"""


    # No flight and both ends in one country: the journey is by road or rail,
    # and it has to appear in the plan. Without this the itinerary opened with
    # sightseeing in the destination on Day 1 — a Kinniya traveller was shown a
    # Colombo temple at 09:00 while really sitting on a six-hour bus, and every
    # day after that was wrong by one.
    if (not confirmed_flight) and first_leg and _same_country(departure_country, geo):
        home = departure_city or "the traveller's home town"
        ground_rules = f"""
CRITICAL — GETTING THERE AND BACK (no flight on this route):
- {home} and {first_leg['city']} are in the same country and there is no flight. The traveller travels overland.
- Day 1 MUST OPEN with a "transport" activity named "Travel: {home} -> {first_leg['city']}" giving the realistic mode (bus, train, or private car), the departure time, the journey time, and the fare for {travelers} traveller(s) found via search.
- Day {days} MUST END with the journey home, named "Travel: {(last_leg or first_leg)['city']} -> {home}", with the same detail.
- Plan Day 1 and Day {days} AROUND those journeys. If the journey takes most of the day, schedule only what genuinely fits after it — do not fill a travel day with sightseeing.
- Never write an arrival by air, an airport transfer, or a flight number anywhere in this plan.
"""
        arrival_rules = ground_rules

    if confirmed_flight and (confirmed_flight.get("title") or confirmed_flight.get("name")):
        f_name = confirmed_flight.get("title") or confirmed_flight.get("name")
        f_route = confirmed_flight.get("route", "")
        f_currency = confirmed_flight.get("currency") or ""
        f_per_traveler = confirmed_flight.get("price_per_traveler")
        f_type = confirmed_flight.get("trip_type") or ("round_trip" if confirmed_flight.get("return_date") else "one_way")
        if f_per_traveler:
            trip_word = {"round_trip": "return", "open_jaw": "both legs"}.get(f_type, "one-way")
            f_price = f"{f_currency} {f_per_traveler:,.0f} per traveller ({trip_word})"
        else:
            f_price = confirmed_flight.get("estimated_price_range", "")

        def _leg_line(label: str, leg: dict | None, fallback_route: str, date: str) -> str:
            if not isinstance(leg, dict) or not (leg.get("origin") or fallback_route):
                return ""
            route = (
                f"{leg['origin']} → {leg['destination']}"
                if leg.get("origin") and leg.get("destination") else fallback_route
            )
            bits = [route]
            if leg.get("airlines"):
                bits.append(", ".join(leg["airlines"][:2]))
            if leg.get("departure_time"):
                bits.append(f"departs {leg['departure_time']}")
            if leg.get("arrival_time"):
                bits.append(f"arrives {leg['arrival_time']}")
            if leg.get("duration"):
                bits.append(leg["duration"])
            stops = leg.get("stops")
            if isinstance(stops, int):
                bits.append("non-stop" if stops == 0 else f"{stops} stop(s)")
            return f"- {label}{f' {date}' if date else ''}: " + ", ".join(bits) + "\n"

        out_line = _leg_line(
            "OUTBOUND", confirmed_flight.get("outbound") or {"origin": ""}, f_route,
            confirmed_flight.get("outbound_date") or "",
        ) or (f"- OUTBOUND: {f_route}\n" if f_route else "")
        ret_leg = confirmed_flight.get("return")
        ret_route = confirmed_flight.get("return_route") or ""
        if isinstance(ret_leg, dict) and ret_leg.get("origin"):
            ret_line = _leg_line("RETURN", ret_leg, ret_route, confirmed_flight.get("return_date") or "")
        elif f_type != "one_way":
            home = (departure_airport or {}).get("iata") or (ret_route.split("→")[0].strip() if ret_route else "")
            r_date = confirmed_flight.get("return_date") or ""
            ret_line = (
                f"- RETURN{f' {r_date}' if r_date else ''}: from {home or 'the arrival airport'} "
                f"back to the origin (exact flight chosen at booking)\n"
            )
        else:
            ret_line = ""
        shape = {
            "open_jaw": (
                f"open-jaw — land at {(arrival_airport or {}).get('iata') or '?'}, fly home from "
                f"{(departure_airport or {}).get('iata') or '?'}"
            ),
            "round_trip": f"round trip via {(arrival_airport or {}).get('iata') or (f_route.split('→')[-1].strip() if f_route else '?')}",
        }.get(f_type, "one way")
        flight_rules = f"""
CRITICAL — CONFIRMED FLIGHTS (live Google Flights; do not change the airports or dates):
- Option: "{f_name}" — trip type: {shape}
{out_line}{ret_line}- Fare: {f_price}
- Provider: Google Flights
"""

        if arrival_transfer:
            a_city = arrival_airport.get("city") or arrival_airport["iata"]
            a_time = ((confirmed_flight.get("outbound") or {}).get("arrival_time") or "").strip()
            km_txt = f", about {arrival_km:,.0f} km away" if arrival_km is not None else ""
            mode = (first_leg.get("arrive_by") or "").strip()
            mode_hint = f" (the route planner suggests: {mode})" if mode and mode != "none" else ""
            far = arrival_km is not None and arrival_km > _GATEWAY_MAX_KM
            arrival_rules = f"""
CRITICAL — ARRIVAL LOGISTICS:
- The traveller lands at {arrival_airport['iata']} ({a_city}){f' at {a_time}' if a_time else ''} on Day 1. The first night is in {first_leg['city']}{km_txt}.
- Day 1 MUST open with a "transport" activity named "Transfer: {a_city} airport → {first_leg['city']}" that states the mode{mode_hint}, a realistic duration, and the fare for {travelers} traveller(s) found via search.
- {"This is a long transfer: say so plainly and prefer a domestic flight or an overnight train over a road journey; if it needs most of Day 1, plan Day 1 around it." if far else "If the transfer takes more than ~6 hours by road, say so and prefer a domestic flight or overnight train."}
- Do not schedule sightseeing in {a_city} on Day 1 unless the transfer is under an hour.
"""
        if departure_transfer:
            d_city = departure_airport.get("city") or departure_airport["iata"]
            d_time = ((confirmed_flight.get("return") or {}).get("departure_time") or "").strip()
            km_txt = f", about {departure_km:,.0f} km away" if departure_km is not None else ""
            departure_rules = f"""
CRITICAL — DEPARTURE LOGISTICS:
- The flight home leaves from {departure_airport['iata']} ({d_city}){f' at {d_time}' if d_time else ''} on Day {days}. The last night is in {last_leg['city']}{km_txt}.
- Day {days} MUST END with a "transport" activity named "Transfer: {last_leg['city']} → {d_city} airport" that arrives at least 3 hours before departure, with mode, duration and fare for {travelers} traveller(s).
- If the flight leaves before 10:00, make that transfer the last activity of Day {max(days - 1, 1)} instead and note the early start.
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
    first_city = (first_leg or {}).get("city") or destination
    if (
        not confirmed_flight
        and departure_city
        and departure_city.strip().lower() != first_city.strip().lower()
    ):
        ground_transport_rules = f"""
CRITICAL — GETTING TO {first_city.upper()} (NO FLIGHT BOOKED FOR THIS TRIP):
- The traveler starts from "{departure_city}"{f', {departure_country}' if departure_country else ''} and has NOT booked a flight — assume they travel by bus, train, shared taxi, or car.
- Day 1 MUST open with a "transport" activity covering this journey, named something like "Travel from {departure_city} to {first_city}".
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
{hop_rules}{arrival_rules}
{departure_rules}
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
{spend_rule}

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
          "tip": "Short practical tip, under 12 words",
          "hours": "Real opening hours if attraction/dining/accommodation and confirmed via search; OMIT this key when not confirmed",
          "cost_per_person": "ONE adult's price as a bare number in {currency} - digits only, no symbol, no range, no words; 0 when free",
          "price_source": "Short source name actually found via search (site, publisher or official page) — a name, not a sentence",
          "price_basis": "Under 15 words: the anchor rate/figure found and any conversion applied",
          "price_confidence": "Fixed | Typical | Estimated",
          "type": "transport|attraction|dining|exploration|accommodation|other",
          "restaurants": [
            {{
              "name": "Restaurant Name",
              "cuisine": "Cuisine type (e.g. Seafood, Italian, Local)",
              "price_range": "{currency} 25 - 45 or $$",
              "rating": "4.6 ★",
              "tip": "Signature dish or booking tip, under 8 words"
            }}
          ]
        }}
      ]
    }}
  ]
}}

Rules for "type" field in each activity:
- "transport": Travel/transit between locations. cost_per_person = one adult fare.
- "attraction": Ticketed landmarks, museums, temples, parks. cost_per_person = one adult ticket.
- "dining": Meals (Breakfast, Lunch, Dinner). cost_per_person = one adult meal. MUST include "restaurants" array with up to 2 real top-rated dining suggestions with name, cuisine, price_range, rating, and tip. For non-dining activities, keep "restaurants": [].
- "exploration": Free self-guided walking, public markets, viewpoints. cost_per_person = 0.
- "accommodation": Hotel check-in/check-out. cost_per_person = 0 (room cost lives in budget_breakdown).
- "other": Any other activity.

General rules:
- Produce exactly {days} entries in "day_plans", each with 3-5 activities.
- "cost_per_person" is ALWAYS one adult share, never the group total: the party figure is worked out afterwards. {travelers} traveller(s) are going, so keep the sum of every cost_per_person x {travelers} inside {spend_cap} {currency}.
- Use real, recognisable places in and around {dest_anchor}.
- Be concise; tips under ~12 words, "price_basis" under 15 words. Every string is plain text — no markdown.
- Output MINIFIED JSON on a single line: no indentation, no line breaks between keys, no code fences, no commentary. The response is parsed by a machine; whitespace only costs.
"""


async def _call_gemini(
    prompt: str,
    api_key: str,
    max_tokens: int = 4096,
    thinking_budget=None,
    use_grounding: bool = False,
    response_schema: dict | None = None,
    operation: str = "odyssey_generate",
    timeout_s: float | None = None,
    models: tuple[str, ...] | None = None,
) -> tuple[str, list[dict]]:
    """Call Gemini with optional Google Search grounding.

    Returns (text, grounding_chunks) where grounding_chunks is a list of
    {"title": ..., "uri": ...} dicts extracted from the response's
    groundingMetadata. Empty list when grounding is disabled or absent.

    `response_schema` is a Gemini `responseSchema` (OpenAPI subset) for
    constrained JSON output. It rides on the JSON-mode path, so it is only
    honoured when grounding is off — the same restriction as responseMimeType.
    `operation` names the call in telemetry (`{operation}:{model}`), so the
    route planner's small call is not counted as an itinerary generation.
    `models` overrides the model chain — pass `_LITE_MODELS` for work that does
    not need Flash.
    """
    api_key = (api_key or "").strip().strip('"').strip("'")
    base_generation_config = {
        "temperature": 0.8,
        "maxOutputTokens": max_tokens,
    }
    # Google Gemini API strictly rejects responseMimeType: 'application/json' when tools/grounding are active (HTTP 400).
    if not use_grounding:
        base_generation_config["responseMimeType"] = "application/json"
        if response_schema:
            base_generation_config["responseSchema"] = response_schema
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    # Odyssey is a one-shot background job, so a single 503 would permanently
    # fail it. Rotate through the model chain twice (with a short backoff
    # between passes) so a model that's overloaded right now is bypassed for
    # one that's currently healthy.
    data = None
    attempts = list(models or _MODELS) * 2
    # Grounded calls may take longer due to live search; use extended timeout.
    # A caller producing a long answer (the day-by-day plan) passes its own.
    timeout = timeout_s if timeout_s else (90.0 if use_grounding else 45.0)
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
                # Model-aware, so the cheap chain and the pro fallback are not
                # billed at Flash's rate in the telemetry roll-up.
                family = "flash_lite" if "lite" in model else ("pro" if "pro" in model else "flash")
                sku = f"gemini_{family}_{'grounded' if use_grounding else 'generate'}"
                async with telemetry.track(
                    "gemini", f"{operation}:{model}",
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
        repaired = _close_truncated_json(raw[start:])
        if repaired is not None:
            return repaired
    raise ValueError("Gemini did not return a JSON object")


def _close_truncated_json(candidate: str) -> dict | None:
    """Recover the complete prefix of a response cut off mid-value.

    Walks the text once, tracking string state (escapes included) and the
    stack of open containers, and records every point outside a string where
    a complete value has just ended — a closing bracket, or the comma after a
    member — together with what was still open there. Cutting the text at
    such a point leaves a prefix made only of complete values, so appending
    the matching closers yields valid JSON. The latest cut that parses wins:
    the most of the plan that survived. The old approach of appending a
    handful of fixed suffixes only worked when the cut happened to land
    between two top-level values, which a plan truncated inside a day's
    restaurant list never does.
    """
    stack: list[str] = []
    cuts: list[tuple[int, str]] = []          # (prefix length, closers)
    in_str = esc = False
    for i, ch in enumerate(candidate):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            stack.append("}")
        elif ch == "[":
            stack.append("]")
        elif ch in "}]":
            if stack and stack[-1] == ch:
                stack.pop()
            cuts.append((i + 1, "".join(reversed(stack))))
        elif ch == ",":
            cuts.append((i, "".join(reversed(stack))))

    # Only the tail is worth trying: a cut further back than a few hundred
    # values discards most of the plan anyway.
    for length, closers in reversed(cuts[-600:]):
        try:
            parsed = json.loads(candidate[:length] + closers)
        except Exception:
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


def _plan_day_count(plan: dict) -> int:
    """How many usable days a parsed plan actually carries."""
    day_plans = plan.get("day_plans") if isinstance(plan, dict) else None
    if not isinstance(day_plans, list):
        return 0
    return sum(
        1 for d in day_plans
        if isinstance(d, dict) and (d.get("activities") or d.get("theme"))
    )


def _require_days(plan: dict, raw: str, expected: int = 0) -> None:
    """Reject a plan that is empty, or short of the trip that was asked for.

    A plan with three of six days is not a shorter trip, it is a truncated
    response: the dates, the flights and every budget line were computed for
    six. Shipping it puts a six-day header and a six-day budget over three days
    of itinerary, which is why this now raises rather than logging — the caller
    catches it and retries ungrounded, the same second chance an unparseable
    response already got.

    The raw response is logged in two short slices because this is the one
    failure we cannot reproduce after the fact: the model is non-deterministic
    and the text is not stored anywhere.
    """
    got = _plan_day_count(plan)
    want = max(int(expected or 0), 0)
    if got > 0 and (not want or got >= want):
        return
    body = (raw or "").strip()
    reason = (
        "response contained no day_plans" if got == 0
        else f"plan carried {got} of {want} days"
    )
    logger.warning(
        "%s (%d chars, keys=%s). Head: %s ... Tail: %s",
        reason.capitalize(),
        len(body),
        sorted(plan.keys())[:12] if isinstance(plan, dict) else type(plan).__name__,
        body[:300].replace("\n", " "),
        body[-300:].replace("\n", " "),
    )
    raise ValueError(reason)


def _short_plan_notice(plan: dict, days: int) -> str:
    """What to tell the traveller when the model wrote fewer days than asked.

    Returned rather than raised: the plan is kept. Empty string is the normal
    case, and the app draws nothing for it.
    """
    got = _plan_day_count(plan)
    want = max(int(days or 0), 0)
    if not got or not want or got >= want:
        return ""
    return (
        f"Only {got} of {want} days could be written for this trip. "
        f"The dates and budget still cover {want} days \u2014 tap Retry to "
        f"complete the plan."
    )


# The six activity types the app switches on. Anything else lands in its
# `other` bucket, which renders no button *and* no [Paid] badge, so an
# unrecognised word quietly costs the traveller the price chip. The model
# writes "activity", "sightseeing" or "experience" often enough to matter -
# twice in one 14-day Turkey plan - so the synonyms are mapped here rather
# than left to the client, where only some of them are known.
_ACTIVITY_TYPES = frozenset(
    {"transport", "attraction", "dining", "exploration", "accommodation", "other"}
)
_ACTIVITY_TYPE_SYNONYMS = {
    "transit": "transport", "travel": "transport", "flight": "transport",
    "train": "transport", "bus": "transport", "drive": "transport",
    "museum": "attraction", "landmark": "attraction", "ticket": "attraction",
    "sightseeing": "attraction", "activity": "attraction",
    "experience": "attraction", "tour": "attraction", "workshop": "attraction",
    "restaurant": "dining", "food": "dining", "meal": "dining",
    "cafe": "dining", "lunch": "dining", "dinner": "dining",
    "explore": "exploration", "walk": "exploration", "wander": "exploration",
    "leisure": "exploration", "relaxation": "exploration",
    "hotel": "accommodation", "check-in": "accommodation",
    "checkin": "accommodation", "stay": "accommodation",
}


def normalise_activity_type(raw) -> str:
    """One of the six types the app knows, or "" when there is nothing to say."""
    text = str(raw or "").strip().lower()
    if not text:
        return ""
    if text in _ACTIVITY_TYPES:
        return text
    return _ACTIVITY_TYPE_SYNONYMS.get(text, "other")


def nightly_ranges(
    hotel_strategies: dict | None, currency: str,
) -> tuple[str, dict[int, str]]:
    """The nightly rate range for the whole trip, and one per leg.

    `generate_hotel_strategies_for_legs` already searches each city on its own
    coordinates and dates and tags every result with `leg_index`. Collapsing
    all of them into a single min/max threw that grouping away: a live 14-day
    Japan plan quoted "INR 4,507 - 28,232" on all five cities, so the Hakone
    day advertised an Osaka floor 400 km away (real Hakone rooms start at
    14,932) and the Osaka day advertised a Hakone ceiling.

    The trip-wide string is still returned because a leg whose own search came
    back empty has to print something, and because a single-city plan has one
    leg - there the two are the same string, which is why this stayed invisible
    until the route planner made multi-city trips normal.
    """
    trip_wide = ""
    by_leg: dict[int, str] = {}
    if not (hotel_strategies and isinstance(hotel_strategies.get("strategies"), list)):
        return trip_wide, by_leg

    def _text(values: list[float]) -> str:
        lo, hi = min(values), max(values)
        return (
            f"{currency} {lo:,.0f}" if lo == hi
            else f"{currency} {lo:,.0f} - {hi:,.0f}"
        )

    rates: list[float] = []
    grouped: dict[int, list[float]] = {}
    for s in hotel_strategies["strategies"]:
        if not isinstance(s, dict):
            continue
        rate = _extract_lowest_price(s.get("price_per_night"))
        if rate <= 0:
            continue
        rates.append(rate)
        leg_i = s.get("leg_index")
        if isinstance(leg_i, int) and not isinstance(leg_i, bool):
            grouped.setdefault(leg_i, []).append(rate)
    if rates:
        trip_wide = _text(rates)
    return trip_wide, {i: _text(v) for i, v in grouped.items() if v}


def stay_basis_for_day(
    day_no: int,
    city_legs: list[dict] | None,
    ranges_by_leg: dict[int, str],
    trip_range: str,
) -> tuple[str, str]:
    """(nightly range, city) for the city a given day sleeps in.

    Falls back to the trip-wide range when the day sits outside every leg, or
    when that leg's own search returned nothing - a rate has to be printed
    either way, and a neighbouring city's is closer than none.
    """
    for i, leg in enumerate(city_legs or []):
        if not isinstance(leg, dict):
            continue
        start = _as_int(leg.get("start_day"), 0)
        end = _as_int(leg.get("end_day"), 0)
        if start <= day_no <= end:
            return ranges_by_leg.get(i) or trip_range, str(leg.get("city") or "")
    return trip_range, ""


def stay_cost_row(rng: str, city: str) -> tuple[str, str]:
    """The `cost` and `price_basis` one accommodation row prints.

    The basis names the city when one is known: "for this trip" was the exact
    wording that made a trip-wide range look deliberate rather than wrong.
    """
    if not rng:
        return "See Stays tab", "See the Stays tab for hotel pricing options."
    where = f"in {city}" if city else "found for this trip"
    return f"{rng} / night", f"Nightly rate range across hotel options {where}: {rng}."


def usable_hours(raw) -> str:
    """Opening hours, or "" when what came back is not hours.

    The prompt already says "leave hours as an empty string - never guess", and
    the model writes "Open until late", "Variable" or "Weekends only" anyway:
    22 times across three 14-day plans. The app draws the field verbatim under a
    clock icon, so filler reads to the traveller as a fact about the venue.
    Asking a third time would not help; containing a digit is the test, and
    every real answer has one - a time, a date, or "24 hours".

    Module-level so it can be tested against the strings the model actually
    produced, rather than only through a whole generation.
    """
    text = str(raw or "").strip()
    return text if re.search(r"\d", text) else ""


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
    text, _ = await _call_gemini(
        prompt, api_key, max_tokens=1024, thinking_budget=0, models=_LITE_MODELS,
    )
    data = _parse_json(text)
    return {
        "name": str(data.get("name") or "").strip(),
        "type": partner_type,
        "url": str(data.get("url") or "").strip(),
    }
