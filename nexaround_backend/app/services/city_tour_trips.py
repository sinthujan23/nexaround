"""City Tours trips: a traveller following a guide step by step.

"Start trip" in the app saves when the traveller set off; "Mark done" saves
when each step (a stop, or the ride to the next one) ended. Every step has
planned minutes, read from the guide's own words: a stop's "time to spend"
("1.5–2 hours") or a ride's "travel time" ("20 min"). A range counts as its
middle, rounded to 5 minutes, and a step with no time it can read gets a
default.

The app lays the day out from these: a step starts when the one before it was
marked done (the first, at the start), and the steps after it follow on, so
marking a step done late or early moves the rest. The worker pushes one
"Done at …?" reminder per step once it runs past its minutes (reminder_loop).

The functions above the database section are pure, so they can be tested on
their own.
"""
from __future__ import annotations

import asyncio
import logging
import math
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.services.city_tours import MOVE, STOP, TRANSPORT_MODES

logger = logging.getLogger(__name__)

PUSH_TYPE = "city_tour_trip"

# Planned minutes for a step whose time is missing or unreadable.
DEFAULT_MINUTES = {STOP: 30, MOVE: 15}
_MAX_MINUTES = 12 * 60

# A running trip older than this is left alone: no more reminders.
ACTIVE_FOR = timedelta(hours=36)
REMIND_EVERY_S = 60

_WORDS = [
    (re.compile(r"\bhalf[ -](?:an )?hour\b"), "30 min"),
    (re.compile(r"\b(?:an|one) hour\b"), "1 hour"),
    (re.compile(r"\bquarter of an hour\b"), "15 min"),
    (re.compile(r"(\d+):(\d{2})\b"), r"\1 h \2 min"),
    (re.compile(r"½"), ".5"),
]
_RANGE = re.compile(r"\s*(?:–|—|-|\bto\b|\bor\b)\s*")
_AMOUNT = re.compile(r"(\d+(?:[.,]\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)?(?![a-z])")


def _unit(word: str) -> Optional[str]:
    return ("h" if word[0] == "h" else "m") if word else None


def _side(text: str, default_unit: Optional[str]) -> Optional[float]:
    """Minutes in one side of a range: "1.5", "2 hours", "1h 30", "45 min"."""
    total, last = None, None
    for number, word in _AMOUNT.findall(text):
        unit = _unit(word)
        if unit is None:
            # "1h30": a bare number after hours is minutes.
            unit = "m" if last == "h" else default_unit
        if unit is None:
            return None
        total = (total or 0) + float(number.replace(",", ".")) * (60 if unit == "h" else 1)
        last = unit
    return total


def parse_minutes(text: str) -> Optional[int]:
    """The minutes a guide's time means: "20 min" → 20, "1.5–2 hours" → 105,
    "45 min–1 hour" → 55. None when it can't be read ("a while", "")."""
    text = (text or "").strip().lower()
    if not text:
        return None
    for pattern, repl in _WORDS:
        text = pattern.sub(repl, text)
    first = next((u for _, u in _AMOUNT.findall(text) if u), "")
    # "2–3 hours": the bare 2 takes the unit written once for the range.
    default_unit = _unit(first)
    values = [v for v in (_side(part, default_unit) for part in _RANGE.split(text)) if v]
    if not values:
        return None
    middle = (min(values) + max(values)) / 2
    return int(min(_MAX_MINUTES, max(5, math.floor(middle / 5 + 0.5) * 5)))


def step_minutes(step: dict) -> int:
    kind = step.get("type")
    text = step.get("time_here") if kind == STOP else step.get("duration")
    return parse_minutes(text or "") or DEFAULT_MINUTES.get(kind, DEFAULT_MINUTES[STOP])


def plan_minutes(content: dict) -> dict[str, int]:
    """Step id → planned minutes, for every step of the guide."""
    return {s["id"]: step_minutes(s) for s in (content or {}).get("steps") or [] if s.get("id")}


def as_time(value) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def due_step(
    started_at: datetime, steps: list[dict], done: dict, minutes: dict[str, int],
) -> Optional[tuple[dict, datetime]]:
    """The step in hand (the first not marked done) and when it is planned to
    end: the end of the step before it, plus its own minutes. None once every
    step is done."""
    since = started_at
    for step in steps:
        at = as_time(done.get(step.get("id")))
        if at is not None:
            since = at
            continue
        planned = minutes.get(step.get("id"), DEFAULT_MINUTES.get(step.get("type"), 30))
        return step, since + timedelta(minutes=planned)
    return None


