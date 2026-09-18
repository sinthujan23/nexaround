"""The cities a traveller may start or finish a trip in, for one country.

The Odyssey planner's Entry box used to accept a whole country, and the client
reported the plans that produced as hallucinated: naming only "Japan" leaves
every city to the model. Entry is now a city, which means the box has to be
able to offer the cities of whichever country was typed.

**No Google API can produce that list.** Measured against the live API on
2026-09-16, every route fails a different way: Text Search for "cities in
Japan" returns nothing, "popular cities to visit in Japan" returns a castle and
a village, a locality-typed search over a box drawn on Japan returns city halls
and a shopping mall, Geocoding for the localities of Japan returns Japan, and
autocomplete for "Japan" returns Japana in Georgia and Japanga in India. Places
is a lookup API - it answers about a name you already have - and has no call
that enumerates what sits inside a country.

So the list is *proposed* by Gemini and *decided* by Google. Gemini knows which
cities a visitor would base in; it does not reliably know what exists. Every
name it offers is put to autocomplete restricted to the country and to
settlements, then to a details call that must return that same country. A name
Google will not confirm never reaches the traveller, so an invented city cannot
appear in the dropdown no matter what the model said.

Restriction matters more than it looks: `regionCode` on Text Search is only a
*bias*, and "Miami" searched with `regionCode: JP` comes back as Miami,
Florida. `includedRegionCodes` on autocomplete is a real restriction - "Paris"
restricted to JP returns nothing at all - which is why verification goes
through autocomplete rather than the one-call Text Search that would otherwise
be cheaper.

Cached for 30 days: which cities a country is known for does not change, so the
first request per country per month pays for it and the rest are free.
"""
from __future__ import annotations

import asyncio
import json
import logging
import re

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.services import place_cache_service

logger = logging.getLogger(__name__)

_AUTOCOMPLETE = "https://places.googleapis.com/v1/places:autocomplete"
_DETAILS = "https://places.googleapis.com/v1/places"

_CACHE_TTL = 30 * 24 * 3600
_CACHE_PREFIX = "country_cities:v1"

# Eight is what fits a dropdown without scrolling and is enough to cover a
# country's usual bases. The list is a starting point, not a cage - the box
# stays a search, so a city outside these eight is still reachable by typing.
_WANTED = 8
_TIMEOUT = 20.0


def _cache_key(country_code: str) -> str:
    return f"{_CACHE_PREFIX}:{country_code.upper()}"


def _tokens(text: str) -> set[str]:
    """Comparable words in a place name, accents and punctuation removed."""
    return {t for t in re.split(r"[^\w]+", (text or "").lower()) if len(t) > 2}


def _names_agree(proposed: str, returned: str) -> bool:
    """Whether Google's answer is the place Gemini meant.

    Autocomplete matches fuzzily inside its restriction, so a name it cannot
    place still comes back as *something*: "Miami" restricted to Japan returns
    Minamioguni. Requiring a shared word separates that from the case worth
    keeping, where Google simply knows the place by another name - Gemini's
    "Machu Picchu Pueblo (Aguas Calientes)" is Google's "Aguas Calientes", and
    Google's name is the one shown.
    """
    a, b = _tokens(proposed), _tokens(returned)
    if not a or not b:
        return False
    return bool(a & b)


async def _propose(country: str, api_key: str) -> list[str]:
    """Ask Gemini which cities a first-time visitor bases themselves in."""
    # Imported here: odyssey_ai_service imports a good deal of the app, and
    # this module is pulled in by the proxy router at startup.
    from app.services import odyssey_ai_service

    prompt = (
        f"List the {_WANTED} cities or towns in {country} that a first-time "
        f"visitor is most likely to base themselves in for a few nights. "
        f"Real, currently inhabited places only - no regions, no provinces, "
        f"no national parks, no single attractions, no airports.\n"
        f'Return ONLY JSON: {{"cities":["...", "..."]}}'
    )
    text, _ = await odyssey_ai_service._call_gemini(
        prompt, api_key, max_tokens=512, thinking_budget=0,
    )
    raw = text or ""
    try:
        data = json.loads(raw[raw.index("{"):raw.rindex("}") + 1])
        names = data.get("cities") or []
    except (ValueError, AttributeError, TypeError) as exc:
        logger.warning("Country cities: could not parse Gemini reply for %s: %s", country, exc)
        return []
    return [str(n).strip() for n in names if isinstance(n, (str, int)) and str(n).strip()][:_WANTED]


