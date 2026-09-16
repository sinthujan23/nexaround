"""What Google actually says about a venue the plan names.

The model writes a restaurant's star rating and a venue's opening hours as
plain fact, and the prompt asks it to confirm both by search. Measured against
the live Places API on 2026-09-16, across 50 ratings on stored September plans:

    exact match (±0.05)  12/50   24%
    within ±0.2          38/50   76%
    off by 0.5 or more    5/50   10%
    average error                0.19 stars

The venues themselves are real — 69 of 70 restaurant names resolved to the
right city — so this is not invention of places. It is invention of the
*numbers attached to them*, which is worse in one specific way: a star rating
is the single most checkable claim in the whole plan. A traveller who opens
Google Maps sees 4.1 where the app said 4.6, and reasonably concludes the
whole itinerary is guesswork.

So ratings and hours are no longer taken from the model at all. They are
looked up here, and a venue Google will not confirm loses its rating rather
than keeping an invented one. One Text Search per venue, cached 30 days: the
same restaurants recur across plans for a city (Trattoria Mario appeared in
two separate Florence plans in the audit sample), so a popular destination
pays for its venues once a month.

Deliberately never raises: a plan that cannot reach Places is still a plan,
and the caller drops the unverifiable fields rather than failing.
"""
from __future__ import annotations

import json
import logging
import math
import re

import httpx

from app.services import place_cache_service, telemetry

logger = logging.getLogger(__name__)

_SEARCH = "https://places.googleapis.com/v1/places:searchText"
_CACHE_PREFIX = "venue_facts:v1"
_CACHE_TTL = 30 * 24 * 3600
_TIMEOUT = 15.0

# `rating`/`userRatingCount` are Enterprise+Atmosphere and
# `regularOpeningHours` is Enterprise, so this mask is billed at the dearer
# tier. It is asked for once per venue per month; see the module docstring.
_FIELD_MASK = (
    "places.id,places.displayName,places.formattedAddress,places.location,"
    "places.rating,places.userRatingCount,places.regularOpeningHours,"
    "places.businessStatus"
)

# How far a venue may sit from the city it was placed in before we treat the
# match as a different place of the same name. The same 60 km the hotel search
# uses, and wide enough for a genuine day-trip venue on a city's edge.
_MAX_KM = 60.0


