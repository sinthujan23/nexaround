"""Keep places that are not live out of every list the app receives.

Hiding a row in the database is not enough on its own. Place lists are cached
in Redis for 14 days per tile, each api process also keeps its own in-memory
copy (`place_cache_service._mem_cache`, consulted on a Redis miss), and several
paths hand Google results straight to the client without looking at our table
at all. Deleting cache keys cannot reach all of that: a place sits in every
tile, radius and category around it, so the keys cannot be listed.

So lists are filtered as they are served instead. Each process holds a small
snapshot of what must not be shown:

  ids    every attraction id whose status is not live
  gids   Google place ids of hidden/rejected rows, so the place's Google twin
         is dropped too. Not for pending rows: the old duplicate copies are
         pending, and their Google ids belong to places that are live.
  grid   hidden/rejected rows with no Google id, matched against Google
         results by the seeders' 25 m + name rule

A status change calls `bump()`, which increments a counter in Redis. Every
process checks that counter at most every few seconds and reloads when it
moves, so a hide reaches the app within seconds without any key deletion.
"""
import asyncio
import re
import time
from dataclasses import dataclass, field
from typing import Iterable, Optional

from sqlalchemy import text

from app.core.database import async_session
from app.services import place_cache_service
from app.utils.place_match import is_same_place

VERSION_KEY = "places:visibility:v"

# How often a process asks Redis whether the snapshot changed.
_CHECK_INTERVAL_S = 3.0
# Reload regardless, in case a bump was lost.
_MAX_AGE_S = 300.0
# With Redis unreachable there is no version to watch; reload on a timer.
_NO_REDIS_RELOAD_S = 60.0

# ~110 m cells. A 25 m match only ever needs the 3x3 block around a point.
_CELL_DEG = 0.001

_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)


@dataclass(frozen=True)
class Snapshot:
    ids: frozenset = frozenset()
    gids: frozenset = frozenset()
    grid: dict = field(default_factory=dict)


EMPTY = Snapshot()


