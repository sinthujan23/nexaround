"""Explorer feedback, quick ratings and the quarterly survey: the rules.

See app/models/feedback.py for what each table holds. The API layers
(app/api/v1/feedback.py for the app, feedback_admin.py for the panel) only
check who is calling and hand over to the functions here.
"""
import io
import logging
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Iterable, Optional

from fastapi import HTTPException, status
from PIL import Image, ImageOps
from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.feedback import Feedback, SurveyPrompt, SurveyResponse, SurveyRound
from app.models.notification import Notification
from app.models.user import User
from app.services import email_service

logger = logging.getLogger(__name__)

# ── Fixed vocabularies (mirrored in the app's feedback_constants.dart) ─────

MESSAGE_TYPES = ("suggestion", "improvement", "problem", "love", "other")
# The first test builds sent "idea". The client asked (2026-11-26) not to call
# what explorers send an "idea" (an idea taken from a user can bring an IP
# claim), so it is stored as a suggestion.
LEGACY_TYPES = {"idea": "suggestion"}
QUICK_TYPES = ("good", "bad")
# Things a quick rating can be about.
QUICK_FEATURES = ("odyssey", "city_guides", "walking_challenge")
QUICK_REASONS = {
    "odyssey": ("wrong_places", "too_rushed", "prices_off", "other"),
    "city_guides": ("route_confusing", "places_closed", "too_long", "other"),
    "walking_challenge": ("too_far", "clues_hard", "map_problem", "other"),
}
STATUSES = ("new", "seen", "planned", "done", "replied", "closed")

# Survey Q2: the features an explorer can say they use.
SURVEY_FEATURES = (
    "ar", "odyssey", "neva", "discover", "city_guides", "walking_challenge",
    "trip_split", "travel_stories", "experiences", "museums", "forum",
)
WOULD_PAY = ("yes", "maybe", "no")
PRICE_RANGES = ("lt2", "2to5", "5to8", "8to12", "gt12")
WHY_NOT = ("free_apps", "travel_rarely", "too_expensive", "other")
MAX_BUILD_NEXT_PICKS = 3

# Icons the team can give a "build next" option. Each is a Material Symbols
# name the app maps to an Icon (feedback_constants.dart); anything else shows
# a light bulb.
OPTION_ICONS = (
    "lightbulb", "wifi_off", "public", "hotel", "flight", "notifications_active",
    "groups", "dark_mode", "translate", "map", "directions_car", "restaurant",
    "photo_camera", "payments", "train", "hiking", "event", "language",
)

# Survey pop-up rules: "Later" hides it for this long, it pops up at most this
# many times per round, and never for an account younger than a day.
SNOOZE = timedelta(days=3)
MAX_AUTO_SHOWS = 3
NEW_ACCOUNT_GRACE = timedelta(days=1)

# Feedback per explorer per day (messages and quick ratings together).
DAILY_LIMIT = 10

# ── Screenshots: private files, served to the admin only ──────────────────

FEEDBACK_UPLOAD_DIR = "app/private_uploads/feedback"
MAX_SCREENSHOTS = 3
MAX_SCREENSHOT_BYTES = 10 * 1024 * 1024
MAX_SIDE_PX = 1800
_NAME = re.compile(r"^[0-9a-f]{32}\.webp$")


def _user_dir(user_id: uuid.UUID) -> str:
    return os.path.join(FEEDBACK_UPLOAD_DIR, str(user_id))


def save_screenshot(user_id: uuid.UUID, content: bytes) -> str:
    """Decode, straighten, shrink and re-encode a screenshot as WebP into the
    explorer's private folder. Returns the file name."""
    if len(content) > MAX_SCREENSHOT_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The picture is larger than 10 MB.")
    try:
        img = Image.open(io.BytesIO(content))
        if img.format == "JPEG":
            img.draft("RGB", (MAX_SIDE_PX * 2, MAX_SIDE_PX * 2))
        img.load()
        img = ImageOps.exif_transpose(img)
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGB")
        img.thumbnail((MAX_SIDE_PX, MAX_SIDE_PX))
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="That file is not a picture we can read.")
    out = io.BytesIO()
    img.save(out, format="WEBP", quality=80, method=4)
    folder = _user_dir(user_id)
    os.makedirs(folder, exist_ok=True)
    name = f"{uuid.uuid4().hex}.webp"
    with open(os.path.join(folder, name), "wb") as f:
        f.write(out.getvalue())
    return name


