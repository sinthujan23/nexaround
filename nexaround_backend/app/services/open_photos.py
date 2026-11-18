"""Free photos for places without one: Wikipedia, then Unsplash (TL, 2026-11-18).

Order a place's photo is chosen in (services/place_photos.attach):
  1. a Google photo already saved on our disk (no new Google photos are bought),
  2. a photo found here — Wikipedia (the place's own article picture), else
     Unsplash (famous sights only, and only when the photo's caption names the
     place, so a café never gets some other café's picture),
  3. a photo a traveller sent and an admin approved,
  4. nothing: the app's category icon (and its "Add a photo" button).

Looked up in the background worker, never while a traveller waits: a list that
has places without a photo queues them, and the next load shows what was found.
Every answer, "nothing found" included, is kept in Redis for 30 days.

Wikipedia is asked once per ~2 km area (one geosearch, every article picture
in it) and places are matched to articles by name within 400 m, so a whole
neighbourhood costs a few requests, not one per place. Unsplash has a small
hourly allowance (our key is on the Demo level: 50 an hour, shared with trip
cover photos), so it is kept for famous sights.

Credits: Wikipedia pictures are mostly CC BY-SA and Unsplash asks for the
photographer's name, so those show only on app builds that print the credit
under the photo (`photo_credit_min_app_version`). Public-domain and CC0
pictures show on every build.
"""
from __future__ import annotations

import asyncio
import html
import json
import logging
import math
import re
import time
import unicodedata
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.services import telemetry

logger = logging.getLogger(__name__)

SIGHT_SECTIONS = {"Attractions", "POI", "Nature", "Experiences", "Beach"}
UNSPLASH_PER_HOUR = 30            # of the Demo key's 50; trip covers use the rest
UNSPLASH_MIN_REVIEWS = 500        # "famous": Google reviews behind the sight
MATCH_RADIUS_M = 400
CELL_DEG = 0.02                   # Wikipedia area: ~2.2 km
CELL_RADIUS_M = 2000
FOUND_TTL = 30 * 24 * 3600
NONE_TTL = 30 * 24 * 3600
QUEUE_KEY = "pphoto:queue"
QUEUED_KEY = "pphoto:queued:"     # + place id, a short-lived "already queued"
MAX_QUEUE = 5000

USER_AGENT = "nexAroundPlacePhotos/1.0 (https://nexaround.com)"
WIKI_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
UNSPLASH_SEARCH = "https://api.unsplash.com/search/photos"

_FREE_LICENCES = ("public domain", "cc0", "pd")
_BUSINESS_WORDS = {
    "hotel", "hotels", "resort", "inn", "hostel", "villa", "villas", "restaurant",
    "cafe", "bar", "pub", "shop", "store", "market", "mall", "apartments", "lodge",
    "guesthouse", "spa", "club", "suites", "bungalow",
}


def _r():
    return telemetry._get_redis()


def result_key(place_id: str) -> str:
    return f"pphoto:v1:{place_id}"


# ── Names ───────────────────────────────────────────────────────────────────

def normalize(name: str) -> str:
    """Lowercase, accents off, punctuation and brackets out: "Galle Fort (Sri
    Lanka)" and "galle fort" compare equal."""
    text = re.sub(r"\(.*?\)", " ", name or "")
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9 ]+", " ", text.lower())
    return re.sub(r"\s+", " ", text).strip()


def _core(name: str) -> str:
    """The name without its qualifier: "Galle Fort, Sri Lanka" -> "galle fort"."""
    return normalize((name or "").split(",")[0])


def names_match(place: str, other: str) -> bool:
    """Exactly the same name, qualifiers aside. Containment is not enough:
    "Galle Fort" must not get the "Galle Fort Hotel" article's picture, nor
    the hotel the fort's (found live on 2026-11-18)."""
    a, b = _core(place), _core(other)
    return bool(a) and a == b


