"""SerpApi integration for real-time Google Flights and Google Hotels search.

Replaces the unreliable RapidAPI service with SerpApi, which provides
structured JSON from Google's own travel search results — including real
prices, real airlines, real hotel names, and automatic airport resolution.

Sign up at https://serpapi.com for a free API key (250 searches/month).
"""
import json
import logging
import math
import re
import time
import urllib.parse
from datetime import datetime

import httpx
from app.services import place_cache_service, telemetry
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

SERPAPI_BASE = "https://serpapi.com/search.json"

# Responses are kept in Redis for a few hours. Every Odyssey retry and every
# geo-corrective regeneration used to pay for the same flight and hotel
# searches again; fares do move, but not within the window in which the same
# trip gets re-planned. Tests flip this off (see tests/conftest.py) because
# they call the same params over and over expecting a fresh HTTP call each time.
_CACHE_ENABLED = True
# A Google Flights search through SerpApi is usually quick — 2.1 s on average
# across 149 live searches — but the tail is long, and the slowest of those ran
# to exactly 10.0 s: our own ceiling, not theirs. Cutting one off wastes the
# search credit (they served it, we hung up) and drops the whole trip onto
# Gemini's estimated fares, which is what put "Cheapest Budget Flights" on an
# Italy plan while the account still had 105 searches left.
_HTTP_TIMEOUT_S = 25.0

# Google answering "there are none" is not the same as our failing to ask.
# No airline flies Pisa to Colombo, and no price exists at any figure — while
# a timeout or a spent quota says nothing about the world at all. Both used to
# come back as {} and both ended up showing the traveller an invented fare.
_NO_RESULTS_RE = re.compile(r"(has\s*n[o']t|have\s*n[o']t|has not|have not)\s+returned\s+any\s+results", re.I)
_NO_RESULTS = "no_results"


def no_results(data) -> bool:
    """True when the provider answered and the answer was "there are none"."""
    return isinstance(data, dict) and data.get("_serpapi_status") == _NO_RESULTS

FLIGHTS_CACHE_TTL_S = 6 * 60 * 60
HOTELS_CACHE_TTL_S = 6 * 60 * 60

# A hotel search that legitimately found nothing is worth remembering for an
# hour. Google does not grow new hotels in a small town between a generation
# and its retry, and the unfiltered rung of the class ladder used to be
# re-bought on every regeneration. Shorter than a real result's TTL because an
# empty answer is the one more likely to be wrong.
HOTELS_EMPTY_TTL_S = 60 * 60

# Once SerpApi says the plan is out of searches, every further call is a
# round trip that can only fail — 45% of one month's calls were exactly that.
# The guard is shared through Redis so all workers stop together, and expires
# on its own so a topped-up plan resumes without a deploy.
_QUOTA_GUARD_ENABLED = True
QUOTA_GUARD_TTL_S = 30 * 60
_QUOTA_GUARD_KEY = "serpapi:quota_exhausted"

# Set when this process last saw (or read) the guard, so a worker mid-Odyssey
# stops calling even if Redis is unavailable.
_quota_blocked_until: float = 0.0


async def _quota_exhausted() -> bool:
    """True while the account is known to be out of searches."""
    global _quota_blocked_until
    if not _QUOTA_GUARD_ENABLED:
        return False
    if time.time() < _quota_blocked_until:
        return True
    try:
        if await place_cache_service.get_raw(_QUOTA_GUARD_KEY):
            _quota_blocked_until = time.time() + QUOTA_GUARD_TTL_S
            return True
    except Exception:
        pass
    return False


async def _mark_quota_exhausted() -> None:
    global _quota_blocked_until
    if not _QUOTA_GUARD_ENABLED:
        return
    _quota_blocked_until = time.time() + QUOTA_GUARD_TTL_S
    logger.warning(
        "[SerpApi] Account is out of searches — pausing all SerpApi calls for %d minutes. "
        "Live flight and hotel prices fall back to AI estimates until the plan renews.",
        QUOTA_GUARD_TTL_S // 60,
    )
    try:
        await place_cache_service.set_raw(_QUOTA_GUARD_KEY, "1", ttl=QUOTA_GUARD_TTL_S)
    except Exception as e:
        logger.debug("[SerpApi] could not publish the quota guard: %s", e)


def _cache_key(params: Dict[str, Any]) -> str:
    """One key per distinct search, never including the API key."""
    clean = {k: v for k, v in params.items() if k != "api_key"}
    return f"serpapi:v1:{clean.get('engine', 'search')}:{telemetry._digest(clean)}"


async def _cache_get(key: str) -> Dict[str, Any] | None:
    if not _CACHE_ENABLED:
        return None
    try:
        raw = await place_cache_service.get_raw(key)
        if raw:
            data = json.loads(raw)
            if isinstance(data, dict):
                return data
    except Exception as e:
        logger.debug("[SerpApi] cache read failed: %s", e)
    return None


async def _cache_set(key: str, data: Dict[str, Any], ttl: int) -> None:
    if not _CACHE_ENABLED or ttl <= 0:
        return
    try:
        await place_cache_service.set_raw(key, json.dumps(data), ttl=ttl)
    except Exception as e:
        logger.debug("[SerpApi] cache write failed: %s", e)

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


# Google Hotels only classifies properties from 2 to 5 stars. Anything below
# that — and every unclassed guesthouse, hostel and apartment — has no class to
# filter on, so a floor outside this range means "do not filter".
_MIN_GOOGLE_HOTEL_CLASS = 2
_MAX_GOOGLE_HOTEL_CLASS = 5


def hotel_class_param(min_hotel_class: int) -> str:
    """SerpApi's `hotel_class` value for a star-class floor: 3 -> "3,4,5".

    Empty when the floor asks for nothing Google can filter on, which is the
    signal to send no `hotel_class` parameter at all rather than one Google
    would reject.
    """
    try:
        floor = int(min_hotel_class)
    except (TypeError, ValueError):
        return ""
    if floor < _MIN_GOOGLE_HOTEL_CLASS or floor > _MAX_GOOGLE_HOTEL_CLASS:
        return ""
    return ",".join(str(c) for c in range(floor, _MAX_GOOGLE_HOTEL_CLASS + 1))


