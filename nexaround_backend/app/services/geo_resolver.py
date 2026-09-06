"""Resolve a free-text destination to a place the AI cannot argue with.

## Why this exists

A tester planned a trip to **Port Blair**, which India renamed **Sri Vijaya
Puram** in 2024. The Odyssey came back split down the middle: the Stays tab
listed real Andaman hotels, while the itinerary toured Kandy and the Temple of
the Sacred Tooth Relic and the flight landed at Colombo.

The split is the whole diagnosis. Hotels are searched by handing the raw string
to Google Hotels, which resolves the place itself — no model involved, so no
room to be wrong. Everywhere a model saw the destination it received exactly one
fact, `- Destination: Sri Vijaya Puram`, and a name beginning "Sri" resolved, in
its training data, to Sri Lanka.

Coordinates alone do not fix that. To a language model `11.62, 92.72` is three
tokens it cannot look up. What settles the question is the country stated in
words — "Andaman and Nicobar Islands, India" — which is what this module exists
to obtain, from Google rather than from the model being corrected.

## Contract

`resolve_destination` never raises and never blocks for long. Every failure
path returns a `DestinationContext` with `resolved == False`, and every consumer
treats that as "carry on exactly as before". A missing API key, a Places miss or
a slow network can therefore make an Odyssey no worse than it already is.
"""
from __future__ import annotations

import asyncio
import json
import logging
import math
import re
from dataclasses import dataclass
from typing import Optional

from app.services import google_places_client, place_cache_service, trip_cost_floor

logger = logging.getLogger(__name__)

# 30 days. A city does not move, and the rename that motivated this module is
# the rare exception rather than the rule.
_CACHE_TTL_SECONDS = 30 * 24 * 3600
_CACHE_PREFIX = "geo:dest:v2:"

# Places is a dependency of a background job, not of a request the user is
# waiting on, but an Odyssey should not stall behind it either.
_RESOLVE_TIMEOUT_S = 6.0

# Hard ceiling on Places lookups per Odyssey. See GeoBudget.
_MAX_GEO_LOOKUPS_PER_ODYSSEY = 6


# ── Renamed places ─────────────────────────────────────────────────────────
#
# Google returns a place's *current* name and no former ones, so a traveller
# who typed the old name and a model that only knows the old name have no way
# to meet. Each group is a set of names for one place; any member resolves the
# others. Keep this short and restricted to genuine official renames — it is
# not a synonym list, and a wrong entry here silently relocates a trip.
_RENAMES: tuple[frozenset[str], ...] = (
    frozenset({"port blair", "sri vijaya puram"}),
    frozenset({"havelock island", "swaraj dweep"}),
    frozenset({"neil island", "shaheed dweep"}),
    frozenset({"bangalore", "bengaluru"}),
    frozenset({"madras", "chennai"}),
    frozenset({"calcutta", "kolkata"}),
    frozenset({"bombay", "mumbai"}),
    frozenset({"kiev", "kyiv"}),
    frozenset({"rangoon", "yangon"}),
    frozenset({"saigon", "ho chi minh city"}),
    frozenset({"turkey", "türkiye", "turkiye"}),
    frozenset({"swaziland", "eswatini"}),
    frozenset({"holland", "netherlands"}),
    frozenset({"macedonia", "north macedonia"}),
)


def _norm(text: str) -> str:
    return " ".join((text or "").strip().lower().split())


