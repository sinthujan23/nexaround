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
from app.services import google_places_client


_CACHE_DIR = Path("app/static/photo_cache")
_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _safe_name(photo_reference: str, maxwidth: int) -> str:
    # photo_references can be hundreds of chars; hash to a stable short name.
    h = hashlib.sha256(f"{photo_reference}:{maxwidth}".encode()).hexdigest()
    return f"{h}.jpg"


def cached_path(photo_reference: str, maxwidth: int) -> Path:
    return _CACHE_DIR / _safe_name(photo_reference, maxwidth)


# Lock per filename so a thundering herd doesn't fetch the same photo twice.
_locks: dict[str, asyncio.Lock] = {}


def _lock_for(name: str) -> asyncio.Lock:
    lock = _locks.get(name)
    if lock is None:
        lock = asyncio.Lock()
        _locks[name] = lock
    return lock


async def get_or_fetch(photo_reference: str, maxwidth: int = 800) -> Optional[Path]:
    """Return the local cached file path. Downloads from Google on first hit."""
    path = cached_path(photo_reference, maxwidth)
    if path.exists() and path.stat().st_size > 0:
        return path

    name = path.name
    async with _lock_for(name):
        # Re-check inside the lock — another coroutine may have just written it.
        if path.exists() and path.stat().st_size > 0:
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