def screenshot_path(user_id: uuid.UUID, name: str) -> Optional[str]:
    """The file on disk for one of an explorer's screenshots, or None."""
    if not _NAME.match(name or ""):
        return None
    path = os.path.join(_user_dir(user_id), name)
    return path if os.path.isfile(path) else None


def _clean_screenshots(user_id: uuid.UUID, names: Iterable[str]) -> list[str]:
    """Only names this explorer actually uploaded, in order, no repeats."""
    kept: list[str] = []
    for n in names or []:
        if n not in kept and screenshot_path(user_id, n):
            kept.append(n)
    if len(kept) > MAX_SCREENSHOTS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Up to {MAX_SCREENSHOTS} pictures.")
    return kept


# ── Small helpers ──────────────────────────────────────────────────────────

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _short(value: Optional[str], limit: int) -> Optional[str]:
    value = (value or "").strip()
    return value[:limit] if value else None


async def _country(db: AsyncSession, user_id: uuid.UUID) -> Optional[str]:
    """Where the explorer is, from their latest request's IP. A failed lookup
    must not spoil the caller's transaction, hence the savepoint."""
    from app.services import ip_country
    try:
        async with db.begin_nested():
            return (await ip_country.countries_for(db, [user_id])).get(user_id)
    except Exception:
        return None


async def check_daily_limit(db: AsyncSession, user_id: uuid.UUID) -> None:
    since = _now() - timedelta(days=1)
    sent = (await db.execute(
        select(func.count(Feedback.id)).where(Feedback.user_id == user_id, Feedback.created_at >= since)
    )).scalar_one()
    if sent >= DAILY_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Thanks for all the feedback! Please try again tomorrow.",
        )


# ── Explorer side: messages and quick ratings ─────────────────────────────

def message_type(raw: str) -> str:
    """A message's type, with the old "idea" stored as "suggestion"."""
    t = LEGACY_TYPES.get(raw, raw)
    if t not in MESSAGE_TYPES:
        raise HTTPException(status_code=400, detail="Pick what it's about.")
    return t


