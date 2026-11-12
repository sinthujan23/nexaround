"""Download one 0.5-degree area of Overture places into `open_places`.

Runs only in the `openimport` container (512 MB, half a CPU core), never in the
api or the worker: DuckDB reads Overture's GeoParquet straight from its public
S3 bucket, fetching only the row groups inside the area. Measured 2026-11-12 on
Da Nang / Hoi An: 82 s, 194 MB peak memory, 2.4 s of CPU, 23,160 places before
filtering.
"""
from __future__ import annotations

import logging
import os
import re
import time
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.services.open_data import sections
from app.services.open_data.score import popularity_score

logger = logging.getLogger(__name__)

BUCKET = "overturemaps-us-west-2"
_LIST_URL = f"https://{BUCKET}.s3.us-west-2.amazonaws.com/?list-type=2&prefix=release/&delimiter=/"
MIN_CONFIDENCE = 0.5

# DuckDB limits: well inside the container's 512 MB, one thread so the import
# never competes for both of the host's cores. Spills to disk if it must.
DUCKDB_MEMORY = os.environ.get("OPEN_DATA_DUCKDB_MEMORY", "300MB")
DUCKDB_TEMP = os.environ.get("OPEN_DATA_DUCKDB_TEMP", "/tmp/duckdb")

_release_cache: tuple[float, str] = (0.0, "")


async def latest_release() -> str:
    """Newest Overture release folder, e.g. '2026-10-21.0' (cached 6 hours)."""
    global _release_cache
    at, value = _release_cache
    if value and time.time() - at < 6 * 3600:
        return value
    async with httpx.AsyncClient(timeout=30) as c:
        r = await c.get(_LIST_URL)
        r.raise_for_status()
    found = sorted(set(re.findall(r"<Prefix>release/(\d{4}-\d{2}-\d{2}\.\d+)/</Prefix>", r.text)))
    if not found:
        raise RuntimeError("no Overture release found")
    _release_cache = (time.time(), found[-1])
    return found[-1]


def _clean(v, n: int) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip()
    if not s or s.lower() in ("unnamed", "none", "null"):
        return None
    return s[:n]


def _address(addr) -> Optional[str]:
    if not isinstance(addr, dict):
        return None
    parts = [_clean(addr.get("freeform"), 300), _clean(addr.get("locality"), 120),
             _clean(addr.get("region"), 80)]
    seen, out = set(), []
    for p in parts:
        if p and p.lower() not in seen:
            seen.add(p.lower())
            out.append(p)
    return ", ".join(out)[:500] if out else None


def fetch_tile(tile: str, release: str) -> list[dict]:
    """Blocking: the tile's places, filtered and mapped to our sections.
    Call from a thread (asyncio.to_thread)."""
    import duckdb  # only installed where imports run

    lat0, lng0, lat1, lng1 = sections.tile_bbox(tile)
    os.makedirs(DUCKDB_TEMP, exist_ok=True)
    con = duckdb.connect()
    try:
        con.execute(f"SET memory_limit='{DUCKDB_MEMORY}'")
        con.execute("SET threads=1")
        con.execute(f"SET temp_directory='{DUCKDB_TEMP}'")
        con.execute("LOAD httpfs")
        con.execute("SET s3_region='us-west-2'")
        tops = ", ".join(f"'{t}'" for t in sections.IMPORT_TOP_LEVELS)
        rows = con.execute(f"""
            SELECT id, names.primary, basic_category, taxonomy.hierarchy, confidence,
                   websites[1], phones[1], socials[1], brand.names.primary,
                   addresses[1], (bbox.ymin + bbox.ymax) / 2, (bbox.xmin + bbox.xmax) / 2
            FROM read_parquet('s3://{BUCKET}/release/{release}/theme=places/type=place/*')
            WHERE bbox.xmin >= ? AND bbox.xmin < ? AND bbox.ymin >= ? AND bbox.ymin < ?
              AND confidence >= ?
              AND names.primary IS NOT NULL
              AND (operating_status IS NULL OR operating_status = 'open')
              AND taxonomy.hierarchy[1] IN ({tops})
        """, [lng0, lng1, lat0, lat1, MIN_CONFIDENCE]).fetchall()
    finally:
        con.close()

    out = []
    for (pid, name, basic, hier, conf, web, phone, social, brand, addr, lat, lng) in rows:
        section = sections.section_for(hier, basic)
        name = _clean(name, 255)
        if not section or not name or lat is None or lng is None:
            continue
        web, phone, social = _clean(web, 500), _clean(phone, 64), _clean(social, 500)
        brand = _clean(brand, 120)
        country = None
        if isinstance(addr, dict) and addr.get("country"):
            country = str(addr["country"])[:2].upper()
        out.append({
            "id": str(pid)[:64], "name": name, "section": section,
            "category": _clean(basic, 64), "latitude": float(lat), "longitude": float(lng),
            "address": _address(addr), "country": country,
            "phone": phone, "website": web, "social": social, "brand": brand,
            "confidence": float(conf or 0.0),
            "popularity_score": popularity_score(
                confidence=conf, website=web, phone=phone, social=social, brand=brand,
            ),
            "tile": tile, "release": release,
        })
    return out


_UPSERT = """
INSERT INTO open_places (id, name, section, category, latitude, longitude, location,
    address, country, phone, website, social, brand, confidence, popularity_score,
    tile, release, imported_at)
VALUES (:id, :name, :section, :category, :latitude, :longitude,
    ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326),
    :address, :country, :phone, :website, :social, :brand, :confidence,
    :popularity_score, :tile, :release, now())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, section = EXCLUDED.section, category = EXCLUDED.category,
    latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, location = EXCLUDED.location,
    address = EXCLUDED.address, country = EXCLUDED.country, phone = EXCLUDED.phone,
    website = EXCLUDED.website, social = EXCLUDED.social, brand = EXCLUDED.brand,
    confidence = EXCLUDED.confidence,
    -- keep our users' points and Wikipedia readers across refreshes
    popularity_score = LEAST(100, EXCLUDED.popularity_score + open_places.our_points),
    tile = EXCLUDED.tile, release = EXCLUDED.release, imported_at = now()
"""


async def save_tile(db, tile: str, release: str, places: list[dict]) -> int:
    """Upsert the tile's places and drop ones the new release no longer has."""
    from sqlalchemy import text

    for i in range(0, len(places), 500):
        await db.execute(text(_UPSERT), places[i:i + 500])
    await db.execute(
        text("DELETE FROM open_places WHERE tile = :t AND release <> :r"),
        {"t": tile, "r": release},
    )
    return len(places)


async def import_tile(tile: str) -> tuple[int, str, float]:
    """Download and save one tile. Returns (places, release, seconds)."""
    import asyncio
    from app.core.database import async_session

    release = await latest_release()
    t0 = time.time()
    places = await asyncio.to_thread(fetch_tile, tile, release)
    async with async_session() as db:
        n = await save_tile(db, tile, release, places)
        await db.commit()
    return n, release, round(time.time() - t0, 1)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)
