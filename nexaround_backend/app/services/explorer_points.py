"""Explorer Points and levels (TL, 2026-11-20).

Travellers earn points for helping others (rating places, writing reviews,
adding photos) and for finishing trips. Points raise their level, and the
level shows next to their name on reviews and photos.

Almost everything is worked out from the rows themselves, never stored, so it
corrects itself: a hidden or deleted review, a rejected or taken-down photo,
or an Odyssey moved back from "completed" simply stops counting.

  - place_reviews (published): stars, plus more for a written / long review;
  - place_photos (approved): per photo, plus a Trailblazer bonus for the first
    photo of a place that showed only its category icon;
  - itineraries (status completed): Odysseys, and Mini Tours (the app saves
    each tour as an itinerary row with a `mini_tour_meta` item);
  - explorer_point_events: only what the server cannot see itself, i.e. the
    one-time carry-over of the old phone-only XP.

Totals are cached in Redis for a few minutes and dropped by `bust()` after
any change. Every number and line of text the app shows comes from here
(`info()`), so they can change without an app release.
"""
from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from typing import Iterable, Optional

from sqlalchemy import text

logger = logging.getLogger(__name__)

# ── The ladder ──────────────────────────────────────────────────────────────

# (name, points needed, tagline). Short on purpose: "Lv 5 · Pirate" sits on
# one line next to a reviewer's name.
LEVELS: list[tuple[str, int, str]] = [
    ("Sofanaut", 0, "Exploring the world from the sofa"),
    ("Sniffer", 15, "Nose to the pavement, sniffing out spots"),
    ("Snackster", 50, "Will travel for street food"),
    ("Snaphawk", 120, "Spots the perfect shot from a mile away"),
    ("Pirate", 250, "Plunders passport stamps in every port"),
    ("Jetninja", 500, "Strikes in any time zone"),
    ("Mapwiz", 1000, "Never lost. Never asks for directions"),
    ("Globzilla", 2000, "Eats continents for breakfast"),
    ("Pinlord", 4000, "Commands an army of map pins"),
    ("Atlasaurus", 8000, "A legend older than maps"),
]
MAX_LEVEL = len(LEVELS)
# The badge drawn with each level's name.
BADGES = ["🛋️", "👃", "🍜", "📸", "🏴‍☠️", "🥷", "🧙", "🦖", "👑", "🦕"]

# ── Points ──────────────────────────────────────────────────────────────────

RATING = 2                 # stars only
WRITTEN = 8                # + a review of WRITTEN_CHARS or more
DETAILED = 10              # + a review of DETAILED_CHARS or more
WRITTEN_CHARS = 30
DETAILED_CHARS = 200
PHOTO = 15                 # a photo an admin approved
TRAILBLAZER = 10           # + the first photo of a place with no photo at all
ODYSSEY = 25               # an Odyssey marked completed
MINI_TOUR = 10             # a Mini Tour finished with MINI_TOUR_MIN_STOPS+
MINI_TOUR_MIN_STOPS = 3
MINI_TOURS_PER_DAY = 3     # more than this in one UTC day earn nothing
CARRY_OVER_CAP = 300       # old phone XP brought over, once

EVENT_CARRY_OVER = "carry_over"
PUSH_TYPE = "explorer_points"

_CACHE_TTL_S = 600


def review_points(rating: Optional[int], comment: Optional[str]) -> int:
    """What one published review is worth."""
    if not rating:
        return 0
    length = len((comment or "").strip())
    pts = RATING
    if length >= WRITTEN_CHARS:
        pts += WRITTEN
    if length >= DETAILED_CHARS:
        pts += DETAILED
    return pts


def photo_points(trailblazer: bool) -> int:
    return PHOTO + (TRAILBLAZER if trailblazer else 0)


def carry_over_points(old_xp: int, trip_points: int) -> int:
    """The old phone XP came from Mini Tours and Odysseys, which the server now
    counts itself, so the carry-over only tops a traveller up to what they had
    (up to the cap) instead of counting those trips twice."""
    return max(0, min(int(old_xp or 0), CARRY_OVER_CAP) - max(0, int(trip_points or 0)))


@dataclass
class LevelInfo:
    level: int
    name: str
    badge: str
    tagline: str
    min_points: int
    next_level: Optional[int]
    next_name: Optional[str]
    next_min_points: Optional[int]
    points_to_next: int
    progress: float          # 0..1 through the current level; 1.0 at the top

    def as_dict(self) -> dict:
        return dict(self.__dict__)


def level_number(points: int) -> int:
    n = 1
    for i, (_, need, _) in enumerate(LEVELS):
        if points >= need:
            n = i + 1
    return n


