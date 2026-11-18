"""Travellers' own ratings and reviews of map places (TL, 2026-11-18).

What a place card shows (`rating_source`), decided here so it can change
without an app release:
  - "google"     the place has a Google rating backed by at least one review;
  - "nexaround"  no Google rating, and at least OUR_STARS_MIN of our travellers
                 rated it;
  - None         neither: no stars (the popularity chip, if any).

Places are identified by the id the app uses (see models/place_review.py).
A place we hold in `attractions` can reach the app under its Google id or our
uuid, so reads look up both and writes store the Google id when there is one.
"""
from __future__ import annotations

import re
import time
import uuid
from typing import Iterable, Optional

from sqlalchemy import func, or_, select

from app.core.database import async_session
from app.models.attraction import Attraction
from app.models.place_review import PlaceReview
from app.services.experience_reviews import round_average

OUR_STARS_MIN = 3            # our ratings needed before a card shows our stars
MAX_NEW_PER_DAY = 20         # new reviews per traveller per UTC day (edits free)

PUBLISHED = "published"
HIDDEN = "hidden"
STATUSES = (PUBLISHED, HIDDEN)

_UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
# Google place ids, op_/ga_ free-data ids and uuids all fit this.
_PLACE_ID_RE = re.compile(r"^[A-Za-z0-9_\-:.]{3,255}$")


def valid_place_id(place_id: str) -> bool:
    return bool(_PLACE_ID_RE.match(place_id or ""))


def _is_uuid(place_id: str) -> bool:
    return bool(_UUID_RE.match(place_id or ""))


def _is_open_id(place_id: str) -> bool:
    return place_id.startswith("op_") or place_id.startswith("ga_")


def rating_source(rating, review_count, our_count) -> Optional[str]:
    """Which stars a card shows. A Google rating with no reviews behind it is
    the 4.0 placeholder our Google mapping fills in, not a rating."""
    if float(rating or 0) > 0 and int(review_count or 0) > 0:
        return "google"
    if int(our_count or 0) >= OUR_STARS_MIN:
        return "nexaround"
    return None


# ── Which keys a place's reviews live under ─────────────────────────────────

async def _candidate_keys(db, ids: Iterable[str]) -> dict[str, list[str]]:
    """Every key each place id's reviews may be stored under."""
    ids = [i for i in dict.fromkeys(str(i) for i in ids if i) if valid_place_id(i)]
    out: dict[str, list[str]] = {i: [i.lower() if _is_uuid(i) else i] for i in ids}
    uuids = [i for i in ids if _is_uuid(i)]
    google = [i for i in ids if not _is_uuid(i) and not _is_open_id(i)]
    if uuids:
        rows = await db.execute(
            select(Attraction.id, Attraction.google_place_id)
            .where(Attraction.id.in_([uuid.UUID(u) for u in uuids]))
        )
        by_uuid = {str(aid): gid for aid, gid in rows}
        for i in uuids:
            gid = by_uuid.get(i.lower())
            if gid:
                out[i].append(gid)
    if google:
        rows = await db.execute(
            select(Attraction.id, Attraction.google_place_id)
            .where(Attraction.google_place_id.in_(google))
        )
        for aid, gid in rows:
            if gid in out:
                out[gid].append(str(aid))
    return out


async def canonical_key(db, place_id: str) -> tuple[str, list[str]]:
    """The key a new review is stored under, and every key this place may
    already have reviews under. Our uuid becomes the place's Google id when we
    know it; a merged copy's old uuid becomes the kept row's."""
    if _is_uuid(place_id):
        from app.repositories.attraction_repository import AttractionRepository
        kept = await AttractionRepository(db).resolve_alias(uuid.UUID(place_id))
        if kept is not None:
            place_id = str(kept)
    keys = (await _candidate_keys(db, [place_id])).get(place_id) or [place_id]
    if _is_uuid(place_id) and len(keys) > 1:
        return keys[1], keys
    return keys[0], keys


# ── Averages ────────────────────────────────────────────────────────────────

# Lists are hot (Around You on every home open): while nobody has written a
# review yet there is nothing to look up, so skip the queries entirely.
_any_cache: dict = {"at": 0.0, "value": False}
_ANY_TTL_S = 60.0


async def _any_published() -> bool:
    """True once any review is published (then it stays true: an all-hidden
    table just answers the lookups with nothing). Rechecked every minute until
    then; each API process keeps its own copy."""
    if _any_cache["value"]:
        return True
    now = time.monotonic()
    if _any_cache["at"] and now - _any_cache["at"] < _ANY_TTL_S:
        return False
    async with async_session() as db:
        found = await db.scalar(
            select(PlaceReview.id).where(PlaceReview.status == PUBLISHED).limit(1)
        )
    _any_cache.update(at=now, value=found is not None)
    return _any_cache["value"]


def note_published() -> None:
    """A review was just published: lists start looking them up at once."""
    _any_cache.update(at=time.monotonic(), value=True)