def mark_done(
    started_at: datetime, steps: list[dict], done: dict, step_id: str,
    at: Optional[datetime], now: datetime,
) -> Optional[dict]:
    """The trip's done times with `step_id` marked, or None when it is not the
    step in hand (already done: a second tap; or one further on). `at` is when
    the traveller tapped, which a retry after a dropped connection keeps; it is
    held between the step's start and now."""
    due = due_step(started_at, steps, done, {})
    if due is None or due[0].get("id") != step_id:
        return None
    since = started_at
    for step in steps:
        if step.get("id") == step_id:
            break
        since = as_time(done.get(step.get("id"))) or since
    when = at if at is not None and at.tzinfo is not None else now
    when = min(max(when, since), now)
    return {**done, step_id: when.isoformat()}


def undo_last(steps: list[dict], done: dict) -> dict:
    """The done times without the last step marked."""
    marked = [s.get("id") for s in steps if s.get("id") in done]
    return {k: v for k, v in done.items() if k != marked[-1]} if marked else dict(done)


def all_done(steps: list[dict], done: dict) -> bool:
    return bool(steps) and all(s.get("id") in done for s in steps)


def _next_stop(steps: list[dict], index: int) -> Optional[dict]:
    return next((s for s in steps[index + 1:] if s.get("type") == STOP), None)


def reminder_text(steps: list[dict], step: dict) -> tuple[str, str]:
    """The push for a step past its planned time: (title, body)."""
    index = next((i for i, s in enumerate(steps) if s.get("id") == step.get("id")), 0)
    if step.get("type") == STOP:
        title = f"Done at {step.get('name') or 'this stop'}?"
        after = steps[index + 1] if index + 1 < len(steps) else None
        if after is None:
            return title, "That's the last stop. Mark it done to finish your trip."
        if after.get("type") == MOVE:
            nxt = _next_stop(steps, index + 1)
            how = TRANSPORT_MODES.get(after.get("mode") or "walk", "Walk")
            where = f" to {nxt['name']}" if nxt and nxt.get("name") else ""
            return title, f"Next: {how}{where}. Mark it done to update your times."
        return title, f"Next: {after.get('name') or 'the next stop'}. Mark it done to update your times."
    nxt = _next_stop(steps, index)
    if nxt and nxt.get("name"):
        return f"Arrived at {nxt['name']}?", "Mark the ride done to update your times."
    return "Still on the way?", "Mark the ride done to update your times."


def view(trip, content: dict) -> dict:
    """A trip as the app reads it: the times saved, and every step's minutes."""
    return {
        "id": str(trip.id),
        "tour_id": str(trip.tour_id),
        "started_at": trip.started_at.isoformat(),
        "finished_at": trip.finished_at.isoformat() if trip.finished_at else None,
        "done": dict(trip.done or {}),
        "minutes": plan_minutes(content),
    }


# ── Database ────────────────────────────────────────────────────────────────

async def remind_due(db, now: datetime) -> int:
    """Push "Done at …?" for every running trip whose step in hand has run
    past its planned time, once per step. Returns how many went out."""
    from sqlalchemy import select

    from app.models.city_tour import CityTour, CityTourTrip
    from app.services.enquiry_notifications import _push_data

    rows = (await db.execute(
        select(CityTourTrip, CityTour)
        .join(CityTour, CityTour.id == CityTourTrip.tour_id)
        .where(
            CityTourTrip.finished_at.is_(None),
            CityTourTrip.ended_at.is_(None),
            CityTourTrip.started_at > now - ACTIVE_FOR,
            CityTour.live_content.isnot(None),
            CityTour.is_hidden.is_(False),
        )
    )).all()
    sent = 0
    for trip, tour in rows:
        steps = (tour.live_content or {}).get("steps") or []
        due = due_step(trip.started_at, steps, trip.done or {}, plan_minutes(tour.live_content))
        if due is None:
            continue
        step, ends = due
        if ends > now or trip.reminded_step_id == step.get("id"):
            continue
        # Saved before the push, so a crash part way never sends it twice.
        trip.reminded_step_id = step.get("id")
        await db.commit()
        title, body = reminder_text(steps, step)
        try:
            await _push_data(db, trip.user_id, title, body, {"type": PUSH_TYPE, "tour_id": str(tour.id)})
            sent += 1
        except Exception as e:
            logger.warning("[city tour trips] reminder for trip %s failed: %s", trip.id, e)
    return sent


async def reminder_loop() -> None:
    """Worker loop (leader only): look for due reminders every minute."""
    from app.core.database import async_session

    while True:
        try:
            async with async_session() as db:
                await remind_due(db, datetime.now(timezone.utc))
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("[city tour trips] reminder loop error: %s", e)
        await asyncio.sleep(REMIND_EVERY_S)