def level_for(points: int) -> LevelInfo:
    points = max(0, int(points or 0))
    n = level_number(points)
    name, need, tagline = LEVELS[n - 1]
    if n >= MAX_LEVEL:
        return LevelInfo(n, name, BADGES[n - 1], tagline, need, None, None, None, 0, 1.0)
    next_name, next_need, _ = LEVELS[n]
    span = next_need - need
    return LevelInfo(
        n, name, BADGES[n - 1], tagline, need, n + 1, next_name, next_need,
        next_need - points, round((points - need) / span, 4) if span else 1.0,
    )


def level_name(n: int) -> str:
    return LEVELS[max(1, min(MAX_LEVEL, n)) - 1][0]


# ── Totals ──────────────────────────────────────────────────────────────────

@dataclass
class Totals:
    ratings: int = 0
    written: int = 0            # reviews of WRITTEN_CHARS+
    detailed: int = 0           # reviews of DETAILED_CHARS+
    photos: int = 0             # approved
    trailblazers: int = 0       # approved, first photo of the place
    photos_pending: int = 0
    pending_trailblazers: int = 0
    odysseys: int = 0
    mini_tours: int = 0
    bonus: int = 0              # carry-over (events)
    carried_over: bool = False

    @property
    def review_points(self) -> int:
        return self.ratings * RATING + self.written * WRITTEN + self.detailed * DETAILED

    @property
    def photo_points(self) -> int:
        return self.photos * PHOTO + self.trailblazers * TRAILBLAZER

    @property
    def trip_points(self) -> int:
        return self.odysseys * ODYSSEY + self.mini_tours * MINI_TOUR

    @property
    def total(self) -> int:
        return self.review_points + self.photo_points + self.trip_points + self.bonus

    @property
    def pending_points(self) -> int:
        return self.photos_pending * PHOTO + self.pending_trailblazers * TRAILBLAZER

    def as_cache(self) -> dict:
        return dict(self.__dict__)


_REVIEWS_SQL = text(f"""
    SELECT user_id,
           count(*) AS ratings,
           count(*) FILTER (WHERE char_length(btrim(coalesce(comment, ''))) >= {WRITTEN_CHARS}) AS written,
           count(*) FILTER (WHERE char_length(btrim(coalesce(comment, ''))) >= {DETAILED_CHARS}) AS detailed
    FROM place_reviews
    WHERE status = 'published' AND user_id = ANY(:ids)
    GROUP BY user_id
""")

_PHOTOS_SQL = text("""
    SELECT user_id,
           count(*) FILTER (WHERE status = 'approved') AS photos,
           count(*) FILTER (WHERE status = 'approved' AND trailblazer) AS trailblazers,
           count(*) FILTER (WHERE status = 'pending') AS pending,
           count(*) FILTER (WHERE status = 'pending' AND trailblazer) AS pending_trailblazers
    FROM place_photos
    WHERE user_id = ANY(:ids)
    GROUP BY user_id
""")

# A Mini Tour is saved several times while it runs (each check-in, then the
# finish), so rows are folded by the app's tour id; its best visited count
# decides whether it counts, and only MINI_TOURS_PER_DAY a day count.
_TRIPS_SQL = text(f"""
    WITH done AS (
        SELECT id, user_id, created_at, items::jsonb AS j
        FROM itineraries
        WHERE status = 'completed' AND user_id = ANY(:ids)
    ),
    ody AS (
        SELECT user_id, count(*) AS n
        FROM done
        WHERE j @> '[{{"kind": "odyssey_meta"}}]'::jsonb
        GROUP BY user_id
    ),
    tours AS (
        SELECT user_id,
               min(created_at) AS at,
               max(CASE WHEN (j->0->>'visited_count') ~ '^[0-9]+$'
                        THEN (j->0->>'visited_count')::int ELSE 0 END) AS visited
        FROM done
        WHERE jsonb_typeof(j) = 'array' AND j->0->>'kind' = 'mini_tour_meta'
        GROUP BY user_id, coalesce(nullif(j->0->>'tour_id', ''), id::text)
    ),
    ranked AS (
        SELECT user_id,
               row_number() OVER (
                   PARTITION BY user_id, (at AT TIME ZONE 'UTC')::date ORDER BY at
               ) AS rn
        FROM tours
        WHERE visited >= {MINI_TOUR_MIN_STOPS}
    ),
    mt AS (
        SELECT user_id, count(*) AS n FROM ranked
        WHERE rn <= {MINI_TOURS_PER_DAY} GROUP BY user_id
    )
    SELECT coalesce(ody.user_id, mt.user_id) AS user_id,
           coalesce(ody.n, 0) AS odysseys, coalesce(mt.n, 0) AS mini_tours
    FROM ody FULL OUTER JOIN mt ON mt.user_id = ody.user_id
""")