def aliases_for(name: str) -> set[str]:
    """Every other name the same place is known by. Empty for most places."""
    key = _norm(name)
    out: set[str] = set()
    for group in _RENAMES:
        if key in group:
            out |= set(group)
    out.discard(key)
    return out


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in km."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ── Lookup budget ──────────────────────────────────────────────────────────
class GeoBudget:
    """Hard ceiling on Places calls for one Odyssey generation.

    Verification is worth paying for, but it is worth paying a *bounded*
    amount for: a multi-city trip could otherwise stack destination resolution,
    per-leg checks, airport checks and drift sampling into a double-digit bill
    on a single generate. Each consumer calls `take()` and skips its check when
    refused, so running out degrades the guard rather than failing the trip.

    Spend priority is the order the callers run in: destination resolution
    first (it is the actual fix), then airports, then legs, then drift
    sampling — so the cheapest-value check is the one that goes hungry.
    """

    __slots__ = ("left", "spent")

    def __init__(self, limit: int = _MAX_GEO_LOOKUPS_PER_ODYSSEY) -> None:
        self.left = max(int(limit), 0)
        self.spent = 0

    def take(self, n: int = 1) -> bool:
        if n <= 0:
            return True
        if self.left < n:
            return False
        self.left -= n
        self.spent += n
        return True


@dataclass(frozen=True)
class DestinationContext:
    """What we actually know about where the trip is, as opposed to what was typed."""

    query: str
    name: str = ""
    formatted_address: str = ""
    country: str = ""
    country_code: str = ""
    admin_area: str = ""
    aliases: tuple[str, ...] = ()
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    place_id: str = ""
    source: str = "unresolved"  # client | places | static | unresolved

    @property
    def resolved(self) -> bool:
        """True once we know the country — the fact the prompts actually need."""
        return bool(self.country_code)

    @property
    def has_coords(self) -> bool:
        return self.latitude is not None and self.longitude is not None

    @property
    def display_name(self) -> str:
        return self.name or self.query

    def label(self) -> str:
        """"Sri Vijaya Puram, Andaman and Nicobar Islands, India"."""
        parts = [self.display_name]
        if self.admin_area and self.admin_area != self.display_name:
            parts.append(self.admin_area)
        if self.country:
            parts.append(self.country)
        return ", ".join(parts)

    @classmethod
    def from_dict(cls, data: dict) -> "DestinationContext":
        """Rebuild from `as_dict` / cached JSON, restoring the alias tuple."""
        known = {f for f in cls.__dataclass_fields__}
        payload = {k: v for k, v in (data or {}).items() if k in known}
        payload["aliases"] = tuple(payload.get("aliases") or ())
        payload.setdefault("query", "")
        return cls(**payload)

    def as_dict(self) -> dict:
        return {
            "query": self.query, "name": self.name,
            "formatted_address": self.formatted_address,
            "country": self.country, "country_code": self.country_code,
            "admin_area": self.admin_area, "aliases": list(self.aliases),
            "latitude": self.latitude, "longitude": self.longitude,
            "place_id": self.place_id, "source": self.source,
        }


def _context_from_geo(query: str, geo: dict, source: str) -> DestinationContext:
    name = geo.get("name") or query
    alias_set = aliases_for(query) | aliases_for(name)
    alias_set.discard(_norm(name))
    return DestinationContext(
        query=query,
        name=name,
        formatted_address=geo.get("formatted_address") or "",
        country=geo.get("country") or "",
        country_code=(geo.get("country_code") or "").upper(),
        admin_area=geo.get("admin_area") or "",
        aliases=tuple(sorted(alias_set)),
        latitude=geo.get("latitude"),
        longitude=geo.get("longitude"),
        place_id=geo.get("place_id") or "",
        source=source,
    )


def _country_from_address_tail(address: str) -> str:
    """Last comma-segment of a formatted address, as an ISO-2 code if we know it.

    Only used when Google would not give us address components. "…, Andaman and
    Nicobar Islands, India" -> "IN".
    """
    if not address:
        return ""
    tail = address.split(",")[-1].strip()
    return (trip_cost_floor.country_for(tail) or "").upper()


