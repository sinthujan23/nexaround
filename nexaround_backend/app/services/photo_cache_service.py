"""On-disk cache for Place Photo bytes.

The first request for a given (photo_reference, maxwidth) hits Google and
writes the bytes under app/static/photo_cache/. Subsequent requests are
served by FastAPI's static handler — Google is never called again.

For now we don't evict; tourist photo sets are small (~10k photos × 100KB
= 1GB). When that becomes a problem, add a cron that prunes by atime.
"""
import asyncio
import hashlib
import os
from pathlib import Path
from typing import Optional
from app.services import google_places_client, telemetry


_CACHE_DIR = Path("app/static/photo_cache")
_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _stable_identity(photo_reference: str, index: int) -> str:
    """The part of a photo reference that survives a refetch.

    Places API (New) mints a *fresh token per response*, so the reference as a
    whole names one reply, not one photo: ask for the same place twice and the
    same image comes back under two different names. Keyed on that, the cache
    could never hit twice — every refetch re-keyed every image to a filename
    nothing had ever written, which is why 6k cached photos were serving a 16%
    hit rate and most places fell through to their category placeholder.

    What does hold is the place and the photo's position within it. Verified
    rather than assumed: photo[0] fetched through two independently obtained
    references returned byte-identical data.
    """
    if photo_reference.startswith("places/") and "/photos/" in photo_reference:
        place_id = photo_reference.split("/", 2)[1]
        return f"{place_id}#{index}"
    # Legacy bare references were stable, and rows still carry ~4k of them, so
    # they stay keyed on themselves and keep hitting the files already on disk.
    return photo_reference


def _safe_name(photo_reference: str, maxwidth: int, index: int = 0) -> str:
    # References run to hundreds of chars; hash the stable identity to a short name.
    h = hashlib.sha256(
        f"{_stable_identity(photo_reference, index)}:{maxwidth}".encode()
    ).hexdigest()
    return f"{h}.jpg"


def cached_path(photo_reference: str, maxwidth: int, index: int = 0) -> Path:
    return _CACHE_DIR / _safe_name(photo_reference, maxwidth, index)


# Lock per filename so a thundering herd doesn't fetch the same photo twice.
_locks: dict[str, asyncio.Lock] = {}


def _lock_for(name: str) -> asyncio.Lock:
    lock = _locks.get(name)
    if lock is None:
        lock = asyncio.Lock()
        _locks[name] = lock
    return lock


async def get_or_fetch(
    photo_reference: str, maxwidth: int = 800, index: int = 0
) -> Optional[Path]:
    """Return the local cached file path. Downloads from Google on first hit."""
    path = cached_path(photo_reference, maxwidth, index)
    # Grouped on the stable identity too, so the dashboard counts one photo
    # once instead of once per token it has ever been handed out under.
    cache_key = f"photo:{_stable_identity(photo_reference, index)}:{maxwidth}"
    if path.exists() and path.stat().st_size > 0:
        # ~99% of photo requests land here. Recording them is what turns the
        # disk cache from invisible into the strongest number on the dashboard.
        async with telemetry.track("internal", "place_photo", cache_key=cache_key) as t:
            t.hit("disk")
        return path

    name = path.name
    async with _lock_for(name):
        # Re-check inside the lock — another coroutine may have just written it.
        if path.exists() and path.stat().st_size > 0:
            async with telemetry.track("internal", "place_photo", cache_key=cache_key) as t:
                t.hit("disk")
            return path
        try:
            data, _ctype = await google_places_client.fetch_photo_bytes(
                photo_reference, maxwidth=maxwidth
            )
        except Exception:
            return None
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, path)
    return path
