"""Which country each explorer uses the app from, for the admin Explorers page.

The country comes from the IP address of the explorer's latest request to the
API (`api_events.client_ip`), looked up in DB-IP's free "IP to Country Lite"
list, kept in `ip_country_ranges`. It says where they are, not where they are
from: a traveller abroad shows the country they are visiting, a VPN its exit
country. What they are from is the nationality they can set in the app
(`users.preferences["nationality"]`), which the page shows beside it.

DB-IP Lite is CC BY 4.0, so the admin page credits DB-IP. A new edition comes
out at the start of each month; the worker loads it (a 4.6 MB download) once
it is published and keeps the previous one until then.
"""
from __future__ import annotations

import asyncio
import gzip
import io
import logging
import uuid
from datetime import datetime, timezone
from typing import Iterable, Optional

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session, engine
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

DOWNLOAD_URL = "https://download.db-ip.com/free/dbip-country-lite-{edition}.csv.gz"
# Which edition ("YYYY-MM") is in the table, in system_settings.
EDITION_KEY = "ip_country_edition"
CHECK_EVERY_S = 6 * 3600
# A real edition has about 730,000 ranges. Anything far smaller is a broken
# download, and loading it would wipe the countries off the page.
MIN_RANGES = 300_000

# Each explorer's latest IP address and the range it falls in. DB-IP marks
# reserved and private space "ZZ"; those count as unknown.
_LATEST_COUNTRY = """
    SELECT u.id AS user_id, r.country_code
    FROM users u
    CROSS JOIN LATERAL (
        SELECT e.client_ip FROM api_events e
        WHERE e.user_id = u.id AND e.client_ip IS NOT NULL
        ORDER BY e.ts DESC
        LIMIT 1
    ) last_ip
    CROSS JOIN LATERAL (
        SELECT c.ip_to, c.country_code FROM ip_country_ranges c
        WHERE c.ip_from <= last_ip.client_ip
        ORDER BY c.ip_from DESC
        LIMIT 1
    ) r
    WHERE r.ip_to >= last_ip.client_ip AND r.country_code <> 'ZZ'
"""


async def countries_for(db: AsyncSession, user_ids: Iterable[uuid.UUID]) -> dict[uuid.UUID, str]:
    """ISO country code per explorer; explorers with no known country are left out."""
    ids = [str(i) for i in user_ids]
    if not ids:
        return {}
    rows = await db.execute(
        text(_LATEST_COUNTRY + " AND u.id = ANY(CAST(:ids AS uuid[]))"), {"ids": ids}
    )
    return {r.user_id: r.country_code for r in rows}


async def country_counts(db: AsyncSession, exclude_user_id: uuid.UUID) -> list[tuple[str, int]]:
    """Explorers per country, most first, over every account but `exclude_user_id`."""
    rows = await db.execute(
        text(f"""
            SELECT country_code, count(*) AS n FROM ({_LATEST_COUNTRY} AND u.id <> :skip) x
            GROUP BY country_code ORDER BY n DESC, country_code
        """),
        {"skip": exclude_user_id},
    )
    return [(r.country_code, r.n) for r in rows]


async def loaded_edition(db: AsyncSession) -> Optional[str]:
    return (await SettingsService(db).get_setting_fresh(EDITION_KEY, "")) or None


def _previous_month(edition: str) -> str:
    year, month = map(int, edition.split("-"))
    year, month = (year, month - 1) if month > 1 else (year - 1, 12)
    return f"{year:04d}-{month:02d}"


async def load(edition: str) -> bool:
    """Replace the table with one edition. False when DB-IP has not published it."""
    async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:
        resp = await client.get(DOWNLOAD_URL.format(edition=edition))
    if resp.status_code == 404:
        return False
    resp.raise_for_status()
    data = gzip.decompress(resp.content)
    ranges = data.count(b"\n")
    if ranges < MIN_RANGES:
        raise ValueError(f"edition {edition} has only {ranges} ranges")

    # One transaction: the page keeps the old edition until the new one is in.
    async with engine.begin() as conn:
        await conn.execute(text("TRUNCATE ip_country_ranges"))
        raw = await conn.get_raw_connection()
        await raw.driver_connection.copy_to_table(
            "ip_country_ranges",
            # A file object: asyncpg reads plain bytes as a file *path*.
            source=io.BytesIO(data),
            columns=["ip_from", "ip_to", "country_code"],
            format="csv",
        )
    async with async_session() as db:
        await SettingsService(db).set_setting(
            EDITION_KEY, edition, "DB-IP country list loaded into ip_country_ranges"
        )
    logger.info("[ip-country] loaded DB-IP edition %s (%d ranges)", edition, ranges)
    return True


async def refresh_if_due() -> None:
    """Load this month's edition, or last month's while this one is not out."""
    current = datetime.now(timezone.utc).strftime("%Y-%m")
    async with async_session() as db:
        loaded = await loaded_edition(db) or ""
    for edition in (current, _previous_month(current)):
        if loaded >= edition:
            return
        if await load(edition):
            return


async def refresh_loop() -> None:
    """Worker loop: look a few times a day, download once a month."""
    while True:
        try:
            await refresh_if_due()
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("[ip-country] refresh failed: %s", str(e)[:300])
        await asyncio.sleep(CHECK_EVERY_S)
