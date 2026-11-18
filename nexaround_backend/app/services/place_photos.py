"""Place photos without Google (TL, 2026-11-18).

Two jobs, run on every place list and place page (from `place_reviews.attach`
and the details route):

1. While Google photos are switched off, a Google photo link is kept only if
   that photo is already saved on our disk. Any other one would 404 in the app
   and show the category icon anyway, so it is dropped and the app sends no
   request for it.
2. A place left without a photo gets the newest photo a traveller sent for it
   that an admin approved, with `photo_credit` naming who took it.

Uploads are re-encoded to WebP (at most 1600 px, quality 80), which also drops
the phone's EXIF data, GPS position included.
"""
from __future__ import annotations

import io
import json
import os
import time
import uuid
from typing import Optional
from urllib.parse import parse_qs, urlsplit

from fastapi import HTTPException, status
from PIL import Image, ImageOps
from sqlalchemy import select

from app.core.database import async_session
from app.models.place_photo import PlacePhoto

PENDING = "pending"
APPROVED = "approved"
REJECTED = "rejected"
STATUSES = (PENDING, APPROVED, REJECTED)

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_UPLOADS_PER_DAY = 10
MAX_SIDE_PX = 1600
WEBP_QUALITY = 80
UPLOAD_DIR = "app/static/uploads/place_photos"
PUBLIC_PREFIX = "/static/uploads/place_photos"

_GOOGLE_PHOTO_PREFIX = "/api/v1/places/photo?"


def credit_for(uploader_name: str) -> str:
    return f"Photo: {uploader_name} · nexAround traveller"


# ── Saving an upload ────────────────────────────────────────────────────────

def save_upload(content: bytes) -> tuple[str, int, int, int]:
    """Decode, straighten, shrink and re-encode an image. Returns (public url,
    width, height, bytes). Raises 400 for anything that is not an image."""
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="The photo is larger than 10 MB.")
    try:
        img = Image.open(io.BytesIO(content))
        # A JPEG decodes straight at a reduced scale: a 48 MP phone photo
        # never has to sit in memory at full size.
        if img.format == "JPEG":
            img.draft("RGB", (MAX_SIDE_PX * 2, MAX_SIDE_PX * 2))
        img.load()
        img = ImageOps.exif_transpose(img)
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGB")
        img.thumbnail((MAX_SIDE_PX, MAX_SIDE_PX))
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="That file is not a photo we can read.")
    if min(img.size) < 200:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="The photo is too small. Please send a larger one.")
    out = io.BytesIO()
    img.save(out, format="WEBP", quality=WEBP_QUALITY, method=4)
    data = out.getvalue()
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    name = f"{uuid.uuid4()}.webp"
    with open(os.path.join(UPLOAD_DIR, name), "wb") as f:
        f.write(data)
    return f"{PUBLIC_PREFIX}/{name}", img.size[0], img.size[1], len(data)


def delete_file(url: Optional[str]) -> None:
    """Remove a stored photo. Only ever a file of ours, by its own name."""
    if not url or not url.startswith(PUBLIC_PREFIX + "/"):
        return
    name = os.path.basename(url)
    try:
        os.remove(os.path.join(UPLOAD_DIR, name))
    except FileNotFoundError:
        pass


# ── Google photo links ──────────────────────────────────────────────────────

def _google_photo_saved(url: str) -> bool:
    """Whether a /places/photo link points at a photo we already hold."""
    from app.services import photo_cache_service
    try:
        q = parse_qs(urlsplit(url).query)
        ref = (q.get("ref") or [""])[0]
        if not ref:
            return False
        index = int((q.get("i") or ["0"])[0] or 0)
        width = int((q.get("maxwidth") or ["800"])[0] or 800)
        path = photo_cache_service.cached_path(ref, width, index)
        return path.exists() and path.stat().st_size > 0
    except Exception:
        return False


def usable_photo_urls(urls: list[str], google_on: bool) -> list[str]:
    """Drop Google photo links the app could not load while photos are off."""
    if google_on or not urls:
        return list(urls or [])
    return [u for u in urls if not u.startswith(_GOOGLE_PHOTO_PREFIX) or _google_photo_saved(u)]


# ── Approved photos ─────────────────────────────────────────────────────────

_any_cache: dict = {"at": 0.0, "value": False}
_ANY_TTL_S = 60.0


async def _any_approved() -> bool:
    """True once any photo is approved; rechecked every minute until then."""
    if _any_cache["value"]:
        return True
    now = time.monotonic()
    if _any_cache["at"] and now - _any_cache["at"] < _ANY_TTL_S:
        return False
    async with async_session() as db:
        found = await db.scalar(
            select(PlacePhoto.id).where(PlacePhoto.status == APPROVED).limit(1)
        )
    _any_cache.update(at=now, value=found is not None)
    return _any_cache["value"]


def note_approved() -> None:
    _any_cache.update(at=time.monotonic(), value=True)


