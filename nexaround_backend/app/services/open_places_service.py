"""Free map data for free users: place lists and place pages.

Order for a free user's request (see plan_service.places_source_for for who
gets here at all):
  1. Our copy of Overture places for the area, sorted by our popularity score.
  2. Area not downloaded yet, or too few places: Geoapify (OpenStreetMap), and
     the area is queued for download by the `openimport` container.
  3. Still too few: return None, and the caller uses today's Google method,
     within the free user's map limit (Medical / Hospital are never limited).

Nothing here changes the Google path: it stays exactly as it was, both as the
backup and for paid users and old app builds.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import text

from app.core.database import async_session
from app.schemas.place import BandedPlacesResponse, PlacesNearbyResponse
from app.services import place_bands, spend_guard, telemetry
from app.services.open_data import geoapify_places, sections
from app.services.open_data.score import label_for

logger = logging.getLogger(__name__)

MIN_PLACES = 8          # fewer than this in a list → try the next source
PER_BAND_ROWS = 40
OVERTURE_CREDIT = "Overture Maps Foundation"
OSM_CREDIT = "© OpenStreetMap contributors (Geoapify)"

_COLUMNS = """
    id, name, section, category, latitude, longitude, address, phone, website,
    social, brand, wiki_views, our_points, popularity_score, imported_at,
    ST_Distance(location::geography,
                ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography) AS distance_m