def property_hotel_class(prop: Dict[str, Any]) -> int:
    """Star class of a Google Hotels property, or 0 when it has none.

    SerpApi gives the class twice: `extracted_hotel_class` as an integer and
    `hotel_class` as prose ("4-star hotel"). The integer is not always present,
    so fall back to reading it out of the string before concluding a property
    is unclassed — treating a 4-star hotel as unclassed would drop it from a
    filtered search.
    """
    if not isinstance(prop, dict):
        return 0
    extracted = prop.get("extracted_hotel_class")
    if isinstance(extracted, bool):
        return 0
    if isinstance(extracted, (int, float)):
        return int(extracted)
    if isinstance(extracted, str) and extracted.strip().isdigit():
        return int(extracted.strip())
    label = prop.get("hotel_class")
    if isinstance(label, (int, float)) and not isinstance(label, bool):
        return int(label)
    if isinstance(label, str):
        match = re.search(r"\d+", label)
        if match:
            return int(match.group())
    return 0


# Hotels are priced per room, so a party of three needs two rooms and pays
# twice the nightly rate. Defined here, beside the extraction that quotes the
# stay total, so the Stays tab and the budget allocation cannot drift apart:
# both derive rooms from this one rule. Showing a one-room total on a tab
# headed "2 rooms", against a budget line that had multiplied by two, is what
# made the same stay look like two different prices.
def _within_radius(
    properties: List[Dict[str, Any]],
    latitude: float,
    longitude: float,
    max_km: float,
    label: str = "",
) -> List[Dict[str, Any]]:
    """Keep only the hotels that are actually near the city.

    The last line of defence for the wrong-country bug. A property with no
    coordinates is KEPT — this drops what it can positively place somewhere
    else, never what it merely cannot check, the same rule the airport
    verification follows. If every result would be dropped the list is
    returned untouched instead: that means the coordinates we were handed are
    wrong, and a real hotel list beats an empty one.
    """
    kept: List[Dict[str, Any]] = []
    dropped: List[str] = []
    for p in properties:
        if not isinstance(p, dict):
            continue
        gps = p.get("gps_coordinates") or {}
        lat, lng = gps.get("latitude"), gps.get("longitude")
        if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
            kept.append(p)
            continue
        if _haversine_km(latitude, longitude, float(lat), float(lng)) <= max_km:
            kept.append(p)
        else:
            dropped.append(str(p.get("name") or "?"))

    if dropped and not kept:
        logger.warning(
            "[SerpApi] Every hotel for %r sits outside %.0f km of the coordinates given "
            "(%.4f, %.4f) — keeping them; the coordinates are the likelier error.",
            label, max_km, latitude, longitude,
        )
        return properties
    if dropped:
        logger.warning(
            "[SerpApi] Dropped %d hotel(s) more than %.0f km from %r: %s",
            len(dropped), max_km, label, ", ".join(dropped[:3]),
        )
    return kept


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in km. Local copy: this module must not import
    the geo resolver, which imports the Places client, which imports this."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def rooms_for(travelers: int) -> int:
    """Rooms a party needs, at one room per traveller.

    Two to a room was the rule until now, which halved the stay line of every
    multi-traveller trip: a 2-pax Egypt plan was budgeted one room at 38,368
    against the 76,736 two rooms cost. Sharing is the travellers' own decision
    and they can halve this themselves once they see it — a budget that has
    already assumed sharing cannot be un-assumed by anyone, and quotes a trip
    colleagues or a parent and adult child cannot actually book.
    """
    try:
        party = int(travelers or 1)
    except (TypeError, ValueError):
        party = 1
    return max(1, party)