async def approved_for(ids: list[str]) -> dict[str, PlacePhoto]:
    """The newest approved photo for each place id that has one."""
    from app.services.place_reviews import _candidate_keys
    ids = [str(i) for i in ids if i]
    if not ids:
        return {}
    async with async_session() as db:
        cand = await _candidate_keys(db, ids)
        keys = {k for ks in cand.values() for k in ks}
        if not keys:
            return {}
        rows = (await db.scalars(
            select(PlacePhoto)
            .where(PlacePhoto.place_key.in_(keys), PlacePhoto.status == APPROVED,
                   PlacePhoto.url.isnot(None))
            .order_by(PlacePhoto.created_at.desc())
        )).all()
    newest: dict[str, PlacePhoto] = {}
    for r in rows:
        newest.setdefault(r.place_key, r)
    out: dict[str, PlacePhoto] = {}
    for place_id, ks in cand.items():
        found = [newest[k] for k in ks if k in newest]
        if found:
            out[place_id] = max(found, key=lambda r: r.created_at)
    return out


async def _google_on() -> bool:
    from app.services import plan_service
    try:
        return await plan_service.google_photos_enabled()
    except Exception:
        return True


async def _credit_shown() -> bool:
    """Whether this app build prints the photo credit under the photo. Photos
    whose licence asks for a credit (most Wikipedia ones, Unsplash) show only
    on those builds."""
    from app.core import request_context
    from app.services import plan_service
    from app.services.open_data import sections
    try:
        minimum = await plan_service.photo_credit_min_version()
    except Exception:
        return False
    return sections.version_at_least(request_context.app_version_var.get(), minimum)


async def _found(ids: list[str]) -> dict[str, Optional[dict]]:
    """Wikipedia / Unsplash answers by place id: a dict, None for "looked up,
    nothing found", and no entry for "never looked up"."""
    from app.services import open_photos
    if not ids:
        return {}
    try:
        values = await open_photos._r().mget([open_photos.result_key(i) for i in ids])
    except Exception:
        return {}
    out: dict[str, Optional[dict]] = {}
    for place_id, raw in zip(ids, values):
        if raw is None:
            continue
        text = raw.decode() if isinstance(raw, bytes) else raw
        out[place_id] = None if text == "none" else json.loads(text)
    return out


async def _fill(items: list[dict]) -> None:
    """The photo for each place, in the TL's order (2026-11-18):
      1. a Google photo already on our disk (photos stay off),
      2. Wikipedia / Unsplash (services/open_photos),
      3. a traveller's photo an admin approved,
      4. none: the app shows its category icon.
    `items` are plain dicts: id, name, lat, lng, section, reviews, photo_urls,
    photo_credit. Places never looked up go to the background lookup queue."""
    from app.services import open_photos
    google_on = await _google_on()
    empty = []
    for it in items:
        it["photo_urls"] = usable_photo_urls(it.get("photo_urls") or [], google_on)
        it.setdefault("photo_credit", None)
        if not it["photo_urls"] and it.get("id"):
            empty.append(it)
    if not empty:
        return

    found = await _found([it["id"] for it in empty])
    credit_ok = await _credit_shown()
    still = []
    for it in empty:
        hit = found.get(it["id"])
        if hit and hit.get("url") and (credit_ok or not hit.get("needs_credit", True)):
            it["photo_urls"] = [hit["url"]]
            it["photo_credit"] = hit.get("credit")
        else:
            still.append(it)

    if still and await _any_approved():
        approved = await approved_for([it["id"] for it in still])
        rest = []
        for it in still:
            photo = approved.get(it["id"])
            if photo:
                it["photo_urls"] = [photo.url]
                it["photo_credit"] = credit_for(photo.uploader_name)
            else:
                rest.append(it)
        still = rest

    never_asked = [
        {"id": it["id"], "name": it.get("name") or "", "lat": it.get("lat"),
         "lng": it.get("lng"), "section": it.get("section"),
         "reviews": int(it.get("reviews") or 0)}
        for it in empty
        if it["id"] not in found and it.get("name") and it.get("lat") is not None
        and it.get("lng") is not None
    ]
    if never_asked:
        await open_photos.enqueue(never_asked[:40])


def _item(pid, name, lat, lng, section, reviews, urls) -> dict:
    return {"id": str(pid or ""), "name": name, "lat": lat, "lng": lng,
            "section": section, "reviews": reviews, "photo_urls": list(urls or [])}


async def attach(places: list[dict]) -> None:
    """Place dicts (Around You / Discover pools), in place."""
    items = [
        _item(p.get("id"), p.get("name"), p.get("latitude"), p.get("longitude"),
              p.get("category_name"), p.get("review_count"), p.get("photo_urls"))
        for p in places
    ]
    await _fill(items)
    for p, it in zip(places, items):
        p["photo_urls"] = it["photo_urls"]
        p["photo_credit"] = it.get("photo_credit")


async def attach_responses(places: list) -> None:
    """PlaceResponse models (flat lists)."""
    items = [
        _item(p.id, p.name, p.latitude, p.longitude, p.category_name,
              p.review_count, p.photo_urls)
        for p in places
    ]
    await _fill(items)
    for p, it in zip(places, items):
        p.photo_urls = it["photo_urls"]
        p.photo_credit = it.get("photo_credit")


async def attach_details(place_id: str, details: dict, *, name=None, lat=None, lng=None) -> None:
    """The place page."""
    it = _item(
        place_id, details.get("name") or name,
        details.get("latitude", lat), details.get("longitude", lng),
        details.get("category_name") or details.get("category"),
        details.get("user_ratings_total") or details.get("review_count"),
        details.get("photo_urls"),
    )
    await _fill([it])
    details["photo_urls"] = it["photo_urls"]
    details["photo_credit"] = it.get("photo_credit")