def _static_context(query: str, latitude=None, longitude=None) -> DestinationContext:
    """Country from the in-process table — no network, no key required."""
    code = (trip_cost_floor.country_for(query) or "").upper()
    if not code:
        for alias in aliases_for(query):
            code = (trip_cost_floor.country_for(alias) or "").upper()
            if code:
                break
    if not code:
        return DestinationContext(query=query, name=query, source="unresolved")
    alias_set = aliases_for(query)
    return DestinationContext(
        query=query, name=query, country_code=code,
        country=_COUNTRY_NAMES.get(code, ""),
        aliases=tuple(sorted(alias_set)),
        latitude=latitude, longitude=longitude,
        source="static",
    )


# Enough country names to render a prompt line. Only codes that appear in
# trip_cost_floor.PLACE_COUNTRY need an entry; anything missing degrades to the
# ISO code, which still reads unambiguously in a prompt.
_COUNTRY_NAMES: dict[str, str] = {
    "IN": "India", "LK": "Sri Lanka", "MV": "Maldives", "NP": "Nepal",
    "TH": "Thailand", "SG": "Singapore", "MY": "Malaysia", "ID": "Indonesia",
    "VN": "Vietnam", "KH": "Cambodia", "PH": "Philippines", "JP": "Japan",
    "KR": "South Korea", "CN": "China", "HK": "Hong Kong", "TW": "Taiwan",
    "AE": "United Arab Emirates", "QA": "Qatar", "OM": "Oman", "SA": "Saudi Arabia",
    "KW": "Kuwait", "BH": "Bahrain", "TR": "Türkiye", "JO": "Jordan",
    "GB": "United Kingdom", "FR": "France", "DE": "Germany", "IT": "Italy",
    "ES": "Spain", "PT": "Portugal", "NL": "Netherlands", "BE": "Belgium",
    "CH": "Switzerland", "AT": "Austria", "CZ": "Czechia", "GR": "Greece",
    "US": "United States", "CA": "Canada", "MX": "Mexico", "BR": "Brazil",
    "AU": "Australia", "NZ": "New Zealand", "ZA": "South Africa",
    "EG": "Egypt", "KE": "Kenya", "MA": "Morocco", "MU": "Mauritius",
    "PK": "Pakistan", "BD": "Bangladesh", "RU": "Russia",
}