def _distance_m(lat1, lng1, lat2, lng2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def needs_credit(licence: Optional[str]) -> bool:
    lic = (licence or "").strip().lower()
    return not any(lic.startswith(f) for f in _FREE_LICENCES)


def _plain(text: Optional[str], limit: int = 80) -> str:
    """Commons' Artist field is HTML; keep the words."""
    clean = html.unescape(re.sub(r"<[^>]+>", "", text or "")).strip()
    return re.sub(r"\s+", " ", clean)[:limit]


# ── Queue (filled by place lists, emptied by the worker) ────────────────────

async def enqueue(places: list[dict]) -> None:
    """Queue places that have no photo and were never looked up."""
    if not places:
        return
    try:
        r = _r()
        if await r.llen(QUEUE_KEY) >= MAX_QUEUE:
            return
        pipe = r.pipeline()
        for p in places:
            pipe.set(QUEUED_KEY + p["id"], "1", ex=6 * 3600, nx=True)
        fresh = await pipe.execute()
        items = [json.dumps(p) for p, ok in zip(places, fresh) if ok]
        if items:
            await r.lpush(QUEUE_KEY, *items)
    except Exception as e:
        logger.info("photo lookup queue unavailable: %s", e)


# ── Wikipedia ───────────────────────────────────────────────────────────────

_wiki_pause_until = 0.0


async def _wiki_get(client: httpx.AsyncClient, url: str, params: dict, op: str) -> Optional[dict]:
    global _wiki_pause_until
    if time.monotonic() < _wiki_pause_until:
        return None
    async with telemetry.track("wikipedia", op) as t:
        resp = await client.get(url, params=params)
        t.upstream(resp)
    if resp.status_code == 429:
        # Asked to slow down: stop for a quarter of an hour.
        _wiki_pause_until = time.monotonic() + 900
        logger.warning("wikipedia asked us to slow down; pausing photo lookups 15 min")
        return None
    if resp.status_code != 200:
        return None
    await asyncio.sleep(1.0)       # a polite one request a second
    return resp.json()


async def _area_articles(client: httpx.AsyncClient, lat: float, lng: float) -> Optional[list[dict]]:
    """Every article with a picture around this ~2 km cell, cached 30 days."""
    clat = round(round(lat / CELL_DEG) * CELL_DEG, 4)
    clng = round(round(lng / CELL_DEG) * CELL_DEG, 4)
    key = f"pphoto:wiki:{clat}:{clng}"
    try:
        cached = await _r().get(key)
        if cached:
            return json.loads(cached)
    except Exception:
        pass
    articles: list[dict] = []
    params = {
        "action": "query", "format": "json", "formatversion": "2",
        "generator": "geosearch", "ggscoord": f"{clat}|{clng}",
        "ggsradius": CELL_RADIUS_M, "ggslimit": 100,
        "prop": "pageimages|coordinates", "piprop": "thumbnail|name",
        "pithumbsize": 800, "pilimit": 50, "colimit": 50,
    }
    for _ in range(4):               # up to ~200 articles with continuation
        data = await _wiki_get(client, WIKI_API, params, "geosearch")
        if data is None:
            return None              # paused or failed: try again later
        for page in (data.get("query") or {}).get("pages") or []:
            thumb = (page.get("thumbnail") or {}).get("source")
            coords = (page.get("coordinates") or [{}])[0]
            if thumb and page.get("pageimage") and coords.get("lat") is not None:
                articles.append({
                    "title": page.get("title") or "",
                    "lat": coords["lat"], "lng": coords["lon"],
                    "thumb": thumb, "file": page["pageimage"],
                })
        if "continue" not in data:
            break
        params = {**params, **data["continue"]}
    try:
        await _r().set(key, json.dumps(articles), ex=FOUND_TTL)
    except Exception:
        pass
    return articles


async def _licence(client: httpx.AsyncClient, file_name: str) -> tuple[Optional[str], str]:
    """(licence, author) of a Commons / Wikipedia file."""
    data = await _wiki_get(client, COMMONS_API, {
        "action": "query", "format": "json", "formatversion": "2",
        "titles": f"File:{file_name}", "prop": "imageinfo",
        "iiprop": "extmetadata", "iiextmetadatafilter": "LicenseShortName|Artist",
    }, "file_licence")
    pages = ((data or {}).get("query") or {}).get("pages") or []
    meta = ((pages[0].get("imageinfo") or [{}])[0].get("extmetadata") or {}) if pages else {}
    licence = (meta.get("LicenseShortName") or {}).get("value")
    author = _plain((meta.get("Artist") or {}).get("value")) or "Unknown"
    return licence, author


class TryLater(Exception):
    """Wikipedia could not be asked (paused or failing): look again later
    rather than remembering "no photo" for a month."""


async def from_wikipedia(client: httpx.AsyncClient, place: dict) -> Optional[dict]:
    articles = await _area_articles(client, place["lat"], place["lng"])
    if articles is None:
        raise TryLater()
    if not articles:
        return None
    best = None
    for a in articles:
        if not names_match(place["name"], a["title"]):
            continue
        d = _distance_m(place["lat"], place["lng"], a["lat"], a["lng"])
        if d <= MATCH_RADIUS_M and (best is None or d < best[0]):
            best = (d, a)
    if best is None:
        return None
    article = best[1]
    if time.monotonic() < _wiki_pause_until:
        raise TryLater()
    licence, author = await _licence(client, article["file"])
    if licence is None:
        return None                # unknown licence: not shown
    return {
        "source": "wikipedia", "url": article["thumb"],
        "credit": f"Photo: {author} / Wikimedia Commons, {licence}"[:160],
        "needs_credit": needs_credit(licence),
    }


# ── Unsplash ────────────────────────────────────────────────────────────────

async def _unsplash_allowed() -> bool:
    key = f"pphoto:unsplash:{datetime.now(timezone.utc):%Y%m%d%H}"
    try:
        used = await _r().incr(key)
        await _r().expire(key, 7200)
        return used <= UNSPLASH_PER_HOUR
    except Exception:
        return False


async def from_unsplash(client: httpx.AsyncClient, place: dict, api_key: str) -> Optional[dict]:
    if not api_key or place.get("section") not in SIGHT_SECTIONS:
        return None
    if int(place.get("reviews") or 0) < UNSPLASH_MIN_REVIEWS:
        return None
    if not await _unsplash_allowed():
        return None
    async with telemetry.track("unsplash", "place_photo_search", sku="unsplash_photo") as t:
        resp = await client.get(UNSPLASH_SEARCH, params={
            "query": place["name"], "per_page": 5, "orientation": "landscape",
            "client_id": api_key,
        })
        t.upstream(resp)
    if resp.status_code != 200:
        return None
    name = normalize(place["name"])
    if len(name) < 6:
        return None
    for photo in resp.json().get("results") or []:
        caption = normalize(f"{photo.get('description') or ''} {photo.get('alt_description') or ''}")
        # The place's whole name, as words, in the photographer's caption, and
        # not as part of a business's name ("Galle Fort Hotel").
        padded = f" {caption} "
        if f" {name} " not in padded:
            continue
        following = padded.split(f" {name} ", 1)[1].split(" ", 1)[0]
        if following in _BUSINESS_WORDS:
            continue
        url = (photo.get("urls") or {}).get("regular")
        if not url:
            continue
        # Unsplash asks to be told when one of its photos is put to use.
        download = (photo.get("links") or {}).get("download_location")
        if download:
            try:
                await client.get(download, params={"client_id": api_key})
            except Exception:
                pass
        user = (photo.get("user") or {}).get("name") or "Unsplash photographer"
        return {
            "source": "unsplash", "url": url,
            "credit": f"Photo: {user} on Unsplash"[:160],
            "needs_credit": True,
        }
    return None


# ── The worker loop ─────────────────────────────────────────────────────────

MAX_TRIES = 3
_key_cache: dict = {"at": 0.0, "value": ""}


async def _unsplash_key() -> str:
    """The Unsplash key from Admin > Settings, read every 10 minutes."""
    if time.monotonic() - _key_cache["at"] < 600:
        return _key_cache["value"]
    from app.core.database import async_session
    from app.services.settings_service import SettingsService
    try:
        async with async_session() as db:
            value = await SettingsService(db).get_setting("unsplash_api_key") or ""
    except Exception:
        value = _key_cache["value"]
    _key_cache.update(at=time.monotonic(), value=value)
    return value


async def lookup(client: httpx.AsyncClient, place: dict, unsplash_key: str) -> Optional[dict]:
    """Wikipedia first, then Unsplash. Raises TryLater when Wikipedia could not
    be asked."""
    found = await from_wikipedia(client, place)
    if found is None:
        found = await from_unsplash(client, place, unsplash_key)
    return found


async def _store(place_id: str, found: Optional[dict]) -> None:
    await _r().set(
        result_key(place_id),
        json.dumps(found) if found else "none",
        ex=FOUND_TTL if found else NONE_TTL,
    )


async def lookup_loop() -> None:
    """Empty the queue one place at a time, about one request a second."""
    async with httpx.AsyncClient(timeout=10, headers={"User-Agent": USER_AGENT}) as client:
        while True:
            try:
                if time.monotonic() < _wiki_pause_until:
                    await asyncio.sleep(30)
                    continue
                item = await _r().brpop(QUEUE_KEY, timeout=30)
                if not item:
                    continue
                raw = item[1]
                place = json.loads(raw.decode() if isinstance(raw, bytes) else raw)
                try:
                    found = await lookup(client, place, await _unsplash_key())
                except TryLater:
                    place["tries"] = int(place.get("tries") or 0) + 1
                    if place["tries"] < MAX_TRIES:
                        await _r().lpush(QUEUE_KEY, json.dumps(place))
                    continue
                await _store(place["id"], found)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.warning("photo lookup failed: %s", e)
                await asyncio.sleep(5)
