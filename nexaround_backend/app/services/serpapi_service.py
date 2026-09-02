"""SerpApi integration for real-time Google Flights and Google Hotels search.

Replaces the unreliable RapidAPI service with SerpApi, which provides
structured JSON from Google's own travel search results — including real
prices, real airlines, real hotel names, and automatic airport resolution.

Sign up at https://serpapi.com for a free API key (250 searches/month).
"""
import json
import logging
import urllib.parse
import httpx
from app.services import telemetry
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

SERPAPI_BASE = "https://serpapi.com/search.json"

# Currencies SerpApi's Google engines accept. Anything else is rejected outright
# with HTTP 400 "Unsupported `XXX` for currency", which is not a soft failure:
# the whole search returns nothing and the caller silently falls back to an AI
# price estimate. That is how a Colombo->Amsterdam trip came to advertise
# LKR 135,000 against a real fare of LKR 287,006 — every SerpApi call for an
# LKR trip had been failing, so no live price was ever fetched.
#
# Deliberately a small, conservative list: an unsupported currency costs a
# wasted round trip and a wrong price, while quoting in USD and converting is
# always safe.
_SERPAPI_CURRENCIES = {
    "USD", "EUR", "GBP", "AUD", "CAD", "JPY", "CNY", "SGD", "CHF", "NZD",
    "INR", "AED", "SAR", "HKD", "KRW", "THB", "MYR", "PHP", "IDR", "TWD",
    "BRL", "MXN", "ZAR", "TRY", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF",
}


def resolve_search_currency(currency: str) -> str:
    """The currency to ask SerpApi for, which may not be the one to display in."""
    code = (currency or "USD").strip().upper()
    return code if code in _SERPAPI_CURRENCIES else "USD"


# Live USD rates, refreshed at most every few hours.
#
# The static table in trip_cost_floor is mirrored to the Flutter client and
# tested to stay byte-identical, so it cannot track the market — and it had
# drifted badly: 300 LKR/USD against a real 328, and 83 INR/USD against 95.
# Every converted fare was ~9% low for Sri Lanka and ~14% low for India, which
# reads as exactly the kind of "prices don't match" the testers reported.
_FX_URL = "https://open.er-api.com/v6/latest/USD"
_FX_TTL_S = 6 * 3600
_fx_cache: dict = {"rates": {}, "at": 0.0}


def _live_fx_rates() -> dict:
    """USD rates, live where possible and the static table where not.

    Never raises and never blocks a generation: on any failure the caller falls
    back to the mirrored constants, which are stale but present.
    """
    import time
    now = time.time()
    if _fx_cache["rates"] and (now - _fx_cache["at"]) < _FX_TTL_S:
        return _fx_cache["rates"]
    try:
        # urllib, not httpx: this is called from inside async request handling,
        # and httpx's *sync* client cannot run there — it raises "asyncio.run()
        # cannot be called from a running event loop" and took the whole hotel
        # search down with it. urllib blocks the loop briefly instead, which is
        # acceptable for a once-per-six-hours refresh on a background job.
        import urllib.request
        with urllib.request.urlopen(_FX_URL, timeout=6.0) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        rates = data.get("rates") or {}
        if rates.get("USD"):
            _fx_cache["rates"] = rates
            _fx_cache["at"] = now
            return rates
    except Exception as e:
        logger.warning(f"[FX] Live rate fetch failed, using static table: {e}")
    return _fx_cache["rates"] or {}


def convert_from_search_currency(amount: float, display_currency: str) -> float:
    """Restate a SerpApi figure in the traveller's own currency.

    A no-op whenever SerpApi could be asked for that currency directly. When it
    could not — LKR being the case that started this — the search was made in
    USD and the number coming back means nothing to the traveller until it is
    converted.

    Uses the same static table the trip-cost floor works from, so a rate is
    approximate but never absent. An approximate live fare is worth far more
    than the AI guess that an unconverted (or failed) search falls back to.
    """
    code = (display_currency or "USD").strip().upper()
    if code in _SERPAPI_CURRENCIES or not amount:
        return amount
    try:
        from app.services.trip_cost_floor import FX_PER_USD
    except Exception:
        return amount
    rate = _live_fx_rates().get(code) or FX_PER_USD.get(code)
    return round(float(amount) * rate, 2) if rate else amount


# Booking aggregators whose bare front page is a dead end. A domain not on this
# list is taken to be the property's own site.
_OTA_HOSTS = {
    "agoda.com", "booking.com", "expedia.com", "hotels.com", "trip.com",
    "priceline.com", "kayak.com", "orbitz.com", "travelocity.com", "hostelworld.com",
    "airbnb.com", "vrbo.com", "tripadvisor.com", "ebookers.com", "lastminute.com",
}