def nights_between(check_in_date: str, check_out_date: str) -> int:
    """Nights spanned by a check-in/check-out pair, or 0 if undeterminable.

    0 means "the caller must supply the nights", never "a one-night stay":
    quoting one night for a whole trip is precisely the failure this replaces.
    """
    if not check_in_date or not check_out_date:
        return 0
    try:
        start = datetime.strptime(str(check_in_date).strip(), "%Y-%m-%d").date()
        end = datetime.strptime(str(check_out_date).strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return 0
    return max((end - start).days, 0)


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

    def __init__(self, api_key: str, *, cache_ttl_s: int | None = None):
        self.api_key = (api_key or "").strip()
        # None = module defaults per engine; 0 = no caching for this instance.
        self.cache_ttl_s = cache_ttl_s

    def _ttl(self, default: int) -> int:
        return default if self.cache_ttl_s is None else int(self.cache_ttl_s)

    async def search_flights(
        self,
        *,
        departure_city: str,
        destination: str,
        outbound_date: str = "",
        return_date: str = "",
        adults: int = 1,
        currency: str = "USD",
        one_way: bool = False,
        departure_token: str = "",
        _operation: str = "search_flights",
    ) -> Dict[str, Any]:
        """Search Google Flights via SerpApi.

        `one_way=True` searches a single leg regardless of `return_date` —
        the shape an open-jaw trip needs (fly into one city, home from
        another), priced as two one-way tickets.

        `departure_token` is the token Google attaches to each outbound
        itinerary of a round-trip search; passing it back with the same
        parameters returns the RETURN itineraries for that outbound, each
        priced as the whole round trip. That is the only way to see the return
        leg — a round-trip response on its own contains outbound options only.

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
        if return_date and not one_way:
            params["return_date"] = return_date
            params["type"] = "1"  # round trip
        else:
            params["type"] = "2"  # one way if no return date
        if departure_token:
            params["departure_token"] = departure_token

        key = _cache_key(params)
        try:
            # Cache first, quota guard second: a hit costs nothing and stays
            # useful while the account is empty.
            cached = await _cache_get(key)
            if cached is None and await _quota_exhausted():
                return {}
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_S) as client:
                async with telemetry.track(
                    "serpapi", _operation,
                    sku="serpapi_search", params=params, cache_key=key,
                ) as t:
                    if cached is not None:
                        t.hit("redis")
                        return cached
                    resp = await client.get(SERPAPI_BASE, params=params)
                    t.upstream(resp)
                if resp.status_code == 429:
                    await _mark_quota_exhausted()
                    return {}
                if resp.status_code != 200:
                    logger.warning(f"[SerpApi] Flights search returned {resp.status_code}: {resp.text[:200]}")
                    return {}
                data = resp.json()

                # Check for errors
                if "error" in data:
                    message = str(data["error"])
                    if _NO_RESULTS_RE.search(message):
                        # A fact about the route, not a failure of ours.
                        logger.info(
                            "[SerpApi] Google has no flights %s -> %s on %s.",
                            params.get("departure_id"), params.get("arrival_id"),
                            params.get("outbound_date"),
                        )
                        return {"_serpapi_status": _NO_RESULTS}
                    logger.warning(f"[SerpApi] Flights error: {message}")
                    return {}

                # Only a response with options is worth keeping: an empty one
                # may be a transient miss, and caching it would pin the miss.
                if data.get("best_flights") or data.get("other_flights"):
                    await _cache_set(key, data, self._ttl(FLIGHTS_CACHE_TTL_S))
                return data

        except Exception as e:
            logger.error("[SerpApi] Flights search failed: %s%s", type(e).__name__,
                         f": {e}" if str(e) else " (no detail — usually a timeout)")
            return {}

    async def search_flights_return(
        self,
        *,
        departure_city: str,
        destination: str,
        outbound_date: str,
        return_date: str,
        departure_token: str,
        adults: int = 1,
        currency: str = "USD",
    ) -> Dict[str, Any]:
        """The return itineraries for one outbound of a round-trip search.

        Same parameters as the search that produced `departure_token`, plus
        the token. Each option in the response is a return flight whose
        `price` is the round trip as a whole with that outbound.
        """
        if not departure_token:
            return {}
        return await self.search_flights(
            departure_city=departure_city,
            destination=destination,
            outbound_date=outbound_date,
            return_date=return_date,
            adults=adults,
            currency=currency,
            departure_token=departure_token,
            _operation="search_flights_return",
        )

    async def search_hotels(
        self,
        *,
        destination: str,
        check_in_date: str = "",
        check_out_date: str = "",
        adults: int = 1,
        currency: str = "USD",
        min_rating: float = 0.0,
        min_hotel_class: int = 0,
        sort_by: int | None = None,
        country: str = "",
        country_code: str = "",
        latitude: float | None = None,
        longitude: float | None = None,
        max_km: float | None = None,
    ) -> Dict[str, Any]:
        """Search Google Hotels via SerpApi.

        `country`, `country_code`, `latitude`/`longitude` and `max_km` all
        answer one question — WHICH Saint Petersburg? A tester's 14-day Russia
        trip came back with correct Moscow hotels and two other cities' hotels
        in the United States, because the query was the bare city name and `gl`
        was pinned to "us": Google localised "hotels in Saint Petersburg" for
        an American searcher and returned Florida. Three layers now, cheapest
        first, none of them an extra request:

          country / country_code  name the country in the query and search as
                                  a local of it. Sourced from the
                                  Places-verified destination, so this is the
                                  authoritative layer.
          latitude / longitude    bias to the city's own coordinates, which
                                  also pulls results toward the centre rather
                                  than the outskirts.
          max_km                  drop whatever still comes back from the
                                  wrong place. Free, and the only layer that
                                  cannot itself be fooled by a bad guess.

        Returns a dict with:
          - properties: list of hotel results with prices, ratings, amenities

        Two different quality filters, which are not the same thing and were
        conflated before:

        `min_hotel_class` is the property's **star class** (3 = a 3-star hotel)
        and is what "only 3-star and above" means. It is sent to Google as the
        native `hotel_class` request parameter — a comma-separated list of the
        classes to keep, e.g. `3,4,5` — so the filtering happens in Google's
        index rather than over one page of already-returned results. Google
        supports classes 2-5 only, and the parameter excludes vacation rentals
        outright (they have no star class to filter on).

        `min_rating` is the **guest review score** out of 5 (4.0 = "rated 4.0
        or better by guests"), applied here over the returned page. A hostel
        can be rated 4.8 by guests and still be an unclassed property, which is
        why a 4.0 review floor never delivered the 3-star-and-above hotels it
        was standing in for.

        `sort_by` is SerpApi's Google Hotels sort code: 3 = lowest price,
        8 = highest rating, 13 = most reviewed. Without it, Google's default
        "relevance" order applies, which skews toward prominent (often
        pricier) chains — the reason a quality floor alone still surfaced
        the same well-known hotels first even once budget travelers were
        allowed into the results.
        """
        if not self.api_key:
            return {}

        # The country goes in the query text, not only in a parameter:
        # "hotels in Saint Petersburg, Russia" is unambiguous before Google
        # localises anything.
        place = (destination or "").strip()
        country_name = (country or "").strip()
        if country_name and country_name.lower() not in place.lower():
            place = f"{place}, {country_name}"
        q = f"hotels in {place}"

        params: Dict[str, Any] = {
            "engine": "google_hotels",
            "api_key": self.api_key,
            "q": q,
            "adults": str(adults),
            "currency": resolve_search_currency(currency),
            "hl": "en",
            # Search as a local of the destination. Pinned to "us" before,
            # which is exactly what sent a Russian trip to Florida.
            "gl": (country_code or "us").strip().lower()[:2],
        }
        if latitude is not None and longitude is not None:
            # Zoom 12 is roughly one city: tighter re-centres on a district,
            # looser lets the neighbouring town back in.
            params["ll"] = f"@{latitude:.4f},{longitude:.4f},12z"

        if check_in_date:
            params["check_in_date"] = check_in_date
        if check_out_date:
            params["check_out_date"] = check_out_date
        if sort_by:
            params["sort_by"] = str(sort_by)
        # Google only knows classes 2-5. A floor of 3 becomes "3,4,5"; a floor
        # of 0 or 1 is no filter at all rather than "1,2,3,4,5", which Google
        # rejects.
        class_filter = hotel_class_param(min_hotel_class)
        if class_filter:
            params["hotel_class"] = class_filter

        key = _cache_key(params)
        try:
            cached = await _cache_get(key)
            if cached is None and await _quota_exhausted():
                return {}
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_S) as client:
                async with telemetry.track(
                    "serpapi", "search_hotels",
                    sku="serpapi_search", params=params, cache_key=key,
                ) as t:
                    if cached is not None:
                        t.hit("redis")
                        data = cached
                        resp = None
                    else:
                        resp = await client.get(SERPAPI_BASE, params=params)
                        t.upstream(resp)
                if resp is not None:
                    if resp.status_code == 429:
                        await _mark_quota_exhausted()
                        return {}
                    if resp.status_code != 200:
                        logger.warning(f"[SerpApi] Hotels search returned {resp.status_code}: {resp.text[:200]}")
                        return {}
                    data = resp.json()

                    if "error" in data:
                        logger.warning(f"[SerpApi] Hotels error: {data['error']}")
                        return {}

                    # Cached before the rating/class post-filters below, which
                    # are cheap and depend on arguments that are not in the key.
                    # An empty answer is cached too, for less time: a town with
                    # no classed hotel has none on the retry either, and the
                    # class ladder used to re-buy that emptiness every run.
                    if data.get("properties"):
                        await _cache_set(key, data, self._ttl(HOTELS_CACHE_TTL_S))
                    else:
                        await _cache_set(key, {"properties": []}, self._ttl(HOTELS_EMPTY_TTL_S))

                # ── Layer 3: is it even in the right place? ──────────────
                # Applied to cached results too, on purpose: a result cached
                # before this guard existed would otherwise keep serving
                # Florida hotels for a Russian city until the TTL expired.
                if max_km and latitude is not None and longitude is not None:
                    data["properties"] = _within_radius(
                        data.get("properties") or [], latitude, longitude, max_km, destination,
                    )

                # Apply min_rating filter
                if min_rating > 0 and "properties" in data:
                    data["properties"] = [
                        p for p in data["properties"]
                        if isinstance(p, dict)
                        and isinstance(p.get("overall_rating"), (int, float))
                        and p["overall_rating"] >= min_rating
                    ]

                # Verify the star class Google actually returned rather than
                # trusting the request parameter. `hotel_class` is a filter
                # Google applies to its own index, and a property that carries
                # no class at all (a guesthouse, an apartment) has been seen to
                # slip through it — which would put exactly the properties this
                # filter exists to exclude back in front of the traveller.
                if class_filter and "properties" in data:
                    kept = [
                        p for p in data["properties"]
                        if isinstance(p, dict)
                        and property_hotel_class(p) >= min_hotel_class
                    ]
                    dropped = len(data["properties"]) - len(kept)
                    if dropped:
                        logger.info(
                            "[SerpApi] Dropped %d of %d properties below %d-star class",
                            dropped, len(data["properties"]), min_hotel_class,
                        )
                    data["properties"] = kept

                return data

        except Exception as e:
            logger.error("[SerpApi] Hotels search failed: %s%s", type(e).__name__,
                         f": {e}" if str(e) else " (no detail — usually a timeout)")
            return {}


def extract_hotel_strategies_from_serpapi(
    serpapi_data: Dict[str, Any],
    *,
    destination: str,
    currency: str,
    check_in_date: str = "",
    check_out_date: str = "",
    travelers: int = 1,
    nights: int = 0,
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

    # The stay is quoted for the party, not for one room: `travelers` used to be
    # accepted here and never read, so a party of three saw a one-room total on
    # the Stays tab while the budget allocation had already multiplied the same
    # nightly rate by two rooms. Same nights, same rooms, same arithmetic as
    # `_required_stay_cost` in the odyssey service — that is what makes the two
    # screens agree.
    rooms = rooms_for(travelers)
    # The trip's own planned nights win over the dates when both are known: the
    # budget's stay line is built from the leg's nights, so deriving a
    # different number here from a date window that happens to disagree would
    # reintroduce the very mismatch this shares. Dates are the fallback for
    # callers that pass no nights.
    nights = int(nights or 0) or nights_between(check_in_date, check_out_date)

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

        # Whole-stay total = nightly x nights x rooms.
        #
        # Google's own `total_rate` is one room for the window it was searched
        # with, and is missing entirely when the search carried no dates — in
        # which case the nightly rate was being shown as if it were the trip
        # total. Deriving the total instead means the figure always states the
        # same thing, is defined for every property, and matches the stay line
        # in the budget allocation, which is built from this same arithmetic on
        # the cheapest hotel of each leg.
        stay_total_str = ""
        if converted_nightly > 0 and nights > 0:
            stay_total_str = f"{display_code} {converted_nightly * nights * rooms:,.0f}"
        elif total_extracted:
            # No usable nightly rate: fall back to Google's own stay total,
            # scaled to the rooms the party needs.
            converted_total = convert_from_search_currency(
                float(total_extracted), display_code,
            )
            stay_total_str = f"{display_code} {converted_total * rooms:,.0f}"
        elif total_display and rooms == 1:
            # Only safe to pass through verbatim for a single room — for more,
            # an unparsed string cannot be multiplied and would understate.
            stay_total_str = total_display

        strategies.append({
            "rank": rank,
            "name": name,
            "provider_name": provider,
            "category": category,
            "rating": rating_str,
            "reviews": reviews if isinstance(reviews, int) else 0,
            "price_per_night": price_str,
            "total_estimated_cost": stay_total_str,
            "nights": nights,
            "rooms": rooms,
            # Star class, so the app can show what was actually filtered on and
            # a reviewer can tell a 3-star hotel from a 4.5-guest-rated hostel.
            "hotel_class": property_hotel_class(p),
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
        # State the star class actually met, not the average guest score. The
        # old line read "All hotels shown are rated 4.3★ or higher" off the
        # *mean* review score, so it was both a different measure from the one
        # being filtered on and arithmetically wrong — an average is not a
        # floor, and half the list sat below it.
        classes = [int(s.get("hotel_class") or 0) for s in strategies]
        classed = [c for c in classes if c > 0]
        if classed and len(classed) == len(classes):
            general_tips.append(
                f"Every hotel here is {min(classed)}-star class or above."
            )
        if nights > 0:
            room_word = "room" if rooms == 1 else "rooms"
            general_tips.append(
                f"Est. Total covers {nights} {'night' if nights == 1 else 'nights'} "
                f"x {rooms} {room_word} for {max(int(travelers or 1), 1)} "
                f"{'traveller' if max(int(travelers or 1), 1) == 1 else 'travellers'}."
            )

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

# A fare far above the cheapest on the route is not a tier, it is a different
# trip. Odyssey plans to the traveller's budget, so a fare that breaks it is
# never worth a card: live results have offered a 5x fare whose whole merit was
# arriving 95 minutes sooner.
_FARE_CEILING = 2.0

# Two itineraries landing this close together are the same journey, and the
# cheaper one wins. Deliberately tighter than `_meaningfully_different`'s 15%:
# that asks "are these different offers?", this asks "is the extra money buying
# real time?" — and 10 minutes off a 34-hour trip is not.
_NEAR_TIE_DURATION = 0.05


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

    segments: List[Dict[str, Any]] = []
    for leg in legs:
        if not isinstance(leg, dict):
            continue
        dep = leg.get("departure_airport") or {}
        arr = leg.get("arrival_airport") or {}
        segments.append({
            "from": str((dep or {}).get("id") or ""),
            "departure_time": str((dep or {}).get("time") or ""),
            "to": str((arr or {}).get("id") or ""),
            "arrival_time": str((arr or {}).get("time") or ""),
            "airline": str(leg.get("airline") or ""),
            "flight_number": str(leg.get("flight_number") or ""),
            "duration_minutes": int(leg.get("duration") or 0) if isinstance(leg.get("duration"), (int, float)) else 0,
        })

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
        "segments": segments,
        # Round-trip searches attach a token to each outbound; sending it back
        # returns that outbound's return itineraries. Never stored on a
        # strategy — it is a search handle, not a fact about the flight.
        "departure_token": str(option.get("departure_token") or ""),
        "booking_token": str(option.get("booking_token") or ""),
    }


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


def _price_time_frontier(candidates: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Fares that no other fare beats on both money and time.

    Stops are reported to the traveller, never ranked. A 2-stop 46-hour routing
    is not "more comfortable" than a 3-stop 25-hour one, and ranking by stop
    count is how a fare costing 26,000 more for 20 extra hours in transit came
    to be labelled "Fastest & Fewest Stops" — time in transit already carries
    the cost of a connection.
    """
    frontier: List[Dict[str, Any]] = []
    for c in candidates:
        beaten = any(
            o is not c
            and o["price"] <= c["price"]
            and o["duration"] <= c["duration"]
            and (
                o["price"] < c["price"]
                or o["duration"] < c["duration"]
                # Same fare and same time: fewer connections wins outright, and
                # the other is not a choice. Stops break an exact tie and only
                # an exact tie — ranking by them is what this replaces.
                or o["stops"] < c["stops"]
            )
            for o in candidates
        )
        if not beaten:
            frontier.append(c)
    return frontier


def _select_flight_tiers(candidates: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Pick up to three real fares, cheapest first.

    Every card costs more than the one above it and gets there sooner. That is
    the only promise the Flights tab makes, and it is the one the numbers can
    always keep: a tier name is now a price rank, so it cannot contradict the
    fare it labels.

    What this replaces: each tier was claimed in turn by its own criterion,
    "comfortable" before "recommended". Comfortable took the best fare on the
    route and Recommended picked from the remainder, so a live
    Colombo->Edinburgh search labelled a 183,456 / 3-stop itinerary "Best
    Value" with a 139,016 / 2-stop one on the card beneath it — and the budget,
    which prices itself off the Recommended fare, inherited the wrong number.
    Selecting over the price/time frontier makes that arrangement
    unrepresentable rather than merely unlikely.

    Fewer than three fares is a normal outcome, not a degraded one: most live
    routes carry two genuinely different offers, and 30 of the 55 stored
    Odysseys with live prices already show two. The app falls back to the
    nearest tier it has rather than printing one fare under two names.

    The one fare selected on something other than the trade-off is the route's
    direct flight, which always gets a card when the route has one — see the
    two blocks marked "direct" below. Direct flights are rare enough that this
    is nearly free: of 30 live searches held in cache, 28 routes have no
    non-stop at all, one is non-stop throughout (Cairo->Aswan, where the
    cheapest fare is already the direct one), and exactly one route changes.
    """
    frontier = _price_time_frontier(candidates)
    if not frontier:
        return {}

    # The route's best direct flight, taken before the fare ceiling below can
    # price it out. "Is there a direct flight?" is the first question asked of
    # a long-haul route, and the answer is the traveller's to weigh against the
    # fare beside it — not ours to withhold because the fare is high. A live
    # Colombo->Gatwick search carried exactly one non-stop, at 2.03x the
    # cheapest connection, and the ceiling dropped it for being 3% over.
    #
    # Only this one fare is exempt. Every other non-stop still answers to the
    # ceiling, so a first-class seat on the same aircraft cannot ride in behind
    # it and reach the middle card, which is the one the budget prices itself
    # from.
    nonstops = [c for c in frontier if c["stops"] == 0]
    direct = min(nonstops, key=lambda c: (c["price"], c["duration"])) if nonstops else None

    floor = min(c["price"] for c in frontier)
    frontier = [
        c for c in frontier
        if c["price"] <= floor * _FARE_CEILING or c is direct
    ]
    # On a price/time frontier the cheapest fare is also the slowest, so price
    # order is the order of the trade-off itself.
    frontier.sort(key=lambda c: (c["price"], c["duration"], c["stops"]))

    cheapest = frontier[0]
    picked = [cheapest]

    # A route that has a direct flight shows it. Leaving that to the "fastest"
    # rule below is not enough: a connection landing within
    # `_NEAR_TIE_DURATION` of the non-stop beats it there on price, and the
    # direct flight vanishes from a route that has one.
    if direct is not None and direct is not cheapest:
        picked.append(direct)

    # The fast end — but never pay extra to shave minutes, so among everything
    # arriving within `_NEAR_TIE_DURATION` of the quickest, take the cheapest.
    quickest = max(min(c["duration"] for c in frontier), 1)
    fastest = min(
        (c for c in frontier if (c["duration"] - quickest) / quickest < _NEAR_TIE_DURATION),
        key=lambda c: c["price"],
    )
    # `picked[1:]` is the direct card when the route has one and nothing
    # otherwise, so a route without a non-stop keeps exactly its old behaviour.
    if all(fastest is not p for p in picked) and all(
        _meaningfully_different(fastest, p) for p in picked[1:]
    ):
        picked.append(fastest)

    # A middle card has to earn its place: the most transit time saved per
    # extra rupee over the cheapest fare.
    taken = {id(c) for c in picked}
    rest = [
        c for c in frontier
        if id(c) not in taken and all(_meaningfully_different(c, p) for p in picked)
    ]
    while rest and len(picked) < len(FLIGHT_TIERS):
        best = max(
            rest,
            key=lambda c: (cheapest["duration"] - c["duration"])
            / max(c["price"] - cheapest["price"], 1),
        )
        picked.append(best)
        rest = [c for c in rest if c is not best and _meaningfully_different(c, best)]

    picked.sort(key=lambda c: (c["price"], c["duration"]))
    # Two fares fill the ends, as they have since tiers landed; the middle name
    # is the one a thin route does without.
    names = (
        FLIGHT_TIERS if len(picked) == 3
        else ("minimum", "comfortable") if len(picked) == 2
        else ("minimum",)
    )
    return dict(zip(names, picked))


def _candidate_metrics(serpapi_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Every priced, distinct itinerary in one SerpApi response, best-ranked first."""
    if not serpapi_data:
        return []
    raw_options = (serpapi_data.get("best_flights") or []) + (serpapi_data.get("other_flights") or [])
    candidates: List[Dict[str, Any]] = []
    seen = set()
    for option in raw_options:
        metrics = _flight_option_metrics(option)
        if not metrics or metrics["identity"] in seen:
            continue
        seen.add(metrics["identity"])
        candidates.append(metrics)
    return candidates


def _leg_payload(m: Dict[str, Any], date: str, currency: str, *, priced: bool) -> Dict[str, Any]:
    """One direction of a journey, as the app's FlightLeg reads it.

    `priced` is True only when the fare in `m` is this leg's own (a one-way
    search). A round-trip response prices the whole journey on the outbound
    option, so its legs carry no price of their own.
    """
    return {
        "origin": m.get("origin_id") or "",
        "destination": m.get("dest_id") or "",
        "date": date or "",
        "departure_time": m.get("departure_time") or "",
        "arrival_time": m.get("arrival_time") or "",
        "airlines": list(m.get("airlines") or []),
        "flight_numbers": list(m.get("flight_numbers") or []),
        "stops": int(m.get("stops") or 0),
        "duration_minutes": int(m.get("duration") or 0),
        "duration": _format_duration(m.get("duration") or 0),
        "price_per_traveler": (
            round(convert_from_search_currency(m["price"], currency), 2) if priced else None
        ),
        "segments": list(m.get("segments") or []),
        "booking_url": "",  # filled server-side by _apply_flight_booking_urls
    }


def _stop_label(stops: int) -> str:
    return "Non-stop" if stops == 0 else ("1 stop" if stops == 1 else f"{stops} stops")


def _card_title(stops: int, total_minutes: int) -> str:
    """The header of one flight card: what the itinerary *is*, never a verdict.

    The three cards used to be headed "Cheapest Fare", "Best Value Route" and
    "Fastest & Fewest Stops". Two of those are claims about the other cards,
    and a claim can be wrong: a live Colombo->Edinburgh search headed its
    dearest, most-stopped fare "Best Value Route". Connections and time in
    transit are facts about this itinerary alone, and they are the two the
    fares are ranked on, so no two cards on a route can share a header.

    Carrier was tried here first and read identically on two cards of the same
    open jaw — they flew out together and differed only on the way home.
    """
    stop_text = _stop_label(stops)
    duration = _format_duration(total_minutes)
    return f"{stop_text} · {duration}" if duration else stop_text


def _strategy_payload(
    *,
    tier: str,
    rank: int,
    m: Dict[str, Any],
    per_traveler: float,
    party: int,
    currency: str,
    trip_type: str,
    outbound_date: str,
    return_date: str,
    description: str,
    outbound: Dict[str, Any],
    return_leg: Dict[str, Any] | None,
) -> Dict[str, Any]:
    out_minutes = int(outbound.get("duration_minutes") or 0)
    ret_minutes = int(return_leg.get("duration_minutes") or 0) if return_leg else None
    return {
        # ── Structured, authoritative numbers ──────────────────────────
        "tier": tier,
        "price_per_traveler": per_traveler,
        "price_total": round(per_traveler * party, 2),
        "currency": currency.upper(),
        "price_basis": "per_traveler",
        "trip_type": trip_type,
        "outbound_date": outbound_date,
        "return_date": return_date,
        "outbound_duration_minutes": out_minutes,
        "return_duration_minutes": ret_minutes,
        "total_duration_minutes": out_minutes + (ret_minutes or 0),
        "is_live_price": True,
        "price_source": "google_flights_serpapi",
        "travelers": party,
        "travel_class": m.get("travel_class") or "",
        "flight_numbers": list(m.get("flight_numbers") or []),

        # ── Each direction on its own, for the app's Outbound / Return blocks ──
        "outbound": outbound,
        "return": return_leg,
        "return_route": (
            f"{return_leg['origin']} → {return_leg['destination']}"
            if return_leg and return_leg.get("origin") and return_leg.get("destination") else ""
        ),

        # ── Legacy fields (older app builds read these) ────────────────
        "rank": rank,
        "strategy": "direct" if m["stops"] == 0 else "nearby_airport" if tier == "minimum" else "budget_carrier",
        "title": _card_title(int(outbound.get("stops") or 0), out_minutes + (ret_minutes or 0)),
        "provider_name": "Google Flights",
        "description": description,
        # Emptied with the tier titles: every badge it carried ("Best value",
        # "Fastest route") was a verdict on the other cards. The app renders
        # neither field when it is blank, old builds included.
        "estimated_savings": "",
        # Rendered from price_per_traveler, never an independent value.
        "estimated_price_range": f"{currency.upper()} {per_traveler:,.0f}",
        "airlines": list(m.get("airlines") or []),
        "route": (
            f"{outbound['origin']} → {outbound['destination']}"
            if outbound.get("origin") and outbound.get("destination") else ""
        ),
        "stops": int(outbound.get("stops") or 0),
        "total_duration": outbound.get("duration") or "",
        "convenience": _convenience_stars(int(outbound.get("stops") or 0), out_minutes),
        "tip": "",
        "booking_url": "",  # filled server-side by _build_deep_booking_url
    }


def _more_option_payload(m: Dict[str, Any], currency: str, party: int, leg: str) -> Dict[str, Any]:
    per_traveler = round(convert_from_search_currency(m["price"], currency), 2)
    return {
        "leg": leg,
        "price_per_traveler": per_traveler,
        "price_total": round(per_traveler * party, 2),
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


def _typical_range_tip(serpapi_data: Dict[str, Any], currency: str, label: str = "this route") -> str:
    price_insights = (serpapi_data or {}).get("price_insights") or {}
    typical = price_insights.get("typical_price_range") or []
    if isinstance(typical, list) and len(typical) == 2 and typical[0] and typical[1]:
        # Google reports these in the currency the search was made in, which is
        # not the traveller's when SerpApi does not support theirs. Labelling an
        # unconverted figure with their currency code is how a Colombo-Amsterdam
        # fare came to read "LKR 700 - 940" beside a real LKR 262,500 fare.
        typical_lo = convert_from_search_currency(float(typical[0]), currency)
        typical_hi = convert_from_search_currency(float(typical[1]), currency)
        return (
            f"Google's typical range for {label} is {currency.upper()} "
            f"{typical_lo:,.0f} - {typical_hi:,.0f} per traveller."
        )
    return ""


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

    A round-trip response describes the OUTBOUND itineraries only; each
    strategy's `return` is None until `attach_return_leg` fills it from a
    `departure_token` follow-up search. The tokens for the chosen tiers are
    returned under `_departure_tokens` for exactly that purpose — the caller
    pops the key before the result is stored.

    Returns a dict shaped like:
      {
        "strategies": [...],
        "general_tips": [...],
        "best_months": "...",
        "more_options": [...],
        "_departure_tokens": {tier: token},
      }
    """
    candidates = _candidate_metrics(serpapi_data)
    if not candidates:
        return {}

    trip_type = "round_trip" if return_date else "one_way"
    selected = _select_flight_tiers(candidates)
    if not selected:
        return {}

    party = max(int(travelers or 1), 1)

    strategies: List[Dict[str, Any]] = []
    tokens: Dict[str, str] = {}
    for rank, tier in enumerate([t for t in FLIGHT_TIERS if t in selected], start=1):
        m = selected[tier]
        # SerpApi was asked for a currency it supports, which is not always the
        # traveller's. Convert before anything downstream treats these as the
        # trip's own numbers.
        per_traveler = round(convert_from_search_currency(m["price"], currency), 2)
        outbound = _leg_payload(m, outbound_date, currency, priced=(trip_type == "one_way"))
        carriers = ", ".join(m["airlines"][:2]) if m["airlines"] else "multiple carriers"
        trip_label = "round trip" if trip_type == "round_trip" else "one way"
        duration_str = outbound["duration"]
        description = (
            f"{_stop_label(m['stops'])} {trip_label} from {departure_city} to {destination} with {carriers}"
            + (f", {duration_str} outbound." if duration_str else ".")
        )
        strategies.append(_strategy_payload(
            tier=tier, rank=rank, m=m, per_traveler=per_traveler, party=party,
            currency=currency, trip_type=trip_type,
            outbound_date=outbound_date, return_date=return_date,
            description=description, outbound=outbound, return_leg=None,
        ))
        if m.get("departure_token"):
            tokens[tier] = m["departure_token"]

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
    typical = _typical_range_tip(serpapi_data, currency)
    if typical:
        general_tips.append(typical)
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
        _more_option_payload(m, currency, party, "outbound")
        for m in sorted(candidates, key=lambda c: c["price"])
        if m["identity"] not in taken_ids
    ]

    return {
        "strategies": strategies,
        "general_tips": general_tips,
        "best_months": "",
        "more_options": more_options,
        "_departure_tokens": tokens,
    }


# Beyond this many candidates per direction the cross product stops being
# worth ranking: 30 x 30 combinations already cover every fare level Google
# returned, and the tail is the same airlines at worse prices.
_OPEN_JAW_POOL = 30


def extract_open_jaw_strategies_from_serpapi(
    outbound_data: Dict[str, Any],
    return_data: Dict[str, Any],
    *,
    departure_city: str,
    destination: str,
    currency: str,
    outbound_date: str = "",
    return_date: str = "",
    travelers: int = 1,
    arrival_city: str = "",
    departure_gateway_city: str = "",
) -> Dict[str, Any]:
    """Tiers for a trip that lands in one city and flies home from another.

    Google has no single fare for that shape short of a multi-city search plus
    a token follow-up per option, so it is priced as two one-way tickets:
    every outbound itinerary paired with every return one, and the existing
    tier selection run over the pairs. `price_per_traveler` is both legs
    together; each leg also carries its own fare.
    """
    outbound = _candidate_metrics(outbound_data)
    inbound = _candidate_metrics(return_data)
    if not outbound or not inbound:
        return {}

    outbound = sorted(outbound, key=lambda c: c["price"])[:_OPEN_JAW_POOL]
    inbound = sorted(inbound, key=lambda c: c["price"])[:_OPEN_JAW_POOL]

    combos: List[Dict[str, Any]] = []
    for o in outbound:
        for r in inbound:
            airlines = list(o["airlines"])
            airlines += [a for a in r["airlines"] if a not in airlines]
            combos.append({
                "identity": (o["identity"], r["identity"]),
                "price": o["price"] + r["price"],
                "duration": o["duration"] + r["duration"],
                "stops": o["stops"] + r["stops"],
                "airlines": airlines,
                "flight_numbers": o["flight_numbers"] + r["flight_numbers"],
                "origin_id": o["origin_id"],
                "dest_id": o["dest_id"],
                "travel_class": o["travel_class"] or r["travel_class"],
                "departure_time": o["departure_time"],
                "arrival_time": o["arrival_time"],
                "_outbound": o,
                "_return": r,
            })

    selected = _select_flight_tiers(combos)
    if not selected:
        return {}

    party = max(int(travelers or 1), 1)
    into = arrival_city or destination
    home_from = departure_gateway_city or destination

    strategies: List[Dict[str, Any]] = []
    for rank, tier in enumerate([t for t in FLIGHT_TIERS if t in selected], start=1):
        m = selected[tier]
        o, r = m["_outbound"], m["_return"]
        per_traveler = round(convert_from_search_currency(m["price"], currency), 2)
        out_leg = _leg_payload(o, outbound_date, currency, priced=True)
        ret_leg = _leg_payload(r, return_date, currency, priced=True)
        out_carriers = ", ".join(o["airlines"][:2]) if o["airlines"] else "multiple carriers"
        ret_carriers = ", ".join(r["airlines"][:2]) if r["airlines"] else "multiple carriers"
        description = (
            f"{_stop_label(o['stops'])} from {departure_city} to {into} with {out_carriers}"
            + (f", {out_leg['duration']}" if out_leg["duration"] else "")
            + f"; home from {home_from} with {ret_carriers}, {_stop_label(r['stops']).lower()}"
            + (f", {ret_leg['duration']}." if ret_leg["duration"] else ".")
        )
        strategies.append(_strategy_payload(
            tier=tier, rank=rank, m=m, per_traveler=per_traveler, party=party,
            currency=currency, trip_type="open_jaw",
            outbound_date=outbound_date, return_date=return_date,
            description=description, outbound=out_leg, return_leg=ret_leg,
        ))

    general_tips: List[str] = [
        f"Live Google Flights fares: fly into {into} on {outbound_date or 'the outbound date'} and "
        f"home from {home_from} on {return_date or 'the return date'}, priced as two one-way "
        f"tickets per traveller including taxes."
    ]
    if party > 1:
        general_tips.append(
            f"Group total is the per-traveller fare x {party}; seats at the lowest fare may be limited."
        )
    for data, label in ((outbound_data, "the outbound"), (return_data, "the return")):
        typical = _typical_range_tip(data, currency, label)
        if typical:
            general_tips.append(typical)
    general_tips.append("Fares change constantly — tap through to confirm the current price before booking.")

    taken_out = {m["_outbound"]["identity"] for m in selected.values()}
    taken_ret = {m["_return"]["identity"] for m in selected.values()}
    more_options = [
        _more_option_payload(m, currency, party, "outbound")
        for m in outbound if m["identity"] not in taken_out
    ] + [
        _more_option_payload(m, currency, party, "return")
        for m in inbound if m["identity"] not in taken_ret
    ]

    return {
        "strategies": strategies,
        "general_tips": general_tips,
        "best_months": "",
        "more_options": more_options,
        "_departure_tokens": {},
    }


def rerank_tiers(strategies: List[Dict[str, Any]]) -> bool:
    """Put the cards back in order after a fare has moved, dropping any that
    the move has made pointless.

    A tier name is a price rank, and every card must cost more than the one
    above it and get there sooner - that is the whole basis of the Flights tab
    and what stops a card claiming to be better than one it is beaten by.
    `attach_return_leg` breaks both: Google prices a round trip at the outbound
    level, so every card carries the cheapest total achievable with that
    outbound, and pricing one card's specific return replaces its fare with
    what that exact pair costs while the others keep the "from" price.

    Seen live on a Colombo->Spain search: Recommended came back at EUR 1,459
    over 39h 35m beside a Comfortable at EUR 939 over 15h 50m - cheaper and two
    and a half times quicker. Re-ranking alone would have left that fare on the
    top card, still dearer and still slower than the one beneath it, so an
    itinerary beaten on both axes is dropped instead. Two cards is a normal
    outcome for a route, not a degraded one.

    Re-ranked here rather than pricing every return first: returns cost a
    SerpApi search each and only one is bought per plan, so the fare that moves
    is known only after the ladder exists. Returns True when anything changed.
    """
    priced = [
        s for s in strategies
        if isinstance(s, dict) and isinstance(s.get("price_per_traveler"), (int, float))
        and s["price_per_traveler"] > 0
    ]
    if len(priced) < 2:
        return False

    before = [(id(s), s.get("tier")) for s in strategies]

    def _mins(s):
        return int(s.get("total_duration_minutes") or 0)

    # Beaten on money and on time, by a card that is not merely its equal.
    kept = [
        s for s in priced
        if not any(
            o is not s
            and o["price_per_traveler"] <= s["price_per_traveler"]
            and _mins(o) <= _mins(s)
            and (o["price_per_traveler"] < s["price_per_traveler"] or _mins(o) < _mins(s))
            for o in priced
        )
    ]
    if not kept:
        kept = priced

    kept.sort(key=lambda s: (s["price_per_traveler"], _mins(s)))
    names = (
        FLIGHT_TIERS if len(kept) == 3
        else ("minimum", "comfortable") if len(kept) == 2
        else ("minimum",)
    )
    for rank, (name, strat) in enumerate(zip(names, kept), start=1):
        strat["tier"] = name
        strat["rank"] = rank

    strategies[:] = kept
    return [(id(s), s.get("tier")) for s in strategies] != before


def attach_return_leg(
    strategy: Dict[str, Any],
    return_data: Dict[str, Any],
    *,
    currency: str,
    return_date: str = "",
) -> bool:
    """Fill a round-trip strategy's `return` from its departure_token follow-up.

    Each option in `return_data` is a return itinerary for the strategy's
    outbound, priced as the whole round trip. The cheapest is taken — it is
    the one Google's outbound-level price was quoting — and its combined fare
    replaces the strategy's, since that is the bookable number. Returns True
    when a return leg was attached.
    """
    candidates = _candidate_metrics(return_data)
    if not candidates or not isinstance(strategy, dict):
        return False
    best = min(candidates, key=lambda c: (c["price"], c["duration"], c["stops"]))

    ret_leg = _leg_payload(best, return_date or strategy.get("return_date") or "", currency, priced=False)
    strategy["return"] = ret_leg
    strategy["return_route"] = (
        f"{ret_leg['origin']} → {ret_leg['destination']}"
        if ret_leg["origin"] and ret_leg["destination"] else ""
    )
    strategy["return_duration_minutes"] = ret_leg["duration_minutes"]
    # The whole journey, for anything that wants it — but NOT the figure the
    # header quotes, and not `total_duration_minutes`.
    #
    # Google only sells the return itinerary per outbound, so `_RETURN_LEG_TIERS`
    # buys one of these per plan rather than one per card. Folding the return
    # into the headline time therefore changed one card out of three, and the
    # three stopped being comparable: a live Colombo->Osaka plan showed
    # "21h 10m" (outbound), "25h 30m" (outbound + return) and "10h 55m"
    # (outbound) side by side, which made the cheapest card look quicker than
    # the middle one and undid the whole point of ranking them by time.
    #
    # Every card now quotes its outbound, which is the half Google priced for
    # all of them. The return is shown as its own line on the card that has it.
    strategy["round_trip_duration_minutes"] = (
        int(strategy.get("outbound_duration_minutes") or 0) + ret_leg["duration_minutes"]
    )

    combined = round(convert_from_search_currency(best["price"], currency), 2)
    previous = strategy.get("price_per_traveler")
    if combined > 0:
        if isinstance(previous, (int, float)) and previous > 0 and abs(combined - previous) / previous > 0.10:
            logger.info(
                "[SerpApi] Round-trip fare moved from %s to %s once the return leg was priced.",
                previous, combined,
            )
        party = max(int(strategy.get("travelers") or 1), 1)
        strategy["price_per_traveler"] = combined
        strategy["price_total"] = round(combined * party, 2)
        strategy["estimated_price_range"] = f"{currency.upper()} {combined:,.0f}"
    return True


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
