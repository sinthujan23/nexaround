"""One cover photo per destination, looked up once, shown everywhere.

Two callers want a cover for an Odyssey: the itinerary list, which fills one
in while the plan is still generating so the card is not blank, and the
generation itself, which stamps one onto the finished plan. They used to make
two *independent* calls to Unsplash's `/photos/random` — random being the
operative word — so the picture a user watched for forty seconds was replaced
by a different one the moment the plan landed.

Where the photo comes from, and why in this order:

  1. Google Places — a photo attached to the destination's own place_id.
     Correct by construction: the resolver (already run and cached by the
     generator) says *which* place, and Google returns photos *of that place*.
     Works for a village as well as a capital. Unsplash was tried first and
     could not be made reliable: its search is fuzzy, so "Kattankudy" returned
     2,321 photos of cats, "Sri Vijaya Puram" a cat, and there is no location
     field on a result to check it against. It also 404s on no match and
     allows 50 requests an hour on this key.
  2. Unsplash, for the *country* only, when Google has no photo of the place.
     A country name is the one query Unsplash cannot misread, and a Sri Lanka
     photo on a Sri Lankan trip is right, if generic.

Cached by destination in Redis for 30 days (misses for 6 hours). The list
poll fires within 5 s of the placeholder being saved and generation finishes
35–120 s later, so the second lookup is a cache hit: one resolution per
destination per month, whichever caller gets there first.
"""
import logging
from typing import Optional
from urllib.parse import quote

import httpx

from app.core.config import settings
from app.services import (
    geo_resolver,
    google_places_client,
    photo_cache_service,
    place_cache_service,
    telemetry,
)

logger = logging.getLogger(__name__)

_CACHE_TTL = 30 * 24 * 3600      # a cover, once found, is stable
_NEGATIVE_TTL = 6 * 3600         # nothing found — worth retrying, not hourly
_MISS = "__none__"               # sentinel; a real value is always a URL
# v1 held /photos/random picks, v2 Unsplash name searches (the cats). Both
# are left to expire; nothing reads them.
_KEY_VERSION = "v3"

# Width the cover is fetched and served at. The list card is ~360 dp wide and
# the app decodes it at 1080 px for 3x screens, so this is the size that is
# actually shown; the URL names the same width so the anonymous image request
# finds the file the pre-warm wrote.
_PLACE_PHOTO_WIDTH = 1080

_UNSPLASH_SEARCH_URL = "https://api.unsplash.com/search/photos"


def _key(destination: str) -> str:
    return f"cover:{_KEY_VERSION}:{destination.strip().lower()}"


def _pick_photo(refs: list[dict]) -> int:
    """Index of the photo to use: the largest landscape one, else the first.

    A landscape frame fills the card; a portrait one is cropped to a sliver.
    Among landscapes, resolution is the best cheap proxy for "someone took
    this on purpose" over "snapped it from the car".
    """
    best, best_px = None, -1
    for i, r in enumerate(refs):
        if r["width"] >= r["height"] and r["width"] * r["height"] > best_px:
            best, best_px = i, r["width"] * r["height"]
    return best if best is not None else 0


async def _google_place_cover(destination: str) -> tuple[str, Optional[geo_resolver.DestinationContext]]:
    """Google's photo of the place. Returns (url, resolved context) so the
    fallback can reuse the resolution rather than pay for it twice."""
    geo = await geo_resolver.resolve_destination(destination)
    if not geo.place_id:
        return "", geo
    refs = await google_places_client.fetch_place_photo_refs(geo.place_id)
    if not refs:
        return "", geo
    pick = _pick_photo(refs)
    ref = refs[pick]["name"]
    # Through the same disk cache `/places/photo` serves from, so the app's
    # anonymous image load — which can never reach Google — finds it there.
    path = await photo_cache_service.get_or_fetch(ref, maxwidth=_PLACE_PHOTO_WIDTH, index=pick)
    if path is None:
        return "", geo
    base = settings.PUBLIC_BASE_URL.rstrip("/")
    url = f"{base}/api/v1/places/photo?ref={quote(ref, safe='')}&i={pick}&maxwidth={_PLACE_PHOTO_WIDTH}"
    return url, geo


async def _unsplash_country_cover(country: str, api_key: str) -> str:
    """Top relevant Unsplash photo for a country name. "" if none or on error."""
    if not api_key or not country:
        return ""
    params = {
        "query": country,
        "orientation": "landscape",
        "per_page": 1,
        "order_by": "relevant",
        "content_filter": "high",
        "client_id": api_key,
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            async with telemetry.track(
                "unsplash", "cover_photo_search",
                sku="unsplash_photo", cache_key=_key(country),
            ) as t:
                response = await client.get(_UNSPLASH_SEARCH_URL, params=params)
                t.upstream(response)
        if response.status_code != 200:
            logger.error("Unsplash search %r returned %s: %s",
                         country, response.status_code, response.text[:200])
            return ""
        data = response.json()
        results = data.get("results") if isinstance(data, dict) else None
        if not results:
            return ""
        return str(((results[0] or {}).get("urls") or {}).get("regular") or "")
    except Exception as e:
        logger.error("Unsplash country cover failed for %r: %s", country, e)
        return ""


async def fetch_cover_photo(destination: str, unsplash_api_key: str = "") -> str:
    """Uncached lookup. Returns an absolute image URL, or "" if there is none."""
    destination = (destination or "").strip()
    if not destination:
        return ""
    geo = None
    try:
        url, geo = await _google_place_cover(destination)
        if url:
            return url
    except Exception as e:
        logger.warning("Google place cover failed for %r: %s", destination, e)
    country = geo.country if geo is not None else ""
    if country and country.lower() != destination.lower():
        return await _unsplash_country_cover(country, unsplash_api_key)
    # The destination *is* a country with no Google photo — rare, but the
    # country query is still the right one.
    return await _unsplash_country_cover(destination, unsplash_api_key)


async def cover_for_destination(destination: str, unsplash_api_key: str = "") -> str:
    """Resolve a destination to a cover URL through the shared cache.

    Caching the miss is the important half: an itinerary whose destination has
    no photo would otherwise be re-looked-up on every list poll, forever.
    Destinations repeat heavily across users, so the cache is shared, not
    per-user — two people's Dubai trips get the same skyline, which is the
    intent.
    """
    destination = (destination or "").strip()
    if not destination:
        return ""
    key = _key(destination)
    cached = await place_cache_service.get_raw(key)
    if cached is not None:
        return "" if cached == _MISS else cached

    url = await fetch_cover_photo(destination, unsplash_api_key)
    await place_cache_service.set_raw(
        key, url or _MISS, ttl=_CACHE_TTL if url else _NEGATIVE_TTL,
    )
    return url