async def summaries(ids: Iterable[str]) -> dict[str, tuple[Optional[float], int]]:
    """(average, count) of published reviews for each place id."""
    ids = [str(i) for i in ids if i]
    if not ids:
        return {}
    async with async_session() as db:
        cand = await _candidate_keys(db, ids)
        keys = {k for ks in cand.values() for k in ks}
        if not keys:
            return {}
        rows = await db.execute(
            select(PlaceReview.place_key, func.count(), func.sum(PlaceReview.rating))
            .where(PlaceReview.place_key.in_(keys), PlaceReview.status == PUBLISHED)
            .group_by(PlaceReview.place_key)
        )
        by_key = {k: (int(c), int(t or 0)) for k, c, t in rows}
    out: dict[str, tuple[Optional[float], int]] = {}
    for place_id, ks in cand.items():
        count = sum(by_key[k][0] for k in set(ks) if k in by_key)
        total = sum(by_key[k][1] for k in set(ks) if k in by_key)
        out[place_id] = (round_average(total, count), count)
    return out


async def stored_ratings(ids: Iterable[str]) -> dict[str, tuple[float, int]]:
    """The Google rating and rating count we saved for places (attractions),
    by the id the app uses: a Google id through `google_place_id`, our uuid
    directly. Since 2026-11-18 Google is not asked for ratings any more (TL),
    so this is where an existing place's rating comes from."""
    ids = [i for i in dict.fromkeys(str(i) for i in ids if i) if valid_place_id(i)]
    uuids = [i for i in ids if _is_uuid(i)]
    google = [i for i in ids if not _is_uuid(i) and not _is_open_id(i)]
    out: dict[str, tuple[float, int]] = {}
    if not uuids and not google:
        return out
    async with async_session() as db:
        if google:
            rows = await db.execute(
                select(Attraction.google_place_id, Attraction.rating, Attraction.review_count)
                .where(Attraction.google_place_id.in_(google),
                       Attraction.rating > 0, Attraction.review_count > 0)
            )
            for gid, rating, count in rows:
                out.setdefault(gid, (float(rating), int(count)))
        if uuids:
            rows = await db.execute(
                select(Attraction.id, Attraction.rating, Attraction.review_count)
                .where(Attraction.id.in_([uuid.UUID(u) for u in uuids]),
                       Attraction.rating > 0, Attraction.review_count > 0)
            )
            by_id = {str(aid): (float(r), int(c)) for aid, r, c in rows}
            for u in uuids:
                if u.lower() in by_id:
                    out[u] = by_id[u.lower()]
    return out


def _unrated(rating, count) -> bool:
    return float(rating or 0) <= 0 or int(count or 0) <= 0


async def attach(places: list[dict]) -> None:
    """Add our_rating, our_review_count and rating_source to place dicts, in
    place. Done before ranking so Around You's order uses them. A place
    without a rating gets the one we saved for it, if any."""
    need = [p for p in places if _unrated(p.get("rating"), p.get("review_count"))]
    if need:
        saved = await stored_ratings(str(p.get("id") or "") for p in need)
        for p in need:
            hit = saved.get(str(p.get("id") or ""))
            if hit:
                p["rating"], p["review_count"] = hit
    sums: dict = {}
    if places and await _any_published():
        sums = await summaries(str(p.get("id") or "") for p in places)
    for p in places:
        avg, count = sums.get(str(p.get("id") or ""), (None, 0))
        p["our_rating"] = avg
        p["our_review_count"] = count
        p["rating_source"] = rating_source(p.get("rating"), p.get("review_count"), count)
    # Photos go through the same pass: unsaved Google links out, approved
    # traveller photos in (services/place_photos).
    from app.services import place_photos
    await place_photos.attach(places)


async def attach_responses(places: list) -> None:
    """The same for PlaceResponse models (flat lists, already ranked)."""
    need = [p for p in places if _unrated(p.rating, p.review_count)]
    if need:
        saved = await stored_ratings(str(p.id) for p in need)
        for p in need:
            hit = saved.get(str(p.id))
            if hit:
                p.rating, p.review_count = hit
    sums: dict = {}
    if places and await _any_published():
        sums = await summaries(str(p.id) for p in places)
    for p in places:
        avg, count = sums.get(str(p.id), (None, 0))
        p.our_rating = avg
        p.our_review_count = count
        p.rating_source = rating_source(p.rating, p.review_count, count)
    from app.services import place_photos
    await place_photos.attach_responses(places)


# ── One place's reviews ─────────────────────────────────────────────────────

def place_reviews_query(keys: list[str]):
    return (
        select(PlaceReview)
        .where(PlaceReview.place_key.in_(keys), PlaceReview.status == PUBLISHED)
        .order_by(PlaceReview.created_at.desc())
    )


async def breakdown(db, keys: list[str]) -> dict:
    """Average, count and how many gave 5, 4, 3, 2 and 1 stars."""
    rows = await db.execute(
        select(PlaceReview.rating, func.count())
        .where(PlaceReview.place_key.in_(keys), PlaceReview.status == PUBLISHED)
        .group_by(PlaceReview.rating)
    )
    per_star = {int(r): int(c) for r, c in rows}
    count = sum(per_star.values())
    total = sum(r * c for r, c in per_star.items())
    return {
        "average": round_average(total, count),
        "count": count,
        "breakdown": [per_star.get(star, 0) for star in (5, 4, 3, 2, 1)],
    }


async def user_review(db, user_id, keys: list[str]) -> Optional[PlaceReview]:
    return await db.scalar(
        select(PlaceReview)
        .where(PlaceReview.user_id == user_id, PlaceReview.place_key.in_(keys))
        .order_by(PlaceReview.created_at.desc())
        .limit(1)
    )


def admin_search_clause(q: str):
    like = f"%{q.strip()}%"
    return or_(
        PlaceReview.place_name.ilike(like),
        PlaceReview.comment.ilike(like),
        PlaceReview.reviewer_name.ilike(like),
    )