"""


def _place_from_row(r) -> dict:
    m = r._mapping
    score = int(m["popularity_score"] or 0)
    return {
        "id": f"op_{m['id']}",
        "name": m["name"],
        "latitude": float(m["latitude"]),
        "longitude": float(m["longitude"]),
        "category_name": m["section"],
        "address": m["address"],
        "rating": 0.0,
        "review_count": 0,
        "photo_urls": [],
        "tags": sections.tags_for(m["section"], m["category"]),
        "distance_m": float(m["distance_m"] or 0.0),
        "is_active": True,
        "created_at": (m["imported_at"] or datetime.now(timezone.utc)).isoformat(),
        "popularity": score,
        "popularity_label": label_for(
            wiki_views=int(m["wiki_views"] or 0), our_points=int(m["our_points"] or 0), score=score,
        ),
        "data_source": "open",
    }


def _place_from_geoapify(g: dict) -> dict:
    return {
        "id": g["id"],
        "name": g["name"],
        "latitude": g["latitude"],
        "longitude": g["longitude"],
        "category_name": g["section"],
        "address": g.get("address"),
        "rating": 0.0,
        "review_count": 0,
        "photo_urls": [],
        "tags": g.get("tags") or [],
        "distance_m": g.get("distance_m") or 0.0,
        "is_active": True,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "popularity": 0,
        "popularity_label": None,
        "data_source": "open",
    }


# ── Download areas ──────────────────────────────────────────────────────────

async def ensure_tiles(lat: float, lng: float, radius_m: float) -> bool:
    """Queue any area this circle touches that we have never asked for.
    True when every area is already downloaded."""
    tiles = sections.tiles_for_circle(lat, lng, radius_m)
    try:
        async with async_session() as db:
            rows = (await db.execute(
                text("SELECT tile, status FROM open_areas WHERE tile = ANY(:t)"), {"t": tiles},
            )).all()
            known = {r[0]: r[1] for r in rows}
            missing = [t for t in tiles if t not in known]
            if missing:
                await db.execute(
                    text("INSERT INTO open_areas (tile, status) VALUES (:tile, 'queued') "
                         "ON CONFLICT (tile) DO NOTHING"),
                    [{"tile": t} for t in missing],
                )
                await db.commit()
        return not missing and all(s == "done" for s in known.values())
    except Exception as e:
        logger.warning("open data: could not check areas: %s", e)
        return False


# ── Queries ─────────────────────────────────────────────────────────────────

async def _rows(lat: float, lng: float, section: str, max_m: float,
                min_m: float = 0.0, limit: int = 80) -> list[dict]:
    sql = f"""
        SELECT {_COLUMNS} FROM open_places
        WHERE section = :section
          AND ST_DWithin(location::geography,
                         ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :max_m)
          {"AND NOT ST_DWithin(location::geography, ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :min_m)" if min_m > 0 else ""}
        ORDER BY popularity_score DESC, distance_m
        LIMIT :limit
    """
    async with async_session() as db:
        rows = (await db.execute(text(sql), {
            "lat": lat, "lng": lng, "section": section,
            "max_m": float(max_m), "min_m": float(min_m), "limit": limit,
        })).all()
    return [_place_from_row(r) for r in rows]


def _merge(primary: list[dict], extra: list[dict]) -> list[dict]:
    """Primary first; extra places only when their name is not already there."""
    names = {(p.get("name") or "").strip().lower() for p in primary}
    out = list(primary)
    for p in extra:
        n = (p.get("name") or "").strip().lower()
        if n and n not in names:
            names.add(n)
            out.append(p)
    return out


async def _geoapify(lat: float, lng: float, section: str, radius_m: float) -> list[dict]:
    try:
        from app.services.settings_service import SettingsService
        async with async_session() as db:
            svc = SettingsService(db)
            await svc.load_settings()
            key = await svc.get_setting("geoapify_api_key")
    except Exception:
        key = None
    found = await geoapify_places.nearby(key or "", lat, lng, section, int(min(radius_m, 50000)))
    return [_place_from_geoapify(g) for g in found]


async def _google_allowed(user_id) -> bool:
    ok, _ = await spend_guard.allowed(user_id)
    return ok


async def _record(cache_key: str, n: int) -> None:
    try:
        async with telemetry.track("open_data", "nearby", cache_key=cache_key) as t:
            t.hit("database")
    except Exception:
        pass


# ── Place lists ─────────────────────────────────────────────────────────────

async def nearby(
    *, user_id, latitude: float, longitude: float, category: str, radius: int,
    limit: int = 20, offset: int = 0, max_photos: int = 1,
) -> Optional[PlacesNearbyResponse]:
    """Free-data answer for /places/nearby, or None for the Google backup."""
    from app.services.places_service import _format_response_places

    try:
        await ensure_tiles(latitude, longitude, radius)
        places = await _rows(latitude, longitude, category, radius, limit=max(80, limit + offset))
        if len(places) < MIN_PLACES:
            places = _merge(places, await _geoapify(latitude, longitude, category, radius))
        if len(places) < MIN_PLACES and await _google_allowed(user_id):
            return None
    except Exception as e:
        logger.warning("open data nearby failed, using Google method: %s", e)
        return None
    await _record(f"open:nb:{latitude:.3f}:{longitude:.3f}:{category}:{radius}", len(places))
    return PlacesNearbyResponse(
        places=_format_response_places(places, max_photos, limit, offset),
        cached=False, source="open",
    )


async def banded(
    *, user_id, latitude: float, longitude: float, category: str,
    max_bands: Optional[int] = None, per_band: Optional[int] = None, max_photos: int = 1,
) -> Optional[BandedPlacesResponse]:
    """Free-data answer for /places/nearby/banded (Around You, Discover)."""
    from app.services import banded_places_service, excluded_keyword_service

    try:
        bands = place_bands.bands_for(category)
        visible = bands[:max_bands] if max_bands else bands
        reach = visible[-1][1]
        await ensure_tiles(latitude, longitude, reach)
        pool: list[dict] = []
        for band_min, band_max in visible:
            pool += await _rows(latitude, longitude, category, band_max,
                                min_m=band_min, limit=PER_BAND_ROWS)
        if len(pool) < MIN_PLACES:
            pool = _merge(pool, await _geoapify(latitude, longitude, category, reach))
        if len(pool) < MIN_PLACES and await _google_allowed(user_id):
            return None
        keywords = await excluded_keyword_service.get_active_keywords()
        banded_places_service._tag_excluded(pool, keywords)
    except Exception as e:
        logger.warning("open data banded failed, using Google method: %s", e)
        return None
    await _record(f"open:band:{latitude:.3f}:{longitude:.3f}:{category}", len(pool))
    return banded_places_service._assemble(
        latitude, longitude, category, visible, pool, max_photos,
        cached_flag=False, source="open", per_band=per_band,
    )


# ── Place page ──────────────────────────────────────────────────────────────

def is_open_id(place_id: str) -> bool:
    return place_id.startswith("op_") or place_id.startswith("ga_")


async def details(place_id: str) -> Optional[dict]:
    """Place page for a free-data place: what we know, no Google call."""
    if place_id.startswith("ga_"):
        g = await geoapify_places.cached_place(place_id)
        if not g:
            return None
        hours = g.get("opening_hours_text")
        return _details_payload(
            place_id, g["name"], g.get("address"), g["latitude"], g["longitude"],
            phone=g.get("phone"), website=g.get("website"), section=g.get("section"),
            weekday_hours=[hours] if hours else [], credit=OSM_CREDIT,
        )
    raw_id = place_id[3:]
    async with async_session() as db:
        r = (await db.execute(text(
            "SELECT name, address, latitude, longitude, phone, website, social, section, "
            "category, wiki_views, our_points, popularity_score FROM open_places WHERE id = :id"
        ), {"id": raw_id})).first()
    if r is None:
        return None
    m = r._mapping
    await _count_open(raw_id)
    return _details_payload(
        place_id, m["name"], m["address"], m["latitude"], m["longitude"],
        phone=m["phone"], website=m["website"] or m["social"], section=m["section"],
        label=label_for(wiki_views=int(m["wiki_views"] or 0), our_points=int(m["our_points"] or 0),
                        score=int(m["popularity_score"] or 0)),
        credit=OVERTURE_CREDIT,
    )


def _details_payload(place_id, name, address, lat, lng, *, phone=None, website=None,
                     section=None, weekday_hours=None, label=None, credit=None) -> dict:
    return {
        "place_id": place_id,
        "id": place_id,
        "name": name,
        "address": address or "",
        "latitude": float(lat),
        "longitude": float(lng),
        "rating": 0.0,
        "user_ratings_total": 0,
        "photo_urls": [],
        "opening_hours": {},
        "weekday_hours": weekday_hours or [],
        "description": None,
        "reviews": [],
        "source": "open",
        "data_source": "open",
        "category_name": section,
        "phone": phone,
        "website": website,
        "popularity_label": label,
        "credit": credit,
    }


async def _count_open(raw_id: str) -> None:
    """Our users' points: place-page opens, folded in nightly."""
    try:
        await telemetry._get_redis().zincrby("open:opens", 1, raw_id)
    except Exception:
        pass