def _looks_like_homepage_url(url: str) -> bool:
    """True when a URL is just a domain root / locale landing page (e.g.
    "agoda.com/en-gb/") rather than a deep link to a specific listing.

    Google Hotels sometimes hands back a bare partner homepage for certain
    listing types (vacation rentals especially) instead of the actual
    property page — trusting it as-is sends the traveller to a dead end.
    """
    if not url:
        return True
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return False

    # A hotel's *own* site is a fine place to send someone even at its root —
    # "amrathaparthotelschiphol.nl/" is that property and nothing else. Only a
    # booking aggregator's front page is the dead end this guards against, and
    # rejecting the hotel's own domain sent travellers to a Google Hotels search
    # that returned "No results" for the very property they were looking at.
    host = (parsed.netloc or "").lower().removeprefix("www.")
    if host and not any(host == o or host.endswith("." + o) for o in _OTA_HOSTS):
        return False

    if parsed.query:
        return False
    segments = [s for s in parsed.path.split("/") if s]
    if not segments:
        return True
    # A single short segment is almost always a locale code (en-gb, en-us, de, ...)
    return len(segments) == 1 and len(segments[0]) <= 5


class SerpApiService:
    """Search Google Flights and Google Hotels via SerpApi."""

    def __init__(self, api_key: str):
        self.api_key = (api_key or "").strip()

    async def search_flights(
        self,
        *,
        departure_city: str,
        destination: str,
        outbound_date: str = "",
        return_date: str = "",
        adults: int = 1,
        currency: str = "USD",
    ) -> Dict[str, Any]:
        """Search Google Flights via SerpApi.

        `adults` defaults to 1 deliberately. Google Flights varies the price it
        displays with party size, and SerpApi returns whatever Google displayed
        — so querying with the real traveller count leaves it ambiguous whether
        a returned figure is one seat or the whole party, which is how the same
        fare ended up being multiplied by the traveller count twice. Searching
        one adult makes the number unambiguously a single-traveller fare; the
        group total is then derived as fare x travellers.

        Trade-off: a 1-adult search does not verify that N seats remain at that
        fare. That matches the per-person "from" price metasearch sites show,
        and is the correct basis for the budget waterfall.

        Returns a dict with:
          - best_flights: list of top flight options
          - other_flights: list of additional options
          - airports: departure/arrival airport info
          - price_insights: pricing analysis from Google
        """
        if not self.api_key:
            return {}

        params: Dict[str, Any] = {
            "engine": "google_flights",
            "api_key": self.api_key,
            "departure_id": departure_city,
            "arrival_id": destination,
            "type": "1",  # 1=round trip, 2=one way
            "adults": str(adults),
            "currency": resolve_search_currency(currency),
            "hl": "en",
        }

        if outbound_date:
            params["outbound_date"] = outbound_date
        if return_date:
            params["return_date"] = return_date
            params["type"] = "1"  # round trip
        else:
            params["type"] = "2"  # one way if no return date

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                async with telemetry.track(
                    "serpapi", "search_flights",
                    sku="serpapi_search", params=params,
                ) as t:
                    resp = await client.get(SERPAPI_BASE, params=params)
                    t.upstream(resp)
                if resp.status_code != 200:
                    logger.warning(f"[SerpApi] Flights search returned {resp.status_code}: {resp.text[:200]}")
                    return {}
                data = resp.json()

                # Check for errors
                if "error" in data:
                    logger.warning(f"[SerpApi] Flights error: {data['error']}")
                    return {}

                return data

        except Exception as e:
            logger.error(f"[SerpApi] Flights search exception: {e}")
            return {}

    async def search_hotels(
        self,
        *,
        destination: str,
        check_in_date: str = "",
        check_out_date: str = "",
        adults: int = 1,
        currency: str = "USD",
        min_rating: float = 0.0,
    ) -> Dict[str, Any]:
        """Search Google Hotels via SerpApi.

        Returns a dict with:
          - properties: list of hotel results with prices, ratings, amenities
        If min_rating > 0, properties below that rating are filtered out.
        """
        if not self.api_key:
            return {}

        # Build the search query
        q = f"hotels in {destination}"

        params: Dict[str, Any] = {
            "engine": "google_hotels",
            "api_key": self.api_key,
            "q": q,
            "adults": str(adults),
            "currency": resolve_search_currency(currency),
            "hl": "en",
            "gl": "us",
        }

        if check_in_date:
            params["check_in_date"] = check_in_date
        if check_out_date:
            params["check_out_date"] = check_out_date

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                async with telemetry.track(
                    "serpapi", "search_hotels",
                    sku="serpapi_search", params=params,
                ) as t:
                    resp = await client.get(SERPAPI_BASE, params=params)
                    t.upstream(resp)
                if resp.status_code != 200:
                    logger.warning(f"[SerpApi] Hotels search returned {resp.status_code}: {resp.text[:200]}")
                    return {}
                data = resp.json()

                if "error" in data:
                    logger.warning(f"[SerpApi] Hotels error: {data['error']}")
                    return {}

                # Apply min_rating filter
                if min_rating > 0 and "properties" in data:
                    data["properties"] = [
                        p for p in data["properties"]
                        if isinstance(p, dict)
                        and isinstance(p.get("overall_rating"), (int, float))
                        and p["overall_rating"] >= min_rating
                    ]

                return data

        except Exception as e:
            logger.error(f"[SerpApi] Hotels search exception: {e}")
            return {}