def _cache_key(name: str, city: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", f"{name}|{city}".lower()).strip("-")
    return f"{_CACHE_PREFIX}:{slug[:180]}"


def _km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    radius = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lng2 - lng1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


# Words that name a kind of establishment rather than a particular one. A
# shared word is what tells us Google answered about the place we asked about,
# and these words carry none of that: an invented "Trattoria Del Fantasma"
# matched a real "Antica Trattoria Santo Padre" on the word "trattoria" alone
# and was handed its rating and its 425 reviews. Measured, not hypothetical.
_GENERIC_VENUE_WORDS = {
    "the", "and", "restaurant", "restaurante", "ristorante", "trattoria",
    "osteria", "hostaria", "pizzeria", "taverna", "tavern", "cafe", "caffe",
    "café", "coffee", "bar", "bistro", "brasserie", "grill", "kitchen",
    "house", "hotel", "inn", "lounge", "club", "garden", "room", "place",
    "restoran", "warung", "kade", "kadai", "hotel", "dhaba", "canteen",
    "eatery", "diner", "food", "foods", "cuisine", "antica", "antico",
    "old", "new", "royal", "grand", "central", "city", "local",
}


def _tokens(text: str) -> set[str]:
    return {t for t in re.split(r"[^\w]+", (text or "").lower()) if len(t) > 2}


def _names_agree(asked: str, got: str) -> bool:
    """Whether Google answered about the place we asked about.

    Text Search always returns *something* for a plausible query, so a venue
    that has closed or never existed comes back as the nearest similar name.
    A shared *distinctive* word separates "Google knows this place by a
    slightly different name" — "Pizzarium Bonci" is Google's "Bonci Pizzarium",
    "Da Enzo al 29" is its "Trattoria Da Enzo" — from "Google found something
    else of the same kind".

    Generic words are dropped before comparing. When a name is nothing but
    generic words there is nothing distinctive to compare, so the whole name
    must match instead: that still confirms a venue genuinely called "The
    Kitchen", while keeping "The Coffee House" from collecting the rating of
    "Old Coffee House Bar". Overlap would accept both, and a wrong rating is
    the thing this module exists to prevent.
    """
    a, b = _tokens(asked), _tokens(got)
    if not a or not b:
        return False
    distinctive_a = a - _GENERIC_VENUE_WORDS
    distinctive_b = b - _GENERIC_VENUE_WORDS
    if distinctive_a and distinctive_b:
        return bool(distinctive_a & distinctive_b)
    return a == b


def _hours_line(raw: dict | None) -> str:
    """Today-agnostic opening hours, in the one-line shape the app draws.

    `weekdayDescriptions` is a week; the card has room for a line. The common
    case by far is a venue open the same hours most days, so the most frequent
    line is the honest summary. Anything else returns "" rather than picking a
    day arbitrarily — an empty field is already handled everywhere.
    """
    descriptions = (raw or {}).get("weekdayDescriptions") or []
    spans: dict[str, int] = {}
    for entry in descriptions:
        text = str(entry or "")
        if ":" not in text:
            continue
        span = text.split(":", 1)[1].strip()
        if not span or not re.search(r"\d", span):
            continue          # "Closed" carries no digits and is not hours
        spans[span] = spans.get(span, 0) + 1
    if not spans:
        return ""
    best, count = max(spans.items(), key=lambda kv: kv[1])
    if count < 4:
        return ""
    # Google separates times with a narrow no-break space and an en space.
    # The app draws this string verbatim under a clock icon, where they render
    # as gaps of surprising widths.
    return best.replace("\u202f", " ").replace("\u2009", " ").replace("\u2013", "-")


async def lookup(
    client: httpx.AsyncClient,
    name: str,
    city: str,
    *,
    latitude: float | None,
    longitude: float | None,
    api_key: str,
) -> dict | None:
    """Google's record of one venue, or None when it will not confirm it.

    Returns {"name", "rating", "review_count", "hours", "latitude",
    "longitude", "open"} — `open` is False for a venue Google marks
    permanently closed, which is a thing worth not sending anyone to.
    """
    clean = (name or "").strip()
    if not clean or not api_key:
        return None

    key = _cache_key(clean, city)
    cached = await place_cache_service.get_raw(key)
    if cached is not None:
        try:
            # "null" is cached too: a venue Google would not confirm should not
            # be asked about again every time a plan names it.
            return json.loads(cached)
        except ValueError:
            pass

    body: dict = {"textQuery": f"{clean}, {city}".strip(", "), "maxResultCount": 1}
    if latitude is not None and longitude is not None:
        body["locationBias"] = {"circle": {
            "center": {"latitude": latitude, "longitude": longitude},
            "radius": 50_000.0,
        }}

    found: dict | None = None
    try:
        # Tracked so this shows as its own line in the cost dashboard: the mask
        # below is billed at Places' dearest Text Search tier, and a
        # verification nobody can see the price of is a verification nobody
        # will notice going wrong.
        async with telemetry.track(
            "google_maps", "venue_facts",
            sku="text_search_atmosphere",
            cache_key=key,
        ) as tracked:
            resp = await client.post(
                _SEARCH, json=body, timeout=_TIMEOUT,
                headers={
                    "X-Goog-Api-Key": api_key,
                    "Content-Type": "application/json",
                    "X-Goog-FieldMask": _FIELD_MASK,
                },
            )
            tracked.upstream(resp)
        if resp.status_code == 200:
            places = resp.json().get("places") or []
            place = places[0] if places else None
            if place:
                got_name = ((place.get("displayName") or {}).get("text") or "").strip()
                location = place.get("location") or {}
                lat, lng = location.get("latitude"), location.get("longitude")
                near_enough = True
                if None not in (lat, lng) and latitude is not None and longitude is not None:
                    near_enough = _km(latitude, longitude, lat, lng) <= _MAX_KM
                if got_name and _names_agree(clean, got_name) and near_enough:
                    found = {
                        "name": got_name,
                        "rating": place.get("rating"),
                        "review_count": place.get("userRatingCount"),
                        "hours": _hours_line(place.get("regularOpeningHours")),
                        "latitude": lat,
                        "longitude": lng,
                        "open": place.get("businessStatus") != "CLOSED_PERMANENTLY",
                    }
    except Exception as exc:
        # Not cached: a timeout is about the network, not about the venue.
        logger.info("Venue lookup failed for %r in %r: %s", clean, city, exc)
        return None

    try:
        await place_cache_service.set_raw(key, json.dumps(found), ttl=_CACHE_TTL)
    except Exception:
        pass
    return found
