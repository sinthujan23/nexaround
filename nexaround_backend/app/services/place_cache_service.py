"""Redis-backed cache for Google Places responses.

The cache key snaps coordinates to a ~500m grid so users browsing the same
neighborhood share a single cached result. With Sri Lanka's tourist hot-spots
being highly concentrated, one cache entry serves many requests for 7 days.
"""
import json
import math
from typing import Optional
import redis.asyncio as aioredis
from app.core.config import settings


# 0.005° ≈ 555m at the equator. Sri Lanka is near the equator so the
# longitudinal degree-to-meters factor stays close to that.
_GRID_DEG = 0.005

# 7 days. Popular places don't churn weekly.
_TTL_SECONDS = 7 * 24 * 60 * 60


_redis: Optional[aioredis.Redis] = None


def _get_client() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis


def _snap(value: float) -> str:
    """Snap a coordinate to the grid, return a stable string for the key."""
    snapped = math.floor(value / _GRID_DEG) * _GRID_DEG
    return f"{snapped:.4f}"


def build_key(lat: float, lng: float, category: Optional[str], radius: int) -> str:
    cat = (category or "all").replace(" ", "_").replace("&", "and").lower()
    return f"places:nearby:{_snap(lat)}:{_snap(lng)}:{cat}:r{radius}"


async def get_cached(key: str) -> Optional[list[dict]]:
    """Return the cached place list or None on miss."""
    try:
        raw = await _get_client().get(key)
        if raw is None:
            return None
        return json.loads(raw)
    except Exception:
        # Cache is best-effort. A bad redis state must never fail a user request.
        return None


async def set_cached(key: str, places: list[dict]) -> None:
    try:
        await _get_client().set(key, json.dumps(places), ex=_TTL_SECONDS)
    except Exception:
        pass