async def resolve_destination(
    query: str,
    *,
    place_id: str = "",
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    address_hint: str = "",
    budget: Optional[GeoBudget] = None,
) -> DestinationContext:
    """Best-effort canonical identity for a typed destination. Never raises.

    Order is cheapest-first, and the first two steps cost nothing:

    1. cache — a city does not move
    2. the client's own coordinates plus a country we can name without asking
    3. a single Places call, biased by those coordinates when we have them
    4. a single Places call on the name alone
    5. the static country table, which needs neither key nor network
    """
    q = (query or "").strip()
    if not q:
        return DestinationContext(query=query or "", source="unresolved")

    cache_key = f"{_CACHE_PREFIX}{place_id or _norm(q)}"
    try:
        cached = await place_cache_service.get_raw(cache_key)
        if cached:
            return DestinationContext.from_dict(json.loads(cached))
    except Exception as e:  # cache is an optimisation, never a dependency
        logger.debug("Destination cache read failed for %s: %s", q, e)

    ctx: DestinationContext | None = None
    try:
        ctx = await asyncio.wait_for(
            _resolve_uncached(
                q, place_id=place_id, latitude=latitude,
                longitude=longitude, address_hint=address_hint, budget=budget,
            ),
            timeout=_RESOLVE_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        logger.warning("Destination resolution timed out for %r", q)
    except Exception as e:
        logger.warning("Destination resolution failed for %r: %s", q, e)

    if ctx is None:
        ctx = _static_context(q, latitude, longitude)

    if ctx.resolved:
        try:
            await place_cache_service.set_raw(
                cache_key, json.dumps(ctx.as_dict()), ttl=_CACHE_TTL_SECONDS,
            )
        except Exception as e:
            logger.debug("Destination cache write failed for %s: %s", q, e)
    return ctx


async def _resolve_uncached(
    q: str, *, place_id: str, latitude, longitude, address_hint: str,
    budget: Optional[GeoBudget],
) -> DestinationContext:
    # 2. The app already picked this place, and we can name the country without
    #    asking anyone. Free, and the common case once the client ships.
    if latitude is not None and longitude is not None:
        code = (
            trip_cost_floor.country_for(address_hint)
            or trip_cost_floor.country_for(q)
            or ""
        ).upper()
        if code:
            alias_set = aliases_for(q)
            return DestinationContext(
                query=q, name=q,
                formatted_address=address_hint or "",
                country=_COUNTRY_NAMES.get(code, ""), country_code=code,
                admin_area="", aliases=tuple(sorted(alias_set)),
                latitude=latitude, longitude=longitude,
                place_id=place_id, source="client",
            )

    # 3/4. One Places call, biased by the client's coordinates when present.
    if budget is None or budget.take():
        geo = await google_places_client.resolve_place_geo(
            q, bias_lat=latitude, bias_lng=longitude, bias_radius_m=25_000.0,
        )
        if geo:
            if not geo.get("country_code"):
                geo["country_code"] = _country_from_address_tail(
                    geo.get("formatted_address") or ""
                )
            if geo.get("country_code"):
                if not geo.get("country"):
                    geo["country"] = _COUNTRY_NAMES.get(geo["country_code"], "")
                ctx = _context_from_geo(q, geo, "places")
                # The client's own coordinates are the ones the user actually
                # tapped; keep them when Google's differ only trivially.
                if latitude is not None and longitude is not None and not ctx.has_coords:
                    ctx = DestinationContext.from_dict(
                        {**ctx.as_dict(), "latitude": latitude, "longitude": longitude}
                    )
                return ctx

    # 5. Static table.
    return _static_context(q, latitude, longitude)


# ── Free drift scan (Tier 1) ───────────────────────────────────────────────
#
# Costs nothing: one precompiled regex over the country table already in
# memory. It is the check that would have caught the reported bug twice — once
# on "Kandy" and again on "Sri Lankan rice and curry".

# Short names collide destructively: "goa" inside "goad", "nice" inside
# "somewhere nice", "male" inside "male travellers". trip_cost_floor learned
# this the hard way and set the same floor for its own loose matching, so reuse
# its constant rather than inventing a second, drifting one.
_MIN_SCAN_LEN = trip_cost_floor._MIN_LOOSE_MATCH

# Demonyms and adjectival forms, so "Sri Lankan rice and curry" and "Kandyan
# dancers" are caught as readily as the bare place name. Deliberately does NOT
# include a bare "h" or "es" — "parish" must not read as Paris.
_DEMONYM_SUFFIX = r"(?:n|ns|an|ans|ian|ians|ese|ish|i)?"


def _build_place_regex() -> re.Pattern:
    names = sorted(
        (n for n in trip_cost_floor.PLACE_COUNTRY if len(n) >= _MIN_SCAN_LEN),
        key=len, reverse=True,  # longest first: "sri lanka" before "lanka"
    )
    if not names:
        return re.compile(r"(?!x)x")  # matches nothing
    alt = "|".join(re.escape(n) for n in names)
    return re.compile(rf"\b({alt}){_DEMONYM_SUFFIX}\b", re.IGNORECASE)


_PLACE_RE = _build_place_regex()


def foreign_place_hits(
    text: str, home_code: str, allow: frozenset[str] = frozenset(),
) -> dict[str, str]:
    """Place names in `text` that belong to a country other than `home_code`.

    Returns {matched name: ISO-2 country}. `allow` holds codes that are
    legitimately foreign for this trip — the traveller's departure country and
    nationality both get named in visa and logistics copy, and neither is drift.
    """
    if not text or not home_code:
        return {}
    home = home_code.upper()
    hits: dict[str, str] = {}
    for match in _PLACE_RE.finditer(text):
        name = match.group(1).lower()
        code = (trip_cost_floor.PLACE_COUNTRY.get(name) or "").upper()
        if code and code != home and code not in allow:
            hits[name] = code
    return hits


@dataclass(frozen=True)
class PlaceCheck:
    query: str
    resolved_name: str = ""
    country_code: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    distance_km: Optional[float] = None
    ok: bool = True          # True when we could not disprove it
    checked: bool = False    # False when no lookup happened at all


async def verify_place(
    name: str,
    *,
    near: Optional[DestinationContext] = None,
    max_km: Optional[float] = None,
    budget: Optional[GeoBudget] = None,
) -> PlaceCheck:
    """Ask Google where a generated place actually is.

    Searched **unbiased** on purpose. Biasing to the destination returns the
    nearest thing sharing the name, which is precisely how a check like this
    talks itself into approving the wrong country.

    `ok` is False only when we positively established a mismatch. Anything we
    could not check — no budget, no key, no result — comes back `ok=True,
    checked=False`, so an unavailable Places API can never invent drift.
    """
    q = (name or "").strip()
    if not q or near is None or not near.resolved:
        return PlaceCheck(query=q)
    if budget is not None and not budget.take():
        return PlaceCheck(query=q)

    try:
        geo = await asyncio.wait_for(
            google_places_client.resolve_place_geo(q), timeout=_RESOLVE_TIMEOUT_S,
        )
    except Exception as e:
        logger.debug("verify_place(%r) failed: %s", q, e)
        return PlaceCheck(query=q)
    if not geo:
        return PlaceCheck(query=q)

    code = (geo.get("country_code") or "").upper()
    lat, lng = geo.get("latitude"), geo.get("longitude")
    dist = None
    if near.has_coords and lat is not None and lng is not None:
        dist = haversine_km(near.latitude, near.longitude, lat, lng)

    ok = True
    if code and code != near.country_code:
        ok = False
    elif max_km is not None and dist is not None and dist > max_km:
        ok = False

    return PlaceCheck(
        query=q, resolved_name=geo.get("name") or "", country_code=code,
        latitude=lat, longitude=lng, distance_km=dist, ok=ok, checked=True,
    )


async def country_from_coordinates(
    latitude: float, longitude: float, *, budget: Optional[GeoBudget] = None,
) -> tuple[str, str]:
    """(country name, ISO-2) for a raw coordinate. ("", "") when unknown.

    A last resort for a departure whose reverse geocode came back as the
    literal string "Nearby" — the sentinel the proxy returns when Geoapify,
    Mapbox and Google have all failed on those coordinates. Re-running that
    same reverse geocode here would fail the same way, so this deliberately
    takes a different route: one Places text search biased to the point, which
    answers with the country of the nearest locality.

    Only the country is wanted. It feeds `_country_fallback_code`, which turns
    "Sri Lanka" into CMB — the honest answer for a traveller whose exact town
    we could not name, and a great deal better than letting a model invent an
    airport, which is how a departure from Trincomalee was quoted from Chennai.
    """
    if latitude is None or longitude is None:
        return ("", "")
    if budget is not None and not budget.take():
        return ("", "")
    try:
        geo = await asyncio.wait_for(
            google_places_client.resolve_place_geo(
                "city", bias_lat=latitude, bias_lng=longitude, bias_radius_m=50_000.0,
            ),
            timeout=_RESOLVE_TIMEOUT_S,
        )
    except Exception as e:
        logger.debug("country_from_coordinates(%s, %s) failed: %s", latitude, longitude, e)
        return ("", "")
    if not geo:
        return ("", "")

    code = (geo.get("country_code") or "").upper()
    if not code:
        tail = (geo.get("formatted_address") or "").split(",")[-1].strip()
        code = (trip_cost_floor.country_for(tail) or "").upper()
    if not code:
        return ("", "")
    return (geo.get("country") or _COUNTRY_NAMES.get(code, ""), code)
