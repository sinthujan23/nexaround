"""The `openimport` container: downloads free map data one area at a time.

    python -m app.open_data_worker

Runs alone in its own container (512 MB, half a CPU core) so an import can
never take memory or CPU from the api or the Odyssey worker. Before every area
it checks the host and waits instead of importing when:
  - free memory is under OPEN_DATA_MIN_FREE_MB (500 MB),
  - the disk is over OPEN_DATA_MAX_DISK_PCT (90 %) full,
  - the free-data table is over OPEN_DATA_MAX_GB (5 GB).

Also, once a day: folds our users' place-page opens into the score, and
re-queues areas older than 30 days when Overture has a newer release.
"""
from __future__ import annotations

import asyncio
import logging
import os
import shutil
import signal
import time
from datetime import datetime, timezone

from sqlalchemy import text

from app.core.database import async_session
from app.services import telemetry
from app.services.open_data import overture_import

logging.basicConfig(level=logging.INFO, format="%(asctime)s openimport %(levelname)s %(message)s", force=True)
logger = logging.getLogger("openimport")

MIN_FREE_MB = int(os.environ.get("OPEN_DATA_MIN_FREE_MB", "500"))
MAX_DISK_PCT = float(os.environ.get("OPEN_DATA_MAX_DISK_PCT", "90"))
MAX_TABLE_GB = float(os.environ.get("OPEN_DATA_MAX_GB", "5"))
MAX_ATTEMPTS = 3
IDLE_SLEEP = 15
BUSY_SLEEP = 300

_stop = asyncio.Event()


def mem_available_mb() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) // 1024
    except Exception:
        pass
    return 0


def disk_used_pct(path: str = "/") -> float:
    u = shutil.disk_usage(path)
    return 100.0 * u.used / u.total if u.total else 100.0


async def table_gb() -> float:
    async with async_session() as db:
        n = (await db.execute(text("SELECT pg_total_relation_size('open_places')"))).scalar()
    return float(n or 0) / 1024 ** 3


async def safe_to_import() -> tuple[bool, str]:
    free = mem_available_mb()
    if free < MIN_FREE_MB:
        return False, f"free memory {free} MB < {MIN_FREE_MB} MB"
    disk = disk_used_pct()
    if disk > MAX_DISK_PCT:
        return False, f"disk {disk:.0f}% > {MAX_DISK_PCT:.0f}%"
    size = await table_gb()
    if size > MAX_TABLE_GB:
        return False, f"free-data table {size:.2f} GB > {MAX_TABLE_GB} GB"
    return True, ""


async def claim_next() -> str | None:
    async with async_session() as db:
        tile = (await db.execute(text("""
            UPDATE open_areas SET status = 'importing', attempts = attempts + 1
            WHERE tile = (
                SELECT tile FROM open_areas WHERE status = 'queued'
                ORDER BY requested_at LIMIT 1 FOR UPDATE SKIP LOCKED
            )
            RETURNING tile
        """))).scalar()
        await db.commit()
    return tile


async def finish(tile: str, *, n: int = 0, release: str | None = None,
                 seconds: float | None = None, error: str | None = None) -> None:
    async with async_session() as db:
        if error is None:
            await db.execute(text("""
                UPDATE open_areas SET status = 'done', places_count = :n, release = :r,
                    seconds = :s, error = NULL, imported_at = now()
                WHERE tile = :t
            """), {"t": tile, "n": n, "r": release, "s": seconds})
        else:
            await db.execute(text("""
                UPDATE open_areas SET
                    status = CASE WHEN attempts >= :max THEN 'failed' ELSE 'queued' END,
                    error = :e, requested_at = now()
                WHERE tile = :t
            """), {"t": tile, "e": error[:2000], "max": MAX_ATTEMPTS})
        await db.commit()


async def recover_interrupted() -> None:
    """An area left 'importing' by a restart goes back in the queue."""
    async with async_session() as db:
        await db.execute(text("""
            UPDATE open_areas SET status = CASE WHEN attempts >= :max THEN 'failed' ELSE 'queued' END
            WHERE status = 'importing'
        """), {"max": MAX_ATTEMPTS})
        await db.commit()


# ── Once a day ──────────────────────────────────────────────────────────────

async def fold_in_our_users() -> int:
    """Place-page opens → our_points (1 open = 1 point, max 10), then decay the
    counts so they reflect roughly the last three months."""
    r = telemetry._get_redis()
    items = await r.zrange("open:opens", 0, -1, withscores=True)
    if not items:
        return 0
    rows = []
    for member, count in items:
        pid = member.decode() if isinstance(member, bytes) else str(member)
        rows.append({"id": pid, "p": int(min(10, round(count)))})
    async with async_session() as db:
        for i in range(0, len(rows), 500):
            await db.execute(text("""
                UPDATE open_places SET
                    popularity_score = LEAST(100, GREATEST(0,
                        popularity_score - our_points + :p)),
                    our_points = :p
                WHERE id = :id
            """), rows[i:i + 500])
        await db.commit()
    # Keep ~3 months of memory: 0.975 ** 90 ≈ 0.1.
    await r.zunionstore("open:opens", {"open:opens": 0.975})
    await r.zremrangebyscore("open:opens", 0, 0.5)
    return len(rows)


async def requeue_stale() -> int:
    release = await overture_import.latest_release()
    async with async_session() as db:
        n = (await db.execute(text("""
            UPDATE open_areas SET status = 'queued', attempts = 0, requested_at = now()
            WHERE status = 'done' AND release <> :r AND imported_at < now() - interval '30 days'
        """), {"r": release})).rowcount
        await db.commit()
    return n or 0


async def daily(last_day: str) -> str:
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if today == last_day or datetime.now(timezone.utc).hour < 2:
        return last_day
    try:
        logger.info("daily: our users' points for %d places", await fold_in_our_users())
        logger.info("daily: %d areas queued for the new Overture release", await requeue_stale())
    except Exception as e:
        logger.warning("daily jobs failed: %s", e)
    return today


# ── Loop ────────────────────────────────────────────────────────────────────

async def main() -> None:
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _stop.set)
    await recover_interrupted()
    logger.info("started (min free %d MB, max disk %.0f%%, max table %.1f GB)",
                MIN_FREE_MB, MAX_DISK_PCT, MAX_TABLE_GB)
    last_day = ""
    while not _stop.is_set():
        try:
            last_day = await daily(last_day)
            ok, why = await safe_to_import()
            if not ok:
                logger.info("waiting: %s", why)
                await _sleep(BUSY_SLEEP)
                continue
            tile = await claim_next()
            if not tile:
                await _sleep(IDLE_SLEEP)
                continue
            t0 = time.time()
            try:
                n, release, secs = await overture_import.import_tile(tile)
                await finish(tile, n=n, release=release, seconds=secs)
                logger.info("area %s: %d places in %.0f s", tile, n, secs)
            except Exception as e:
                await finish(tile, error=f"{type(e).__name__}: {e}")
                logger.warning("area %s failed after %.0f s: %s", tile, time.time() - t0, e)
                await _sleep(30)
        except Exception as e:
            logger.warning("loop error: %s", e)
            await _sleep(60)
    logger.info("stopped")


async def _sleep(seconds: float) -> None:
    try:
        await asyncio.wait_for(_stop.wait(), timeout=seconds)
    except asyncio.TimeoutError:
        pass


if __name__ == "__main__":
    asyncio.run(main())