def _cell(lat: float, lng: float) -> tuple:
    return (int(lat // _CELL_DEG), int(lng // _CELL_DEG))


def build_snapshot(rows: Iterable) -> Snapshot:
    """Build the snapshot from non-live rows.

    Each row: (id, google_place_id, status, lat, lng, name, gid_has_live_row).
    """
    ids, gids, grid = set(), set(), {}
    for rid, gid, status, lat, lng, name, gid_has_live in rows:
        ids.add(str(rid))
        if status not in ("hidden", "rejected"):
            continue
        if gid:
            if not gid_has_live:
                gids.add(gid)
        elif lat is not None and lng is not None and name:
            grid.setdefault(_cell(lat, lng), []).append((lat, lng, name))
    return Snapshot(frozenset(ids), frozenset(gids), grid)


def is_hidden(snap: Snapshot, place: dict) -> bool:
    pid = str(place.get("id") or "")
    if pid in snap.ids or pid in snap.gids:
        return True
    if not snap.grid or _UUID_RE.match(pid):
        # Our own rows are covered by `ids`; only Google results need the
        # proximity match.
        return False
    lat, lng = place.get("latitude"), place.get("longitude")
    name = place.get("name") or ""
    if lat is None or lng is None or not name:
        return False
    cy, cx = _cell(lat, lng)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            for hlat, hlng, hname in snap.grid.get((cy + dy, cx + dx), ()):
                if is_same_place(lat, lng, name, hlat, hlng, hname):
                    return True
    return False


def filter_with(snap: Snapshot, places: list) -> list:
    """`places` without the hidden ones. Accepts dicts or pydantic models."""
    if not snap.ids and not snap.gids and not snap.grid:
        return places
    out = []
    for p in places:
        d = p if isinstance(p, dict) else p.model_dump()
        if not is_hidden(snap, d):
            out.append(p)
    return out


_snapshot: Optional[Snapshot] = None
_loaded_version: Optional[str] = None
_loaded_at = 0.0
_checked_at = 0.0
_lock: Optional[asyncio.Lock] = None
# Held so the task cannot be garbage-collected mid-flight.
_refresh_task: Optional[asyncio.Task] = None


async def _read_version() -> Optional[str]:
    try:
        return await place_cache_service._get_client().get(VERSION_KEY) or "0"
    except Exception as e:
        print(f"⚠️ visibility version read failed: {e}")
        return None


async def _load() -> Snapshot:
    async with async_session() as session:
        # Pending rows only contribute their id, so the per-row columns and the
        # live-twin lookup are computed for hidden/rejected rows alone (CASE
        # evaluates lazily). With tens of thousands of pending copies that is
        # the difference between ~1 s and a fraction of it per reload.
        rows = (await session.execute(text("""
            SELECT a.id,
                   CASE WHEN a.status IN ('hidden', 'rejected') THEN a.google_place_id END,
                   a.status,
                   CASE WHEN a.status IN ('hidden', 'rejected') THEN ST_Y(a.location) END,
                   CASE WHEN a.status IN ('hidden', 'rejected') THEN ST_X(a.location) END,
                   CASE WHEN a.status IN ('hidden', 'rejected') THEN a.name END,
                   CASE WHEN a.status IN ('hidden', 'rejected') AND a.google_place_id IS NOT NULL
                        THEN EXISTS (
                            SELECT 1 FROM attractions l
                            WHERE l.google_place_id = a.google_place_id
                              AND l.status = 'live'
                        )
                        ELSE false
                   END
            FROM attractions a
            WHERE a.status <> 'live'
        """))).all()
    return build_snapshot(rows)


def _fresh(now: float) -> bool:
    return (
        _snapshot is not None
        and now - _checked_at < _CHECK_INTERVAL_S
        and now - _loaded_at < _MAX_AGE_S
    )


async def _refresh() -> None:
    """Ask Redis whether another process changed a status; reload if so."""
    global _snapshot, _loaded_version, _loaded_at, _checked_at
    now = time.monotonic()
    _checked_at = now
    version = await _read_version()
    stale = (
        _snapshot is None
        or now - _loaded_at >= _MAX_AGE_S
        or (version is not None and version != _loaded_version)
        or (version is None and now - _loaded_at >= _NO_REDIS_RELOAD_S)
    )
    if not stale:
        return
    try:
        _snapshot = await _load()
        _loaded_version = version
        _loaded_at = now
    except Exception as e:
        # Fail open: our own queries already filter on status, so the cost is
        # only that a hidden place's Google twin may show until the next load.
        print(f"⚠️ visibility snapshot load failed: {e}")
        if _snapshot is None:
            _snapshot = EMPTY


async def current() -> Snapshot:
    """This process's snapshot.

    A request never waits for a reload while a snapshot is held: it is served
    the one we have, and the refresh runs behind it. Only a process that has
    no snapshot yet (just started) waits for the first load.
    """
    global _lock, _refresh_task
    if _fresh(time.monotonic()):
        return _snapshot
    if _snapshot is not None:
        if _refresh_task is None or _refresh_task.done():
            _refresh_task = asyncio.create_task(_refresh())
        return _snapshot
    if _lock is None:
        _lock = asyncio.Lock()
    async with _lock:
        if _snapshot is None:
            await _refresh()
    return _snapshot


async def filter_places(places: list) -> list:
    return filter_with(await current(), places)


async def _incr_version() -> None:
    await place_cache_service._get_client().incr(VERSION_KEY)


async def bump() -> None:
    """Tell every process the set of non-live places changed.

    This process marks its own snapshot out of date, so its next request starts
    a reload; the others notice the counter within a few seconds.
    """
    global _loaded_at, _checked_at
    _loaded_at = float("-inf")
    _checked_at = float("-inf")
    try:
        await _incr_version()
    except Exception as e:
        print(f"⚠️ visibility bump failed: {e}")
