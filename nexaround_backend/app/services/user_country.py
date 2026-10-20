"""Which country a traveller is standing in, from their coordinates.

The Travel Stories feed uses it to put TravelBytes about the traveller's own
country first. The answer comes from Geoapify's reverse geocoder, the same
service that names the place at the top of the app, and is kept in Redis on a
~5 km grid for 30 days: borders don't move, and most feed loads come from a
few places, so almost every lookup is a cache hit.
"""
import logging
from typing import Optional

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.rate_limiter import get_redis_client
from app.services import telemetry
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

_GRID_DEG = 0.05  # ≈ 5.5 km
_TTL_SECONDS = 30 * 24 * 60 * 60
# Cached for a point that is in no country (open sea). A failed lookup is not
# cached, so the next feed load tries again.
_NO_COUNTRY = "-"
# The feed waits for this, so a slow answer is dropped rather than waited on:
# the TravelBytes then fall back to newest first.
_TIMEOUT_S = 4.0


def cache_key(lat: float, lng: float) -> str:
    def snap(value: float) -> float:
        return round(value / _GRID_DEG) * _GRID_DEG
    return f"country_at:{snap(lat):.2f}:{snap(lng):.2f}"


async def country_at(db: AsyncSession, lat: float, lng: float) -> Optional[str]:
    """ISO 3166-1 alpha-2 code ("CN") of the country at (lat, lng), or None
    when it can't be told. Never raises: the feed must load without it."""
    key = cache_key(lat, lng)
    redis = await get_redis_client()
    try:
        async with telemetry.track(
            "geoapify", "geocode_reverse", sku="geoapify_reverse", cache_key=key,
        ) as t:
            if redis:
                hit = await redis.get(key)
                if hit is not None:
                    t.hit("redis")
                    return None if hit == _NO_COUNTRY else hit

            api_key = await SettingsService(db).get_setting("geoapify_api_key")
            if not api_key:
                return None
            async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
                resp = await client.get(
                    "https://api.geoapify.com/v1/geocode/reverse",
                    params={"lat": lat, "lon": lng, "apiKey": api_key, "format": "json", "lang": "en"},
                )
                t.upstream(resp)
            resp.raise_for_status()
            results = resp.json().get("results") or []
            code = ((results[0].get("country_code") if results else None) or "").upper()

            if redis:
                await redis.set(key, code or _NO_COUNTRY, ex=_TTL_SECONDS)
            return code or None
    except Exception as e:
        logger.warning("Country lookup for the stories feed failed: %s", e)
        return None