_EVENTS_SQL = text("""
    SELECT user_id, coalesce(sum(points), 0) AS points,
           bool_or(kind = :carry) AS carried
    FROM explorer_point_events
    WHERE user_id = ANY(:ids)
    GROUP BY user_id
""")


async def _compute(db, user_ids: list[uuid.UUID]) -> dict[uuid.UUID, Totals]:
    out = {u: Totals() for u in user_ids}
    if not user_ids:
        return out
    params = {"ids": list(user_ids)}
    for row in (await db.execute(_REVIEWS_SQL, params)).mappings():
        t = out[row["user_id"]]
        t.ratings, t.written, t.detailed = row["ratings"], row["written"], row["detailed"]
    for row in (await db.execute(_PHOTOS_SQL, params)).mappings():
        t = out[row["user_id"]]
        t.photos, t.trailblazers = row["photos"], row["trailblazers"]
        t.photos_pending, t.pending_trailblazers = row["pending"], row["pending_trailblazers"]
    for row in (await db.execute(_TRIPS_SQL, params)).mappings():
        t = out[row["user_id"]]
        t.odysseys, t.mini_tours = row["odysseys"], row["mini_tours"]
    for row in (await db.execute(_EVENTS_SQL, {**params, "carry": EVENT_CARRY_OVER})).mappings():
        t = out[row["user_id"]]
        t.bonus, t.carried_over = int(row["points"] or 0), bool(row["carried"])
    return out


def _r():
    from app.services import telemetry
    return telemetry._get_redis()


def _key(user_id) -> str:
    return f"xpts:v1:{user_id}"


def _notified_key(user_id) -> str:
    return f"xpts:lvl:{user_id}"


async def totals_for(db, user_ids: Iterable, *, fresh: bool = False) -> dict[uuid.UUID, Totals]:
    """Each traveller's totals, from the cache where it has them."""
    import json
    ids = [u if isinstance(u, uuid.UUID) else uuid.UUID(str(u)) for u in user_ids if u]
    ids = list(dict.fromkeys(ids))
    if not ids:
        return {}
    out: dict[uuid.UUID, Totals] = {}
    if not fresh:
        try:
            raw = await _r().mget([_key(u) for u in ids])
            for u, v in zip(ids, raw):
                if v:
                    out[u] = Totals(**json.loads(v.decode() if isinstance(v, bytes) else v))
        except Exception:
            out = {}
    missing = [u for u in ids if u not in out]
    if missing:
        computed = await _compute(db, missing)
        out.update(computed)
        try:
            pipe = _r().pipeline()
            for u, t in computed.items():
                pipe.set(_key(u), json.dumps(t.as_cache()), ex=_CACHE_TTL_S)
            await pipe.execute()
        except Exception:
            pass
    return out


async def total_for(db, user_id, *, fresh: bool = False) -> Totals:
    return (await totals_for(db, [user_id], fresh=fresh)).get(
        user_id if isinstance(user_id, uuid.UUID) else uuid.UUID(str(user_id)), Totals()
    )


async def levels_for(db, user_ids: Iterable) -> dict[uuid.UUID, int]:
    """Level number per traveller, for the names on public lists. Never raises:
    a list without levels is better than no list."""
    try:
        return {u: level_number(t.total) for u, t in (await totals_for(db, user_ids)).items()}
    except Exception as e:
        logger.warning(f"Explorer levels lookup failed: {e}")
        return {}


async def bust(user_id) -> None:
    try:
        await _r().delete(_key(user_id))
    except Exception:
        pass


# ── Changes ─────────────────────────────────────────────────────────────────

def change(before: int, after: int) -> dict:
    """The `points` block an answer carries after a traveller's action."""
    lv_before, lv_after = level_number(before), level_number(after)
    return {
        "earned": after - before,
        "total": after,
        "level": lv_after,
        "level_name": level_name(lv_after),
        "levelled_up": lv_after > lv_before,
    }


async def _claim_level(user_id, before: int, after: int) -> Optional[int]:
    """The level to announce, if `after` reached one this traveller has not
    been told about yet (so a hidden-then-restored review cannot repeat it)."""
    lv = level_number(after)
    if lv <= level_number(before) or lv < 2:
        return None
    try:
        r = _r()
        told = int((await r.get(_notified_key(user_id))) or 0)
        if lv <= told:
            return None
        await r.set(_notified_key(user_id), lv)
    except Exception:
        return None
    return lv


def _level_up_line(lv: int) -> tuple[str, str]:
    name, _, tagline = LEVELS[lv - 1]
    return (f"Level up! You're now a {name}",
            f"Level {lv} of {MAX_LEVEL}: {tagline}.")


async def notify_level_up(user_id, before: int, after: int) -> None:
    """A bell line + push for a new level. Never raises."""
    lv = await _claim_level(user_id, before, after)
    if lv is None:
        return
    title, body = _level_up_line(lv)
    await notify(user_id, title, body + " Keep rating places and adding photos.")


