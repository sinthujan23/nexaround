"""City Tours trips: a traveller following one day of a guide step by step.

"Start trip" in the app saves when the traveller set off; "Mark done" saves
when each step (a stop, or the ride to the next one) ended. Every step has
planned minutes, read from the guide's own words: a stop's "time to spend"
("1.5–2 hours") or a ride's "travel time" ("20 min"). A range counts as its
middle, rounded to 5 minutes, and a step with no time it can read gets a
default.

Only stops are ticked ("Visited"), in any order: a traveller who forgot to
tick a stop can tick it later, and one who jumps ahead ticks the stop they are
at. Rides and breaks are not ticked any more (an app from before still can).
The stop in hand is the first stop after the furthest step marked; stops
before that one left unmarked were passed over (the app shows them still to
visit). Any marked step can be taken back.

The app lays the day out from these: the stretch to the stop in hand starts
when the furthest step was marked (the first step, at the start), the rides
and breaks before it run their minutes, and the steps after it follow on, so
ticking a stop late or early moves the rest. The trip is finished once its
last stop is ticked. The worker pushes one "Done at …?" reminder per stop once
it runs past its minutes (reminder_loop).

"Skip" ends a step the same way, at the time it was tapped, and notes it in
`skipped`, so the app can say "Skipped" and leave its minutes out of the pace.

A trip follows one day (`day_id`; a trip from before days, the guide's first
day). The functions above the database section are pure, so they can be
tested on their own.
"""
from __future__ import annotations

import asyncio
import logging
import math
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.services.city_tours import BREAK, MOVE, STOP, TRANSPORT_MODES, all_steps, find_day

logger = logging.getLogger(__name__)

PUSH_TYPE = "city_tour_trip"

# Planned minutes for a step whose time is missing or unreadable.
DEFAULT_MINUTES = {STOP: 30, MOVE: 15, BREAK: 45}
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
    """Step id → planned minutes, for every step of every day."""
    return {s["id"]: step_minutes(s) for s in all_steps(content) if s.get("id")}


def trip_steps(content: dict, day_id: Optional[str]) -> list[dict]:
    """The steps of the day a trip follows."""
    day = find_day(content, day_id)
    return list((day or {}).get("steps") or [])


def as_time(value) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def furthest(steps: list[dict], done: dict) -> int:
    """Where the furthest step marked sits in the day; -1 before any."""
    return max((i for i, s in enumerate(steps) if s.get("id") in done), default=-1)


def due_step(
    started_at: datetime, steps: list[dict], done: dict, minutes: dict[str, int],
) -> Optional[tuple[dict, datetime]]:
    """The stop in hand (the first stop after the furthest step marked) and
    when it is planned to end: when that furthest step was marked (or the
    start), plus the minutes of the rides and breaks on the way and its own.
    None once no stop is left after it."""
    last = furthest(steps, done)
    since = as_time(done.get(steps[last].get("id"))) if last >= 0 else None
    total = 0
    for step in steps[last + 1:]:
        total += minutes.get(step.get("id"), DEFAULT_MINUTES.get(step.get("type"), 30))
        if step.get("type") == STOP:
            return step, (since or started_at) + timedelta(minutes=total)
    return None


def mark_done(
    started_at: datetime, steps: list[dict], done: dict, step_id: str,
    at: Optional[datetime], now: datetime,
) -> Optional[dict]:
    """The trip's done times with `step_id` marked, or None when it is not a
    step of the day or is marked already (a second tap). Any step can be
    marked, in any order. `at` is when the traveller tapped, which a retry
    after a dropped connection keeps; it is held between the step's start (the
    last step before it marked, or the start) and now."""
    if step_id in done or all(s.get("id") != step_id for s in steps):
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
    """The done times without the last step marked, in the day's order (what
    an app from before marking in any order sends)."""
    marked = [s.get("id") for s in steps if s.get("id") in done]
    return {k: v for k, v in done.items() if k != marked[-1]} if marked else dict(done)


def unmark(done: dict, step_id: str) -> dict:
    """The done times without `step_id`: any step marked can be taken back."""
    return {k: v for k, v in done.items() if k != step_id}


def finished_time(steps: list[dict], done: dict) -> Optional[datetime]:
    """When the trip finished: when its last stop (the last step, in a day
    with none) was marked; None until then."""
    stops = [s for s in steps if s.get("type") == STOP] or steps
    return as_time(done.get(stops[-1].get("id"))) if stops else None


def still_skipped(skipped: list, done: dict) -> list[str]:
    """The skipped steps that are still marked: an undone skip drops out."""
    return [s for s in skipped or [] if s in done]


def all_done(steps: list[dict], done: dict) -> bool:
    return bool(steps) and all(s.get("id") in done for s in steps)


def _next_stop(steps: list[dict], index: int) -> Optional[dict]:
    return next((s for s in steps[index + 1:] if s.get("type") == STOP), None)


def reminder_text(steps: list[dict], step: dict) -> tuple[str, str]:
    """The push for a stop past its planned time: (title, body)."""
    index = next((i for i, s in enumerate(steps) if s.get("id") == step.get("id")), 0)
    title = f"Done at {step.get('name') or 'this stop'}?"
    nxt = _next_stop(steps, index)
    if nxt is None:
        return title, "That's the last stop. Mark it visited to finish your trip."
    after = steps[index + 1]
    if after.get("type") == MOVE:
        how = TRANSPORT_MODES.get(after.get("mode") or "walk", "Walk")
        where = f" to {nxt['name']}" if nxt.get("name") else ""
        return title, f"Next: {how}{where}. Mark it visited to update your times."
    if after.get("type") == BREAK:
        return title, f"Next: {after.get('title') or 'a break'}. Mark it visited to update your times."
    return title, f"Next: {nxt.get('name') or 'the next stop'}. Mark it visited to update your times."


def trip_day_id(trip, content: dict) -> Optional[str]:
    """The id of the day a trip follows (the first day's, for a trip from
    before days)."""
    day = find_day(content, trip.day_id)
    return (day or {}).get("id") or trip.day_id


def ends_on_start(trip, day_id: Optional[str], content: dict) -> bool:
    """Whether starting the day [day_id] ends this trip, still shown: a
    running one does (one trip runs at a time), and so does that same day's
    earlier one. Other days' finished trips stay, so a day done keeps its
    ticks when the next day starts."""
    return trip.finished_at is None or trip_day_id(trip, content) == day_id


def other_days(shown: list, content: dict) -> list:
    """The finished trips of the other days, from the trips still shown
    newest first (the first is the trip in hand): the newest for each day."""
    if not shown:
        return []
    seen = {trip_day_id(shown[0], content)}
    out = []
    for trip in shown[1:]:
        day_id = trip_day_id(trip, content)
        if trip.finished_at is None or day_id in seen:
            continue
        seen.add(day_id)
        out.append(trip)
    return out


def view(trip, content: dict) -> dict:
    """A trip as the app reads it: the times saved, and every step's minutes."""
    return {
        "id": str(trip.id),
        "tour_id": str(trip.tour_id),
        "day_id": trip_day_id(trip, content),
        "started_at": trip.started_at.isoformat(),
        "finished_at": trip.finished_at.isoformat() if trip.finished_at else None,
        "done": dict(trip.done or {}),
        "skipped": still_skipped(trip.skipped, trip.done or {}),
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
        steps = trip_steps(tour.live_content, trip.day_id)
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