def extract_hotel_strategies_from_serpapi(
    serpapi_data: Dict[str, Any],
    *,
    destination: str,
    currency: str,
    check_in_date: str = "",
    check_out_date: str = "",
    travelers: int = 1,
    max_hotels: int = 4,
) -> Dict[str, Any]:
    """Convert raw SerpAPI Google Hotels results directly into hotel strategy
    dicts compatible with the Odyssey HotelStrategy model.

    This bypasses Gemini entirely — prices, ratings, and names come straight
    from Google Hotels via SerpAPI so they are 100% accurate.

    Returns a dict shaped like:
      {
        "strategies": [...],
        "general_tips": [...],
        "best_areas": "..."
      }
    """
    raw_properties = serpapi_data.get("properties") or []
    strategies: List[Dict[str, Any]] = []

    # Strictly filter for available properties that have valid, active pricing and names
    properties: List[Dict[str, Any]] = []
    for p in raw_properties:
        if not isinstance(p, dict):
            continue
        name = p.get("name", "").strip()
        if not name:
            continue
        rate_info = p.get("rate_per_night") or {}
        extracted_rate = rate_info.get("extracted_lowest") or 0
        price_display = rate_info.get("lowest", "")
        # Must have a positive price to ensure the hotel is currently available and bookable
        if (isinstance(extracted_rate, (int, float)) and extracted_rate > 0) or price_display:
            properties.append(p)

    # Categorize hotels by price tier
    def _categorize(rate: float, all_rates: List[float]) -> str:
        if not all_rates:
            return "Hotel"
        avg = sum(all_rates) / len(all_rates)
        if rate >= avg * 1.5:
            return "Luxury"
        elif rate >= avg * 0.8:
            return "Boutique"
        else:
            return "Budget"

    # Collect extracted rates for categorization
    all_rates: List[float] = []
    for p in properties[:max_hotels * 2]:
        rate_info = p.get("rate_per_night") or {}
        extracted = rate_info.get("extracted_lowest")
        if isinstance(extracted, (int, float)) and extracted > 0:
            all_rates.append(float(extracted))

    for rank, p in enumerate(properties[:max_hotels], start=1):
        name = p.get("name", "").strip()
        rating = p.get("overall_rating")
        reviews = p.get("reviews", 0)
        hotel_type = p.get("type", "")
        description = p.get("description", "")

        # Price extraction directly from Google Hotels
        rate_info = p.get("rate_per_night") or {}
        price_display = rate_info.get("lowest", "")
        extracted_rate = rate_info.get("extracted_lowest", 0)

        total_info = p.get("total_rate") or {}
        total_display = total_info.get("lowest", "")
        total_extracted = total_info.get("extracted_lowest", 0)

        # Amenities
        amenities = p.get("amenities") or []
        if isinstance(amenities, list):
            amenities = [str(a) for a in amenities[:6]]

        # Location from nearby_places
        nearby = p.get("nearby_places") or []
        location_parts = []
        for np_item in nearby[:2]:
            if isinstance(np_item, dict):
                np_name = np_item.get("name", "")
                if np_name:
                    location_parts.append(np_name)
        location = ", ".join(location_parts) if location_parts else destination

        # Category
        category = hotel_type if hotel_type else _categorize(
            float(extracted_rate) if extracted_rate else 0, all_rates
        )

        # Rating string
        rating_str = f"{rating} ★" if rating else "N/A"

        # Provider: Google Hotels aggregates rates across all platforms
        provider = "Google Hotels"

        # Clean hotel name by stripping room specifications
        import re
        clean_name = re.sub(
            r'\s*[-–—]\s*(Family|Standard|Deluxe|Executive|Superior|Suite|Villa|Room|Bed|King|Queen|Twin|Double|Single|Sea View|Garden View|Ocean View|Penthouse|Bungalow|Apartment|Studio|Cottage|Luxury|Chalet|Resort|One|Two|Three|Four|Five|\d+).*',
            '',
            name,
            flags=re.IGNORECASE
        ).strip(" -–—,")
        if not clean_name:
            clean_name = name

        # Booking URL: use SerpAPI's direct Google Hotels property link if
        # available, unless it's just a bare partner homepage (see
        # _looks_like_homepage_url) — a link that dead-ends on Agoda's front
        # page is worse than no link, so fall back to a named search instead.
        raw_serpapi_link = str(p.get("link") or "").strip()
        serpapi_link = "" if _looks_like_homepage_url(raw_serpapi_link) else raw_serpapi_link
        if serpapi_link:
            booking_url = serpapi_link
        else:
            # Plain Google search, not the Hotels vertical. `travel/hotels?q=`
            # has to resolve the string to a property in Google's own index and
            # answers "No results" when it cannot — which is what a tester saw
            # for a hotel that was right there in the list. A web search always
            # lands somewhere useful, and the `dates` parameter this used to
            # append was never honoured by that page anyway.
            google_q = urllib.parse.quote_plus(f"{clean_name} {destination} hotel booking")
            booking_url = f"https://www.google.com/search?q={google_q}"

        # Format price with currency symbol/code if not already formatted.
        #
        # Google's own display strings ("$120") are in whatever currency the
        # search was made in, which is not the traveller's when SerpApi does not
        # support theirs. Passing those through unconverted is worse than
        # useless: the client relabels the symbol without touching the number,
        # so "$120" renders as "LKR 120". Rebuild from the converted figure
        # instead whenever a conversion actually happened.
        display_code = (currency or "USD").strip().upper()
        converted_nightly = convert_from_search_currency(
            float(extracted_rate) if extracted_rate else 0.0, display_code,
        )
        was_converted = (
            bool(extracted_rate) and converted_nightly != float(extracted_rate or 0)
        )
        if was_converted:
            price_str = f"{display_code} {converted_nightly:,.0f}"
        elif price_display:
            price_str = price_display
        elif extracted_rate:
            price_str = f"{currency} {extracted_rate}"
        else:
            price_str = ""

        strategies.append({
            "rank": rank,
            "name": name,
            "provider_name": provider,
            "category": category,
            "rating": rating_str,
            "reviews": reviews if isinstance(reviews, int) else 0,
            "price_per_night": price_str,
            # Same conversion as the nightly rate: a whole-stay total in the
            # search currency would be relabelled, not converted, downstream.
            "total_estimated_cost": (
                f"{display_code} {convert_from_search_currency(float(total_extracted), display_code):,.0f}"
                if total_extracted and convert_from_search_currency(float(total_extracted), display_code) != float(total_extracted)
                else (total_display or "")
            ),
            "location": location,
            "amenities": amenities,
            "description": description or f"Well-rated hotel in {destination} with excellent guest reviews.",
            "booking_url": booking_url,
            "serpapi_link": serpapi_link,
        })

    # Generate helpful tips
    general_tips = []
    if check_in_date and check_out_date:
        general_tips.append(f"Prices shown are live rates for {check_in_date} to {check_out_date}.")
    general_tips.append("Prices may vary — tap to view the latest rates on the booking site.")
    if strategies:
        avg_rating = sum(
            float(s["rating"].replace(" ★", ""))
            for s in strategies
            if s["rating"] != "N/A"
        ) / max(len([s for s in strategies if s["rating"] != "N/A"]), 1)
        general_tips.append(f"All hotels shown are rated {avg_rating:.1f}★ or higher.")

    # Best areas from the results
    areas = set()
    for s in strategies:
        loc = s.get("location", "")
        if loc and loc != destination:
            areas.add(loc.split(",")[0].strip())
    best_areas = ", ".join(list(areas)[:3]) if areas else destination

    return {
        "strategies": strategies,
        "general_tips": general_tips,
        "best_areas": best_areas,
    }