async def notify(user_id, title: str, body: str) -> None:
    """A bell line and a push to the traveller's devices; never raises."""
    from app.core.database import async_session
    from app.models.notification import Notification
    from app.services.enquiry_notifications import _push_data
    try:
        async with async_session() as db:
            db.add(Notification(user_id=user_id, title=title, body=body, type=PUSH_TYPE))
            await db.commit()
            try:
                await _push_data(db, user_id, title, body, {"type": PUSH_TYPE})
            except Exception as e:
                logger.warning(f"Explorer points push to {user_id} failed: {e}")
    except Exception as e:
        logger.error(f"Explorer points notification for {user_id} failed: {e}")


async def after_change(user_id, before: int) -> None:
    """Background task after anything that may have moved a traveller's
    points: drop the cache, recount, tell them if they levelled up."""
    from app.core.database import async_session
    await bust(user_id)
    try:
        async with async_session() as db:
            after = (await total_for(db, user_id, fresh=True)).total
    except Exception as e:
        logger.warning(f"Explorer points recount for {user_id} failed: {e}")
        return
    await notify_level_up(user_id, before, after)


async def after_photo_approved(user_id, place_name: str, points: int, before: int) -> None:
    """Tell the sender their photo is live and what it earned, in one line
    with the new level when it crossed one."""
    from app.core.database import async_session
    await bust(user_id)
    after = before + points
    try:
        async with async_session() as db:
            after = (await total_for(db, user_id, fresh=True)).total
    except Exception as e:
        logger.warning(f"Explorer points recount for {user_id} failed: {e}")
    title = "Your photo is live"
    body = f"Your photo of {place_name} is now on nexAround. +{points} points."
    lv = await _claim_level(user_id, before, after)
    if lv is not None:
        title, up = _level_up_line(lv)
        body = f"Your photo of {place_name} is live (+{points} points). {up}"
    await notify(user_id, title, body)


# ── What the app shows ──────────────────────────────────────────────────────

def ladder() -> list[dict]:
    return [
        {"level": i + 1, "name": name, "badge": BADGES[i], "min_points": need,
         "tagline": tagline}
        for i, (name, need, tagline) in enumerate(LEVELS)
    ]


def earn_table() -> list[dict]:
    return [
        {"key": "rating", "label": "Rate a place", "points": RATING,
         "note": "Tap the stars on any place."},
        {"key": "written", "label": "Write a review", "points": WRITTEN,
         "note": f"Extra for {WRITTEN_CHARS}+ characters.", "min_chars": WRITTEN_CHARS},
        {"key": "detailed", "label": "Write a detailed review", "points": DETAILED,
         "note": f"Extra again for {DETAILED_CHARS}+ characters.", "min_chars": DETAILED_CHARS},
        {"key": "photo", "label": "Add a photo", "points": PHOTO,
         "note": "Counts once our team approves it."},
        {"key": "trailblazer", "label": "First photo of a place", "points": TRAILBLAZER,
         "note": "Extra for a place that had no photo yet."},
        {"key": "odyssey", "label": "Finish an Odyssey", "points": ODYSSEY,
         "note": "Mark your trip as completed."},
        {"key": "mini_tour", "label": "Finish a Mini Tour", "points": MINI_TOUR,
         "note": f"{MINI_TOUR_MIN_STOPS}+ stops, up to {MINI_TOURS_PER_DAY} tours a day."},
    ]


def info() -> dict:
    """Everything the "?" explainer shows; public, no login."""
    return {
        "title": "What are Explorer Points?",
        "intro": (
            "You earn points for helping other travellers: rating places, writing "
            "reviews and adding photos. Points raise your level, and your level "
            "shows next to your name on reviews and photos."
        ),
        "earn": earn_table(),
        "levels": ladder(),
        "rules": [
            "Photos count once our team approves them.",
            "Hidden or deleted reviews lose their points.",
            "Editing a review never counts twice.",
        ],
    }


def summary(t: Totals) -> dict:
    """GET /points/me."""
    return {
        "total": t.total,
        "level": level_for(t.total).as_dict(),
        "max_level": MAX_LEVEL,
        "pending_points": t.pending_points,
        "points_by": {
            "reviews": t.review_points,
            "photos": t.photo_points,
            "trips": t.trip_points,
            "bonus": t.bonus,
        },
        "counts": {
            "ratings": t.ratings,
            "reviews": t.written,
            "detailed_reviews": t.detailed,
            "photos": t.photos,
            "trailblazer_photos": t.trailblazers,
            "photos_pending": t.photos_pending,
            "odysseys": t.odysseys,
            "mini_tours": t.mini_tours,
        },
        "carried_over": t.carried_over,
    }