async def _confirm(
    client: httpx.AsyncClient, name: str, country_code: str, headers: dict,
) -> dict | None:
    """Google's own record of a proposed city, or None if it will not confirm it."""
    cc = country_code.upper()
    resp = await client.post(_AUTOCOMPLETE, headers=headers, timeout=_TIMEOUT, json={
        "input": name,
        "includedRegionCodes": [cc],
        "includedPrimaryTypes": ["(cities)"],
    })
    if resp.status_code != 200:
        return None
    suggestions = resp.json().get("suggestions") or []
    if not suggestions:
        return None
    prediction = (suggestions[0] or {}).get("placePrediction") or {}
    label = ((prediction.get("text") or {}).get("text") or "").strip()
    place_id = (prediction.get("placeId") or "").strip()
    if not place_id or not _names_agree(name, label):
        return None

    detail = await client.get(
        f"{_DETAILS}/{place_id}",
        headers={**headers, "X-Goog-FieldMask": "id,displayName,location,addressComponents"},
        timeout=_TIMEOUT,
    )
    if detail.status_code != 200:
        return None
    data = detail.json()
    location = data.get("location") or {}
    lat, lng = location.get("latitude"), location.get("longitude")
    if lat is None or lng is None:
        return None
    # The restriction should already guarantee this; checking it here means a
    # coordinate never leaves this module without the country it belongs to
    # having been stated by Google rather than assumed by us.
    got = next(
        (c.get("shortText", "").upper() for c in data.get("addressComponents") or []
         if "country" in (c.get("types") or [])),
        "",
    )
    if got != cc:
        return None
    return {
        "name": ((data.get("displayName") or {}).get("text") or label).strip(),
        "place_id": place_id,
        "latitude": float(lat),
        "longitude": float(lng),
        "country_code": cc,
    }


async def main_cities(
    country: str, country_code: str, *, gemini_key: str, maps_key: str,
    use_cache: bool = True,
    db: AsyncSession | None = None,
) -> list[dict]:
    """Verified cities for one country, newest-known first. Never raises."""
    cc = (country_code or "").strip().upper()
    if len(cc) != 2 or not cc.isalpha() or not (country or "").strip():
        return []

    key = _cache_key(cc)
    if use_cache:
        cached = await place_cache_service.get_raw(key)
        if cached:
            try:
                return json.loads(cached)
            except ValueError:
                pass

    # 1. Database check: if saved in PostgreSQL, return immediately without Gemini or Google Maps API calls
    if db is not None:
        try:
            from sqlalchemy import select
            from app.models.country_city import CountryCity
            stmt = select(CountryCity).where(CountryCity.country_code == cc)
            res = await db.execute(stmt)
            record = res.scalars().first()
            if record and record.cities:
                if use_cache:
                    await place_cache_service.set_raw(key, json.dumps(record.cities), ttl=_CACHE_TTL)
                return record.cities
        except Exception as exc:
            logger.warning("Country cities: DB read failed for %s: %s", cc, exc)

    if not gemini_key or not maps_key:
        return []

    try:
        proposed = await _propose(country, gemini_key)
    except Exception as exc:                      # a dropdown is not worth an error page
        logger.warning("Country cities: proposal failed for %s: %s", country, exc)
        return []
    if not proposed:
        return []

    headers = {"X-Goog-Api-Key": maps_key, "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient() as client:
            results = await asyncio.gather(
                *(_confirm(client, name, cc, headers) for name in proposed),
                return_exceptions=True,
            )
    except Exception as exc:
        logger.warning("Country cities: verification failed for %s: %s", country, exc)
        return []

    cities: list[dict] = []
    seen: set[str] = set()
    for name, outcome in zip(proposed, results):
        if isinstance(outcome, Exception) or not outcome:
            logger.info("Country cities: %s dropped %r (unconfirmed)", cc, name)
            continue
        if outcome["place_id"] in seen:
            continue
        seen.add(outcome["place_id"])
        cities.append(outcome)

    # 2. Database persistence: save verified cities to PostgreSQL
    if cities and db is not None:
        try:
            from sqlalchemy import select
            from app.models.country_city import CountryCity
            stmt = select(CountryCity).where(CountryCity.country_code == cc)
            res = await db.execute(stmt)
            record = res.scalars().first()
            if record:
                record.cities = cities
                record.country = country
            else:
                db.add(CountryCity(country_code=cc, country=country, cities=cities))
            await db.commit()
            logger.info("Country cities: saved %d cities for %s (%s) to DB", len(cities), country, cc)
        except Exception as exc:
            logger.warning("Country cities: DB write failed for %s: %s", cc, exc)
            await db.rollback()

    if cities and use_cache:
        await place_cache_service.set_raw(key, json.dumps(cities), ttl=_CACHE_TTL)
    return cities