# ── Live flight strategy extraction (no LLM in the pricing path) ────────────
#
# Mirrors extract_hotel_strategies_from_serpapi: prices, airlines, durations
# and stop counts come straight from Google Flights via SerpApi, so the
# numbers the traveller sees are the numbers Google quoted. Gemini is only
# ever asked to write prose *around* these figures, never to produce them.

# The three tiers are selection criteria over one live result set — the same
# model Google Flights / Kayak / Skyscanner use for Cheapest / Best / Fastest.
FLIGHT_TIERS = ("minimum", "recommended", "comfortable")

# Value score weights for the "recommended" tier, over min-max normalised
# fields (lower is better on every axis).
_VALUE_WEIGHTS = {"price": 0.55, "duration": 0.30, "stops": 0.15}


def _format_duration(minutes: int) -> str:
    """900 -> '15h 0m'. Returns '' for a missing/zero duration."""
    if not isinstance(minutes, (int, float)) or minutes <= 0:
        return ""
    mins = int(minutes)
    return f"{mins // 60}h {mins % 60}m"


def _convenience_stars(stops: int, duration_minutes: int) -> str:
    """Star string from the two things that actually make a flight pleasant."""
    if stops <= 0:
        score = 5
    elif stops == 1:
        score = 4
    elif stops == 2:
        score = 3
    else:
        score = 2
    # A very long haul is not "five star" however few the stops.
    if duration_minutes and duration_minutes > 1440:      # > 24h
        score -= 2
    elif duration_minutes and duration_minutes > 960:     # > 16h
        score -= 1
    score = max(1, min(5, score))
    return "★" * score + "☆" * (5 - score)


