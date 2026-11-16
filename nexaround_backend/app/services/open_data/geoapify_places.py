"""Geoapify Places (OpenStreetMap data): free live places for an area we have
not downloaded yet, so the first free user there does not wait.

Free plan: 3,000 requests a day (1 request = up to 20 places; we ask for 40 =
2 credits). Counted in Redis; past GEOAPIFY_DAILY_CAP we stop asking and the
caller falls through to the Google backup.

OpenStreetMap data is ODbL: answers are kept in Redis only (7 days), never in
the Overture table, and the app credits "© OpenStreetMap contributors".
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.services import telemetry

logger = logging.getLogger(__name__)

URL = "https://api.geoapify.com/v2/places"
GEOAPIFY_DAILY_CAP = 2700          # credits; the free plan has 3,000
_CACHE_TTL = 7 * 24 * 3600
_PLACE_TTL = 14 * 24 * 3600

CATEGORIES = {
    "Food & Drink": "catering",
    "Shopping": "commercial.supermarket,commercial.shopping_mall,commercial.marketplace,"
                "commercial.department_store,commercial.clothing,commercial.gift_and_souvenir,"
                "commercial.convenience,commercial.food_and_drink,commercial.books,"
                "commercial.jewelry,commercial.elektronics",
    "Hotels": "accommodation",
    "Medical": "healthcare.pharmacy,healthcare.clinic_or_praxis,healthcare.dentist",
    "Hospital": "healthcare.hospital",
}


def _r():
    return telemetry._get_redis()


def _day() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d")


async def credits_used_today() -> int:
    try:
        return int(await _r().get(f"open:geoapify:credits:{_day()}") or 0)
    except Exception:
        return 0


async def _count(credits: int) -> None:
    try:
        key = f"open:geoapify:credits:{_day()}"
        await _r().incrby(key, credits)
        await _r().expire(key, 3 * 86400)
    except Exception:
        pass


def _tags(section: str, cats: list[str]) -> list[str]:
    c = " ".join(cats)
    if section == "Hospital":
        return ["hospital"]
    if section == "Medical":
        if "pharmacy" in c:
            return ["pharmacy"]
        if "dentist" in c:
            return ["dentist"]
        return ["medical_clinic"]
    if section == "Food & Drink":
        if "catering.bar" in c or "catering.pub" in c:
            return ["bar"]
        if "catering.cafe" in c:
            return ["cafe"]
        return ["restaurant"]
    if section == "Hotels":
        return ["hostel"] if "hostel" in c else ["lodging"]
    if section == "Shopping":
        if "shopping_mall" in c:
            return ["shopping_mall"]
        if "supermarket" in c:
            return ["supermarket"]
        return ["store"]
    return []


def to_place(feature: dict, section: str) -> Optional[dict]:
    p = feature.get("properties") or {}
    name = (p.get("name") or "").strip()
    pid = p.get("place_id")
    if not name or not pid or p.get("lat") is None or p.get("lon") is None:
        return None
    raw = (p.get("datasource") or {}).get("raw") or {}
    return {
        "id": f"ga_{pid}"[:120],
        "name": name[:255],
        "section": section,
        "category": ((p.get("categories") or [""])[-1] or "")[:64],
        "latitude": float(p["lat"]),
        "longitude": float(p["lon"]),
        "address": (p.get("formatted") or "")[:500] or None,
        "phone": (raw.get("phone") or raw.get("contact:phone") or None),
        "website": (raw.get("website") or raw.get("contact:website") or None),
        "opening_hours_text": raw.get("opening_hours"),
        "tags": _tags(section, p.get("categories") or []),
        "distance_m": float(p.get("distance") or 0.0),
        "source": "osm",
    }


async def nearby(api_key: str, lat: float, lng: float, section: str,
                 radius_m: int, limit: int = 40) -> list[dict]:
    """Places from Geoapify, cached a week per area. [] when unavailable."""
    cats = CATEGORIES.get(section)
    if not api_key or not cats:
        return []
    key = f"open:geoapify:nb:{lat:.3f}:{lng:.3f}:{section}:{int(radius_m)}"
    try:
        cached = await _r().get(key)
        if cached:
            return json.loads(cached)
    except Exception:
        pass
    credits = max(1, (limit + 19) // 20)
    if await credits_used_today() + credits > GEOAPIFY_DAILY_CAP:
        return []
    places: list[dict] = []
    try:
        async with telemetry.track("geoapify", "places", sku="geoapify_places", cache_key=key) as t:
            async with httpx.AsyncClient(timeout=8) as c:
                r = await c.get(URL, params={
                    "categories": cats,
                    "filter": f"circle:{lng},{lat},{int(radius_m)}",
                    "bias": f"proximity:{lng},{lat}",
                    "limit": limit,
                    "apiKey": api_key,
                })
            t.upstream(r)
            r.raise_for_status()
        await _count(credits)
        for f in r.json().get("features") or []:
            place = to_place(f, section)
            if place:
                places.append(place)
    except Exception as e:
        logger.info("geoapify places failed for %s: %s", section, e)
        return []
    try:
        await _r().set(key, json.dumps(places), ex=_CACHE_TTL)
        pipe = _r().pipeline()
        for place in places:
            pipe.set(f"open:place:{place['id']}", json.dumps(place), ex=_PLACE_TTL)
        await pipe.execute()
    except Exception:
        pass
    return places


async def cached_place(place_id: str) -> Optional[dict]:
    try:
        raw = await _r().get(f"open:place:{place_id}")
        return json.loads(raw) if raw else None
    except Exception:
        return None


async def opening_hours(api_key: str, name: str, lat: float, lng: float) -> Optional[str]:
    """OpenStreetMap opening hours for a named place within 300 m, via a
    Geoapify search (1 credit, inside the same daily cap). Kept 14 days,
    "none" answers included, so a place is looked up once."""
    if not api_key or not name:
        return None
    key = f"open:geoapify:hours:{name.strip().lower()[:80]}:{lat:.4f}:{lng:.4f}"
    try:
        cached = await _r().get(key)
        if cached is not None:
            v = cached.decode() if isinstance(cached, bytes) else str(cached)
            return v or None
    except Exception:
        pass
    if await credits_used_today() + 2 > GEOAPIFY_DAILY_CAP:
        return None
    hours: Optional[str] = None
    try:
        # 1. Find the place by name nearby (the search answer has no hours).
        async with telemetry.track("geoapify", "hours_search", sku="geoapify_places", cache_key=key) as t:
            async with httpx.AsyncClient(timeout=6) as c:
                r = await c.get("https://api.geoapify.com/v1/geocode/search", params={
                    "text": name,
                    "filter": f"circle:{lng},{lat},300",
                    "bias": f"proximity:{lng},{lat}",
                    "limit": 3,
                    "apiKey": api_key,
                })
            t.upstream(r)
            r.raise_for_status()
        await _count(1)
        want = name.strip().lower()
        geo_id = None
        for f in r.json().get("features") or []:
            props = f.get("properties") or {}
            got = str(props.get("name") or "").strip().lower()
            if got and (got in want or want in got) and props.get("place_id"):
                geo_id = props["place_id"]
                break
        # 2. Its details carry OpenStreetMap's opening_hours.
        if geo_id:
            async with telemetry.track("geoapify", "hours_details", sku="geoapify_places", cache_key=key) as t:
                async with httpx.AsyncClient(timeout=6) as c:
                    d = await c.get("https://api.geoapify.com/v2/place-details", params={
                        "id": geo_id, "apiKey": api_key,
                    })
                t.upstream(d)
                d.raise_for_status()
            await _count(1)
            props = ((d.json().get("features") or [{}])[0].get("properties") or {})
            raw = (props.get("datasource") or {}).get("raw") or {}
            oh = props.get("opening_hours") or raw.get("opening_hours")
            if oh:
                hours = str(oh)[:300]
    except Exception as e:
        logger.info("geoapify hours failed for %s: %s", name, e)
        return None
    try:
        await _r().set(key, hours or "", ex=_PLACE_TTL)
    except Exception:
        pass
    return hours