async def create_message(
    db: AsyncSession, user: User, *, type: str, text: str, screenshots: list[str], can_reply: bool,
    source_screen: Optional[str], feature: Optional[str], ref_id: Optional[str], ref_label: Optional[str],
    app_version: Optional[str], platform: Optional[str], os_version: Optional[str],
) -> Feedback:
    type = message_type(type)
    text = (text or "").strip()
    if len(text) < 2:
        raise HTTPException(status_code=400, detail="Write a few words first.")
    await check_daily_limit(db, user.id)
    item = Feedback(
        user_id=user.id, kind="message", type=type, text=text[:5000],
        screenshots=_clean_screenshots(user.id, screenshots), can_reply=bool(can_reply),
        source_screen=_short(source_screen, 40),
        feature=feature if feature in QUICK_FEATURES else None,
        ref_id=_short(ref_id, 64), ref_label=_short(ref_label, 200),
        app_version=_short(app_version, 32), platform=_short(platform, 16), os_version=_short(os_version, 80),
        country=await _country(db, user.id),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


async def rate(
    db: AsyncSession, user: User, *, feature: str, ref_id: str, ref_label: Optional[str], rating: str,
    reasons: list[str], app_version: Optional[str], platform: Optional[str],
) -> Feedback:
    """A quick good/bad after finishing something. Rating the same thing again
    (e.g. adding reasons after "bad") updates the one row."""
    if feature not in QUICK_FEATURES:
        raise HTTPException(status_code=400, detail="Unknown feature.")
    if rating not in QUICK_TYPES:
        raise HTTPException(status_code=400, detail="Rating must be good or bad.")
    ref_id = _short(ref_id, 64)
    if not ref_id:
        raise HTTPException(status_code=400, detail="Missing what is rated.")
    allowed = QUICK_REASONS[feature]
    reasons = [r for r in dict.fromkeys(reasons or []) if r in allowed] if rating == "bad" else []
    existing = (await db.execute(select(Feedback).where(
        Feedback.kind == "quick", Feedback.user_id == user.id,
        Feedback.feature == feature, Feedback.ref_id == ref_id,
    ))).scalar_one_or_none()
    if existing:
        existing.type = rating
        existing.reasons = reasons
        if ref_label:
            existing.ref_label = _short(ref_label, 200)
        await db.commit()
        return existing
    await check_daily_limit(db, user.id)
    item = Feedback(
        user_id=user.id, kind="quick", type=rating, reasons=reasons, can_reply=False,
        feature=feature, ref_id=ref_id, ref_label=_short(ref_label, 200), source_screen=feature,
        # A plain "good" needs no one's attention; "bad" lands as new.
        status="new" if rating == "bad" else "seen",
        app_version=_short(app_version, 32), platform=_short(platform, 16),
        country=await _country(db, user.id),
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


async def mine(db: AsyncSession, user_id: uuid.UUID) -> list[dict]:
    rows = (await db.execute(
        select(Feedback).where(Feedback.user_id == user_id, Feedback.kind == "message")
        .order_by(Feedback.created_at.desc()).limit(50)
    )).scalars().all()
    return [{
        "id": str(f.id), "type": f.type, "text": f.text, "status": f.status,
        "screenshots": len(f.screenshots or []),
        "created_at": f.created_at.isoformat(),
        "replies": [{"text": r.get("text"), "at": r.get("at")} for r in (f.replies or [])],
    } for f in rows]


# ── Explorer side: the survey ─────────────────────────────────────────────

async def open_round(db: AsyncSession) -> Optional[SurveyRound]:
    now = _now()
    return (await db.execute(
        select(SurveyRound).where(
            SurveyRound.is_open.is_(True), SurveyRound.starts_at <= now, SurveyRound.ends_at > now,
        ).order_by(SurveyRound.starts_at.desc()).limit(1)
    )).scalar_one_or_none()


def round_for_app(r: SurveyRound) -> dict:
    return {
        "id": str(r.id), "name": r.name, "ends_at": r.ends_at.isoformat(),
        "build_next_options": [
            {"key": o.get("key"), "label": o.get("label"), "icon": o.get("icon") or "lightbulb"}
            for o in (r.build_next_options or [])
        ],
    }


async def current_for(db: AsyncSession, user: User) -> dict:
    """What the app shows: the open round (or none), whether this explorer has
    answered it, and whether it may pop up by itself right now."""
    r = await open_round(db)
    if not r:
        return {"round": None, "answered": False, "auto_show": False}
    answered = (await db.execute(select(func.count(SurveyResponse.id)).where(
        SurveyResponse.round_id == r.id, SurveyResponse.user_id == user.id,
    ))).scalar_one() > 0
    prompt = await db.get(SurveyPrompt, (r.id, user.id))
    now = _now()
    auto = (
        not answered
        and (prompt is None or prompt.shown_count < MAX_AUTO_SHOWS)
        and (prompt is None or prompt.snoozed_until is None or prompt.snoozed_until <= now)
        and (user.created_at is None or now - user.created_at >= NEW_ACCOUNT_GRACE)
    )
    return {"round": round_for_app(r), "answered": answered, "auto_show": auto}


async def _prompt(db: AsyncSession, round_id: uuid.UUID, user_id: uuid.UUID) -> SurveyPrompt:
    p = await db.get(SurveyPrompt, (round_id, user_id))
    if p is None:
        p = SurveyPrompt(round_id=round_id, user_id=user_id, shown_count=0)
        db.add(p)
    return p


async def _round_or_404(db: AsyncSession, round_id: uuid.UUID, *, must_be_open: bool) -> SurveyRound:
    r = await db.get(SurveyRound, round_id)
    if not r:
        raise HTTPException(status_code=404, detail="Survey not found.")
    if must_be_open:
        now = _now()
        if not (r.is_open and r.starts_at <= now < r.ends_at):
            raise HTTPException(status_code=409, detail="This survey has closed.")
    return r


async def mark_shown(db: AsyncSession, round_id: uuid.UUID, user_id: uuid.UUID) -> None:
    await _round_or_404(db, round_id, must_be_open=True)
    p = await _prompt(db, round_id, user_id)
    p.shown_count = (p.shown_count or 0) + 1
    await db.commit()


async def snooze(db: AsyncSession, round_id: uuid.UUID, user_id: uuid.UUID) -> None:
    await _round_or_404(db, round_id, must_be_open=True)
    p = await _prompt(db, round_id, user_id)
    p.snoozed_until = _now() + SNOOZE
    await db.commit()


async def answer(
    db: AsyncSession, user: User, round_id: uuid.UUID, *, nps: int, features: list[str],
    build_next: list[str], build_next_other: Optional[str], would_pay: str,
    price_range: Optional[str], why_not: list[str], comment: Optional[str],
    app_version: Optional[str], platform: Optional[str],
) -> SurveyResponse:
    r = await _round_or_404(db, round_id, must_be_open=True)
    if not isinstance(nps, int) or not 0 <= nps <= 10:
        raise HTTPException(status_code=400, detail="Pick a number from 0 to 10.")
    if would_pay not in WOULD_PAY:
        raise HTTPException(status_code=400, detail="Answer whether you would pay.")
    if would_pay in ("yes", "maybe"):
        if price_range not in PRICE_RANGES:
            raise HTTPException(status_code=400, detail="Pick how much a month feels fair.")
        why_not = []
    else:
        price_range = None
        why_not = [w for w in dict.fromkeys(why_not or []) if w in WHY_NOT]
    keys = [o.get("key") for o in (r.build_next_options or [])]
    picks = [k for k in dict.fromkeys(build_next or []) if k in keys]
    if len(picks) > MAX_BUILD_NEXT_PICKS:
        raise HTTPException(status_code=400, detail=f"Pick up to {MAX_BUILD_NEXT_PICKS}.")
    exists = (await db.execute(select(func.count(SurveyResponse.id)).where(
        SurveyResponse.round_id == r.id, SurveyResponse.user_id == user.id,
    ))).scalar_one()
    if exists:
        raise HTTPException(status_code=409, detail="You've already answered this survey. Thank you!")
    resp = SurveyResponse(
        round_id=r.id, user_id=user.id, nps=nps,
        features=[f for f in dict.fromkeys(features or []) if f in SURVEY_FEATURES],
        build_next=picks, build_next_other=_short(build_next_other, 300),
        would_pay=would_pay, price_range=price_range, why_not=why_not,
        comment=_short(comment, 2000),
        app_version=_short(app_version, 32), platform=_short(platform, 16),
        country=await _country(db, user.id),
    )
    db.add(resp)
    await db.commit()
    await db.refresh(resp)
    return resp


# ── Admin side: rounds ─────────────────────────────────────────────────────

def slug(label: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", (label or "").lower()).strip("_")
    return (s or "option")[:40]


def normalise_options(options: list[dict], existing: list[dict], answered: bool) -> list[dict]:
    """The team's "build next" list. Keys stay stable for options that keep
    their key, so answers already given still point at the right option. Once
    a round has answers, options can be added and relabelled, not removed."""
    out: list[dict] = []
    seen: set[str] = set()
    for o in options or []:
        label = (o.get("label") or "").strip()[:60]
        if not label:
            continue
        key = (o.get("key") or "").strip()[:40] or slug(label)
        base, n = key, 2
        while key in seen:
            key = f"{base[:37]}_{n}"
            n += 1
        seen.add(key)
        icon = o.get("icon") if o.get("icon") in OPTION_ICONS else "lightbulb"
        out.append({"key": key, "label": label, "icon": icon})
    if answered:
        missing = [o for o in existing or [] if o.get("key") not in seen]
        if missing:
            raise HTTPException(
                status_code=400,
                detail="This survey already has answers, so options can't be removed. You can rename them or add new ones.",
            )
    if len(out) > 15:
        raise HTTPException(status_code=400, detail="Up to 15 options.")
    return out


async def response_count(db: AsyncSession, round_id: uuid.UUID) -> int:
    return (await db.execute(
        select(func.count(SurveyResponse.id)).where(SurveyResponse.round_id == round_id)
    )).scalar_one()


async def close_other_rounds(db: AsyncSession, keep_id: uuid.UUID) -> None:
    others = (await db.execute(
        select(SurveyRound).where(SurveyRound.is_open.is_(True), SurveyRound.id != keep_id)
    )).scalars().all()
    for o in others:
        o.is_open = False


# ── Admin side: results ────────────────────────────────────────────────────

def nps_parts(scores: list[int]) -> dict:
    """Net Promoter Score: % of 9–10 minus % of 0–6, rounded."""
    n = len(scores)
    if not n:
        return {"score": None, "promoters": None, "passives": None, "detractors": None}
    pro = sum(1 for s in scores if s >= 9)
    det = sum(1 for s in scores if s <= 6)
    return {
        "score": round((pro - det) * 100 / n),
        "promoters": round(pro * 100 / n),
        "passives": round((n - pro - det) * 100 / n),
        "detractors": round(det * 100 / n),
    }


def _pct(part: int, whole: int) -> Optional[int]:
    return round(part * 100 / whole) if whole else None


async def _active_explorers(db: AsyncSession, start: datetime, end: datetime) -> int:
    """Explorers with a 30 s+ visit in the window: the Users page's rule."""
    from sqlalchemy import text as sql
    from app.api.v1.admin import ACTIVE_VISIT_SECONDS
    from app.services.official_stories import OFFICIAL_USER_ID
    return (await db.execute(sql("""
        SELECT count(DISTINCT user_id) FROM user_sessions
        WHERE created_at >= :start AND created_at < :end AND user_id IS NOT NULL
          AND user_id != :official AND duration_seconds >= :min_visit
    """), {"start": start, "end": end, "official": OFFICIAL_USER_ID,
           "min_visit": ACTIVE_VISIT_SECONDS})).scalar_one()


async def _summary(db: AsyncSession, r: SurveyRound) -> dict:
    rows = (await db.execute(
        select(SurveyResponse).where(SurveyResponse.round_id == r.id)
    )).scalars().all()
    n = len(rows)
    end = min(r.ends_at, _now())
    nps = nps_parts([x.nps for x in rows])

    pay = {k: sum(1 for x in rows if x.would_pay == k) for k in WOULD_PAY}
    payers = pay["yes"] + pay["maybe"]
    prices = {k: sum(1 for x in rows if x.price_range == k) for k in PRICE_RANGES}
    nos = pay["no"]
    why = {k: sum(1 for x in rows if k in (x.why_not or [])) for k in WHY_NOT}

    options = r.build_next_options or []
    build = []
    for o in options:
        k = o.get("key")
        picked = sum(1 for x in rows if k in (x.build_next or []))
        first = sum(1 for x in rows if (x.build_next or [None])[0] == k)
        build.append({"key": k, "label": o.get("label"), "icon": o.get("icon"),
                      "pct": _pct(picked, n), "count": picked, "first": first})
    build.sort(key=lambda b: (-(b["count"]), -(b["first"])))
    features = sorted(
        ({"key": k, "pct": _pct(sum(1 for x in rows if k in (x.features or [])), n),
          "count": sum(1 for x in rows if k in (x.features or []))} for k in SURVEY_FEATURES),
        key=lambda f: -f["count"],
    )

    quick_rows = (await db.execute(
        select(Feedback.feature, Feedback.type, func.count(Feedback.id))
        .where(Feedback.kind == "quick", Feedback.created_at >= r.starts_at, Feedback.created_at < end)
        .group_by(Feedback.feature, Feedback.type)
    )).all()
    quick = {}
    for feat in QUICK_FEATURES:
        good = sum(c for f, t, c in quick_rows if f == feat and t == "good")
        bad = sum(c for f, t, c in quick_rows if f == feat and t == "bad")
        quick[feat] = {"good_pct": _pct(good, good + bad), "count": good + bad}
    q_good = sum(c for _, t, c in quick_rows if t == "good")
    q_all = sum(c for _, _, c in quick_rows)

    top_price = max(PRICE_RANGES, key=lambda k: prices[k]) if payers else None
    active = await _active_explorers(db, r.starts_at, end) if r.starts_at < end else 0
    return {
        "answers": n,
        "active_explorers": active,
        "answer_rate": _pct(n, active),
        "nps": nps,
        "would_pay": {k: _pct(v, n) for k, v in pay.items()},
        "would_pay_pct": _pct(payers, n),
        "prices": [{"key": k, "pct": _pct(prices[k], payers), "count": prices[k]} for k in PRICE_RANGES],
        "top_price": top_price,
        "why_not": [{"key": k, "pct": _pct(why[k], nos), "count": why[k]} for k in WHY_NOT],
        "build_next": build,
        "build_next_other": [x.build_next_other for x in sorted(rows, key=lambda x: x.created_at, reverse=True)
                             if x.build_next_other][:50],
        "features": features,
        "quick": quick,
        "quick_good_pct": _pct(q_good, q_all),
        "quick_count": q_all,
        "_rows": rows,
    }


async def results(db: AsyncSession, round_id: uuid.UUID) -> dict:
    r = await db.get(SurveyRound, round_id)
    if not r:
        raise HTTPException(status_code=404, detail="Survey not found.")
    cur = await _summary(db, r)
    rows = cur.pop("_rows")

    prev_round = (await db.execute(
        select(SurveyRound).where(SurveyRound.starts_at < r.starts_at)
        .order_by(SurveyRound.starts_at.desc()).limit(1)
    )).scalar_one_or_none()
    previous = None
    if prev_round:
        p = await _summary(db, prev_round)
        p.pop("_rows")
        if p["answers"]:
            previous = {
                "name": prev_round.name, "answers": p["answers"], "nps": p["nps"]["score"],
                "would_pay_pct": p["would_pay_pct"], "quick_good_pct": p["quick_good_pct"],
                "build_next": {b["key"]: b["pct"] for b in p["build_next"]},
                "features": {f["key"]: f["pct"] for f in p["features"]},
            }

    # Comments, newest first, with who wrote them.
    commented = sorted((x for x in rows if x.comment), key=lambda x: x.created_at, reverse=True)[:100]
    names = {}
    if commented:
        users = (await db.execute(select(User.id, User.display_name).where(
            User.id.in_([x.user_id for x in commented])
        ))).all()
        names = {u.id: u.display_name for u in users}
    cur["comments"] = [{
        "name": names.get(x.user_id) or "Explorer", "country": x.country, "nps": x.nps,
        "would_pay": x.would_pay, "text": x.comment, "at": x.created_at.isoformat(),
    } for x in commented]
    cur["comments_total"] = sum(1 for x in rows if x.comment)
    cur["previous"] = previous
    cur["round"] = round_admin(r, len(rows))
    cur["plan_prices"] = plan_prices()
    return cur


def plan_prices() -> list[dict]:
    """The monthly plans and the price range each falls in, so the results can
    show where our prices sit among what explorers called fair."""
    from app.api.v1.billing import CATALOG_PRICES
    out = []
    for (plan, period), usd in CATALOG_PRICES.items():
        if period != "monthly":
            continue
        rng = ("lt2" if usd < 2 else "2to5" if usd < 5 else "5to8" if usd < 8 else "8to12" if usd < 12 else "gt12")
        out.append({"plan": plan, "usd": usd, "range": rng})
    return out


def round_admin(r: SurveyRound, answers: int) -> dict:
    now = _now()
    state = "open" if r.is_open and r.starts_at <= now < r.ends_at else (
        "scheduled" if r.is_open and now < r.starts_at else ("ended" if now >= r.ends_at else "closed"))
    return {
        "id": str(r.id), "name": r.name, "starts_at": r.starts_at.isoformat(), "ends_at": r.ends_at.isoformat(),
        "is_open": r.is_open, "state": state, "answers": answers,
        "build_next_options": r.build_next_options or [], "created_at": r.created_at.isoformat(),
    }


# ── Admin side: replying ───────────────────────────────────────────────────

PUSH_TYPE = "feedback_reply"


async def reply(db: AsyncSession, item: Feedback, text: str, by: str) -> dict:
    """The team's answer: a line in the app's bell and a push (both open My
    feedback), and an email they can answer (it comes from support@)."""
    from app.services.enquiry_notifications import _push_data

    text = (text or "").strip()
    if len(text) < 2:
        raise HTTPException(status_code=400, detail="Write a reply first.")
    if not item.can_reply:
        raise HTTPException(status_code=400, detail="This explorer asked not to be contacted.")
    user = await db.get(User, item.user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=400, detail="This explorer's account is no longer active.")

    title = "The NexAround team replied"
    sent = {"bell": False, "push": False, "email": False}
    line = Notification(user_id=user.id, title=title, body=text[:1000], type=PUSH_TYPE)
    db.add(line)
    await db.commit()
    sent["bell"] = True
    try:
        sent["push"] = await _push_data(db, user.id, title, text[:180], {"type": PUSH_TYPE, "feedback_id": str(item.id)})
    except Exception:
        logger.exception("feedback reply push failed for %s", item.id)
    line.push_status = "sent" if sent["push"] else "failed"

    label = {"suggestion": "Your suggestion", "improvement": "What you'd improve",
             "problem": "The problem you reported"}.get(item.type, "Your message")
    if user.email:
        sent["email"] = await email_service.send_experience_update_email(
            user.email,
            subject="A reply to your NexAround feedback",
            heading="The NexAround team replied",
            intro=text,
            rows=((label, (item.text or "")[:300] + ("…" if len(item.text or "") > 300 else "")),
                  ("Sent", item.created_at.strftime("%d %b %Y"))),
            notes=("Reply to this email to answer us.",),
        )
    item.replies = [*(item.replies or []), {"text": text, "by": by, "at": _now().isoformat(), "sent": sent}]
    item.status = "replied"
    await db.commit()
    return sent