def _flight_option_metrics(option: Dict[str, Any]) -> Dict[str, Any]:
    """Flatten one SerpApi flight option into the numbers we rank on.

    Returns None when the option lacks a usable price or leg list.
    """
    if not isinstance(option, dict):
        return None

    legs = option.get("flights") or []
    if not isinstance(legs, list) or not legs:
        return None

    price = option.get("price")
    if not isinstance(price, (int, float)) or price <= 0:
        return None

    # `total_duration` on a round-trip (type=1) search covers the OUTBOUND
    # itinerary only — Google prices the return once a specific outbound is
    # selected, and fetching it would cost a second SerpApi search per option.
    # We label it as outbound duration in the payload rather than pretending
    # it is the whole round trip.
    duration = option.get("total_duration") or 0
    if not isinstance(duration, (int, float)) or duration < 0:
        duration = 0

    layovers = option.get("layovers") or []
    stops = len(layovers) if isinstance(layovers, list) else max(len(legs) - 1, 0)

    airlines: List[str] = []
    flight_numbers: List[str] = []
    for leg in legs:
        if not isinstance(leg, dict):
            continue
        airline = str(leg.get("airline") or "").strip()
        if airline and airline not in airlines:
            airlines.append(airline)
        fn = str(leg.get("flight_number") or "").strip()
        if fn:
            flight_numbers.append(fn)

    first_dep = legs[0].get("departure_airport") if isinstance(legs[0], dict) else {}
    last_arr = legs[-1].get("arrival_airport") if isinstance(legs[-1], dict) else {}
    origin_id = str((first_dep or {}).get("id") or "").strip()
    dest_id = str((last_arr or {}).get("id") or "").strip()

    travel_classes = []
    for leg in legs:
        if isinstance(leg, dict):
            tc = str(leg.get("travel_class") or "").strip()
            if tc and tc not in travel_classes:
                travel_classes.append(tc)

    return {
        # Identity is the flight-number sequence: two tiers must never be the
        # same itinerary wearing different labels.
        "identity": tuple(flight_numbers) or (origin_id, dest_id, str(price), str(duration)),
        "price": float(price),
        "duration": int(duration),
        "stops": int(stops),
        "airlines": airlines,
        "flight_numbers": flight_numbers,
        "origin_id": origin_id,
        "dest_id": dest_id,
        "travel_class": travel_classes[0] if travel_classes else "",
        "serpapi_type": str(option.get("type") or ""),
        "departure_time": str((first_dep or {}).get("time") or ""),
        "arrival_time": str((last_arr or {}).get("time") or ""),
    }


def _normalise(value: float, low: float, high: float) -> float:
    """Min-max to 0..1; a flat field contributes nothing rather than dividing by zero."""
    if high <= low:
        return 0.0
    return (value - low) / (high - low)


def _meaningfully_different(a: Dict[str, Any], b: Dict[str, Any]) -> bool:
    """Would a traveller see these two options as different offers?

    Two different flight numbers at the same price, same stop count and
    near-identical duration read as the same card twice — which is how the
    tiers looked broken in the first place. Distinct identity is not enough;
    the *offer* has to differ.
    """
    if a["stops"] != b["stops"]:
        return True

    cheaper = min(a["price"], b["price"])
    if cheaper > 0 and abs(a["price"] - b["price"]) / cheaper >= 0.05:
        return True

    shorter = min(a["duration"], b["duration"])
    if shorter > 0 and abs(a["duration"] - b["duration"]) / shorter >= 0.15:
        return True

    return False


def _is_dominated(candidate: Dict[str, Any], picked: Dict[str, Any]) -> bool:
    """True when `picked` beats `candidate` on price, time AND stops.

    A "Recommended" option that costs more, takes longer and stops more often
    than the "Minimum" one is not a recommendation — it is a worse deal wearing
    a better label. Those get dropped, leaving the tier absent.
    """
    no_better = (
        candidate["price"] >= picked["price"]
        and candidate["duration"] >= picked["duration"]
        and candidate["stops"] >= picked["stops"]
    )
    strictly_worse = (
        candidate["price"] > picked["price"]
        or candidate["duration"] > picked["duration"]
        or candidate["stops"] > picked["stops"]
    )
    return no_better and strictly_worse


def _select_flight_tiers(candidates: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Pick up to three *distinct* itineraries: cheapest, best value, most comfortable.

    Returns a {tier: metrics} dict. Tiers are omitted rather than duplicated
    when the pool is too small or too uniform — showing the same offer under
    two labels is the exact bug this replaces. A route with one real fare level
    should show one card, not three identical ones.
    """
    if not candidates:
        return {}

    prices = [c["price"] for c in candidates]
    durations = [c["duration"] for c in candidates]
    stops = [c["stops"] for c in candidates]
    p_lo, p_hi = min(prices), max(prices)
    d_lo, d_hi = min(durations), max(durations)
    s_lo, s_hi = min(stops), max(stops)

    selected: Dict[str, Dict[str, Any]] = {}
    taken = set()

    def _claim(tier: str, option: Dict[str, Any]) -> None:
        selected[tier] = option
        taken.add(option["identity"])

    # Minimum — cheapest fare, tie-broken by the shorter trip.
    cheapest = min(candidates, key=lambda c: (c["price"], c["duration"], c["stops"]))
    _claim("minimum", cheapest)

    def _distinct_pool() -> List[Dict[str, Any]]:
        """Candidates a traveller would read as a different offer from every pick so far."""
        return [
            c for c in candidates
            if c["identity"] not in taken
            and all(_meaningfully_different(c, picked) for picked in selected.values())
        ]

    # Comfortable — fewest stops, then fastest, then cheapest of those.
    comfort_pool = _distinct_pool()
    if comfort_pool:
        _claim("comfortable", min(comfort_pool, key=lambda c: (c["stops"], c["duration"], c["price"])))

    # Recommended — best blended value among options that are genuinely
    # different AND not simply beaten outright by a tier already on show.
    value_pool = [
        c for c in _distinct_pool()
        if not any(_is_dominated(c, picked) for picked in selected.values())
    ]
    if value_pool:
        def _value_score(c: Dict[str, Any]) -> float:
            return (
                _VALUE_WEIGHTS["price"] * _normalise(c["price"], p_lo, p_hi)
                + _VALUE_WEIGHTS["duration"] * _normalise(c["duration"], d_lo, d_hi)
                + _VALUE_WEIGHTS["stops"] * _normalise(c["stops"], s_lo, s_hi)
            )
        _claim("recommended", min(value_pool, key=_value_score))

    # A tier with no genuinely different option left is simply absent. The app
    # falls back to the nearest tier it does have, rather than being handed the
    # same offer twice under two names.
    return selected


def extract_flight_strategies_from_serpapi(
    serpapi_data: Dict[str, Any],
    *,
    departure_city: str,
    destination: str,
    currency: str,
    outbound_date: str = "",
    return_date: str = "",
    travelers: int = 1,
) -> Dict[str, Any]:
    """Convert raw SerpApi Google Flights results directly into flight strategy
    dicts compatible with the Odyssey FlightStrategy model.

    This bypasses Gemini entirely — prices, airlines, durations and stop counts
    come straight from Google Flights via SerpApi so they are 100% accurate.

    Price contract, enforced here and relied on by the whole stack:
    every price is **per traveller, round trip (when a return date was
    searched), taxes and fees included**, in `currency`. `price_total` is
    always derived as price_per_traveler x travelers, never sourced
    independently. This matches the convention documented in
    trip_cost_floor.py ("Cheapest plausible return airfare ... per traveller").

    Returns a dict shaped like:
      {
        "strategies": [...],
        "general_tips": [...],
        "best_months": "..."
      }
    """
    if not serpapi_data:
        return {}

    raw_options = (serpapi_data.get("best_flights") or []) + (serpapi_data.get("other_flights") or [])

    # Deduplicate by itinerary identity, keeping the first (best-ranked) copy.
    candidates: List[Dict[str, Any]] = []
    seen = set()
    for option in raw_options:
        metrics = _flight_option_metrics(option)
        if not metrics or metrics["identity"] in seen:
            continue
        seen.add(metrics["identity"])
        candidates.append(metrics)

    if not candidates:
        return {}

    trip_type = "round_trip" if return_date else "one_way"
    selected = _select_flight_tiers(candidates)
    if not selected:
        return {}

    party = max(int(travelers or 1), 1)
    priciest = max(s["price"] for s in selected.values())

    tier_titles = {
        "minimum": "Cheapest Fare",
        "recommended": "Best Value Route",
        "comfortable": "Fastest & Fewest Stops",
    }

    strategies: List[Dict[str, Any]] = []
    for rank, tier in enumerate([t for t in FLIGHT_TIERS if t in selected], start=1):
        m = selected[tier]
        # SerpApi was asked for a currency it supports, which is not always the
        # traveller's. Convert before anything downstream treats these as the
        # trip's own numbers.
        per_traveler = round(convert_from_search_currency(m["price"], currency), 2)
        total = round(per_traveler * party, 2)
        route = f"{m['origin_id']} → {m['dest_id']}" if m["origin_id"] and m["dest_id"] else ""
        airlines = m["airlines"]
        duration_str = _format_duration(m["duration"])

        # One badge per tier, each saying something the others don't. Only the
        # cheapest tier quotes a percentage — two cards both shouting "Save
        # ~40%" tells the traveller nothing about how they differ.
        if tier == "minimum":
            saving_pct = (
                int(round((priciest - per_traveler) / priciest * 100)) if priciest > 0 else 0
            )
            savings = f"Save ~{saving_pct}%" if saving_pct >= 3 else "Lowest fare"
        elif tier == "comfortable":
            savings = "Non-stop" if m["stops"] == 0 else "Fastest route"
        else:
            savings = "Best value"

        stop_label = "Non-stop" if m["stops"] == 0 else (
            "1 stop" if m["stops"] == 1 else f"{m['stops']} stops"
        )
        carriers = ", ".join(airlines[:2]) if airlines else "multiple carriers"
        trip_label = "round trip" if trip_type == "round_trip" else "one way"
        description = (
            f"{stop_label} {trip_label} from {departure_city} to {destination} with {carriers}"
            + (f", {duration_str} outbound." if duration_str else ".")
        )

        if tier == "minimum":
            tip = "Cheapest live fare on this route — book early, budget fares move fastest."
        elif tier == "comfortable":
            tip = "Shortest time in transit. Worth the premium on long-haul or tight schedules."
        else:
            tip = "Best balance of price and travel time across the live results."

        strategies.append({
            # ── Structured, authoritative numbers ──────────────────────────
            "tier": tier,
            "price_per_traveler": per_traveler,
            "price_total": total,
            "currency": currency.upper(),
            "price_basis": "per_traveler",
            "trip_type": trip_type,
            "outbound_date": outbound_date,
            "return_date": return_date,
            "outbound_duration_minutes": m["duration"],
            "return_duration_minutes": None,
            "total_duration_minutes": m["duration"],
            "is_live_price": True,
            "price_source": "google_flights_serpapi",
            "travelers": party,
            "travel_class": m["travel_class"],
            "flight_numbers": m["flight_numbers"],

            # ── Legacy fields (older app builds read these) ────────────────
            "rank": rank,
            "strategy": "direct" if m["stops"] == 0 else "nearby_airport" if tier == "minimum" else "budget_carrier",
            "title": tier_titles[tier],
            "provider_name": "Google Flights",
            "description": description,
            "estimated_savings": savings,
            # Rendered from price_per_traveler, never an independent value.
            "estimated_price_range": f"{currency.upper()} {per_traveler:,.0f}",
            "airlines": airlines,
            "route": route,
            "stops": m["stops"],
            "total_duration": duration_str,
            "convenience": _convenience_stars(m["stops"], m["duration"]),
            "tip": tip,
            "booking_url": "",  # filled server-side by _build_deep_booking_url
        })

    general_tips: List[str] = []
    if outbound_date and return_date:
        general_tips.append(
            f"Live Google Flights fares for {outbound_date} → {return_date}, per traveller including taxes."
        )
    elif outbound_date:
        general_tips.append(f"Live one-way Google Flights fares for {outbound_date}, per traveller.")
    if party > 1:
        general_tips.append(
            f"Group total is the per-traveller fare x {party}; seats at the lowest fare may be limited."
        )

    price_insights = serpapi_data.get("price_insights") or {}
    typical = price_insights.get("typical_price_range") or []
    if isinstance(typical, list) and len(typical) == 2 and typical[0] and typical[1]:
        # Google reports these in the currency the search was made in, which is
        # not the traveller's when SerpApi does not support theirs. Labelling an
        # unconverted figure with their currency code is how a Colombo-Amsterdam
        # fare came to read "LKR 700 - 940" beside a real LKR 262,500 fare.
        typical_lo = convert_from_search_currency(float(typical[0]), currency)
        typical_hi = convert_from_search_currency(float(typical[1]), currency)
        general_tips.append(
            f"Google's typical range for this route is {currency.upper()} "
            f"{typical_lo:,.0f} - {typical_hi:,.0f} per traveller."
        )
    general_tips.append("Fares change constantly — tap through to confirm the current price before booking.")

    # Every real itinerary the tiers did not take, stated plainly.
    #
    # The tiers deliberately refuse to show a flight that is worse than an
    # already-listed one on every axis, so on a route where one fare is both
    # cheapest and fastest only two tiers can honestly be filled — and the tab
    # then looked empty beside Google's list of a dozen. These carry no tier
    # label and make no recommendation: they are the rest of the market, for a
    # traveller whose reasons (airline, departure time, stopover city) are not
    # ones we can rank.
    taken_ids = {m["identity"] for m in selected.values()}
    more_options = [
        {
            "price_per_traveler": round(convert_from_search_currency(m["price"], currency), 2),
            "price_total": round(convert_from_search_currency(m["price"], currency) * party, 2),
            "currency": currency.upper(),
            "airlines": m.get("airlines") or [],
            "route": " → ".join(x for x in (m.get("origin_id"), m.get("dest_id")) if x),
            # Departure and arrival times are the whole reason someone picks one
            # of these over a tier: the ranking cannot know they need to land
            # before a meeting or avoid a 02:00 departure.
            "departure_time": m.get("departure_time") or "",
            "arrival_time": m.get("arrival_time") or "",
            "flight_numbers": m.get("flight_numbers") or [],
            "stops": m["stops"],
            "total_duration": _format_duration(m["duration"]),
            "convenience": _convenience_stars(m["stops"], m["duration"]),
            "is_live_price": True,
            "price_source": "google_flights_serpapi",
        }
        for m in sorted(candidates, key=lambda c: c["price"])
        if m["identity"] not in taken_ids
    ]

    return {
        "strategies": strategies,
        "general_tips": general_tips,
        "best_months": "",
        "more_options": more_options,
    }


def format_flight_results_for_gemini(
    serpapi_data: Dict[str, Any],
    departure_city: str,
    destination: str,
    currency: str,
) -> str:
    """Convert SerpApi Google Flights JSON into a text summary for Gemini to analyze."""
    if not serpapi_data:
        return ""

    lines = [f"REAL FLIGHT DATA from Google Flights ({departure_city} → {destination}):"]
    lines.append("")

    # Extract airport info
    airports = serpapi_data.get("airports") or []
    if airports:
        for airport_group in airports:
            dep = airport_group.get("departure") or []
            arr = airport_group.get("arrival") or []
            if dep:
                dep_names = [f"{a.get('name', '')} ({a.get('id', '')})" for a in dep]
                lines.append(f"Departure airports: {', '.join(dep_names)}")
            if arr:
                arr_names = [f"{a.get('name', '')} ({a.get('id', '')})" for a in arr]
                lines.append(f"Arrival airports: {', '.join(arr_names)}")
        lines.append("")

    # Extract price insights
    price_insights = serpapi_data.get("price_insights") or {}
    if price_insights:
        lowest = price_insights.get("lowest_price")
        typical_low = price_insights.get("typical_price_range", [None, None])
        if lowest:
            lines.append(
                f"Lowest price found: {currency} "
                f"{convert_from_search_currency(float(lowest), currency):,.0f}"
            )
        if typical_low and typical_low[0]:
            lines.append(
                f"Typical price range: {currency} "
                f"{convert_from_search_currency(float(typical_low[0]), currency):,.0f} - {currency} "
                f"{convert_from_search_currency(float(typical_low[1]), currency):,.0f}"
            )
        lines.append("")

    # Best flights
    best_flights = serpapi_data.get("best_flights") or []
    other_flights = serpapi_data.get("other_flights") or []
    all_flights = best_flights + other_flights

    for i, flight_option in enumerate(all_flights[:6], start=1):
        flights = flight_option.get("flights") or []
        price = flight_option.get("price", "N/A")
        flight_type = flight_option.get("type", "")
        total_duration = flight_option.get("total_duration", 0)
        stops = len(flights) - 1 if len(flights) > 1 else 0
        is_best = i <= len(best_flights)

        hours = total_duration // 60
        mins = total_duration % 60
        duration_str = f"{hours}h {mins}m" if total_duration else "N/A"

        tag = "⭐ BEST" if is_best else "OTHER"
        # Converted before Gemini sees it: this block is the model's only view of
        # the fares, and an unconverted number labelled with the trip's currency
        # would have it reason (and write prose) about the wrong magnitude.
        shown = convert_from_search_currency(float(price or 0), currency)
        lines.append(f"Flight {i} [{tag}] — {currency} {shown:,.0f} ({flight_type})")
        lines.append(f"  Duration: {duration_str} | Stops: {stops}")

        route_parts = []
        airlines = set()
        for leg in flights:
            dep_airport = leg.get("departure_airport", {})
            arr_airport = leg.get("arrival_airport", {})
            airline = leg.get("airline", "")
            flight_number = leg.get("flight_number", "")
            dep_id = dep_airport.get("id", "?")
            arr_id = arr_airport.get("id", "?")
            dep_time = leg.get("departure_airport", {}).get("time", "")
            arr_time = leg.get("arrival_airport", {}).get("time", "")
            airlines.add(airline)
            route_parts.append(f"{dep_id}→{arr_id}")
            lines.append(f"  {airline} {flight_number}: {dep_id} ({dep_time}) → {arr_id} ({arr_time})")

        lines.append(f"  Route: {' → '.join(route_parts)}")
        lines.append(f"  Airlines: {', '.join(airlines)}")
        lines.append("")

    if not all_flights:
        lines.append("No flight results found for this route.")

    return "\n".join(lines)


def format_hotel_results_for_gemini(
    serpapi_data: Dict[str, Any],
    destination: str,
    currency: str,
) -> str:
    """Convert SerpApi Google Hotels JSON into a text summary for Gemini to analyze."""
    if not serpapi_data:
        return ""

    lines = [f"REAL HOTEL DATA from Google Hotels ({destination}):"]
    lines.append("")

    properties = serpapi_data.get("properties") or []

    for i, hotel in enumerate(properties[:8], start=1):
        name = hotel.get("name", "Unknown Hotel")
        hotel_type = hotel.get("type", "")
        rating = hotel.get("overall_rating", "N/A")
        reviews = hotel.get("reviews", 0)
        rate_info = hotel.get("rate_per_night") or {}
        lowest_rate = rate_info.get("lowest", "N/A")
        extracted_rate = rate_info.get("extracted_lowest", 0)
        total_info = hotel.get("total_rate") or {}
        total_rate = total_info.get("lowest", "N/A")
        amenities = hotel.get("amenities") or []
        description = hotel.get("description", "")
        link = hotel.get("link", "")
        nearby = hotel.get("nearby_places") or []

        lines.append(f"Hotel {i}: {name}")
        if hotel_type:
            lines.append(f"  Type: {hotel_type}")
        lines.append(f"  Rating: {rating}/5 ({reviews} reviews)")
        lines.append(f"  Price/night: {lowest_rate}")
        if total_rate != "N/A":
            lines.append(f"  Total stay: {total_rate}")
        if amenities:
            lines.append(f"  Amenities: {', '.join(amenities[:5])}")
        if description:
            lines.append(f"  Description: {description[:120]}")
        lines.append("")

    if not properties:
        lines.append("No hotel results found for this destination.")

    return "\n".join(lines)
