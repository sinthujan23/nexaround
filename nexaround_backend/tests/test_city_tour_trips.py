"""City Tours trips: planned minutes, the step in hand, Mark done and reminders."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services import city_tour_trips as trips

T0 = datetime(2026, 10, 28, 9, 0, tzinfo=timezone.utc)


def _steps():
    return [
        {"id": "a", "type": "stop", "name": "Eiffel Tower", "time_here": "1.5–2 hours"},
        {"id": "b", "type": "move", "mode": "metro", "duration": "20 min"},
        {"id": "c", "type": "stop", "name": "Louvre", "time_here": "2–3 hours"},
        {"id": "d", "type": "move", "mode": "walk", "duration": ""},
        {"id": "e", "type": "stop", "name": "Notre-Dame", "time_here": "45 min–1 hour"},
    ]


@pytest.mark.parametrize("text, minutes", [
    ("20 min", 20),
    ("1.5–2 hours", 105),
    ("45 min–1 hour", 55),
    ("2–3 hours", 150),
    ("1-2 hrs", 90),
    ("1 h", 60),
    ("1h30", 90),
    ("1 h 30 min", 90),
    ("90 mins", 90),
    ("1:30", 90),
    ("half an hour", 30),
    ("an hour", 60),
    ("1½ hours", 90),
    ("2 to 3 hours", 150),
    ("10 minutes", 10),
    ("3 min", 5),
    ("", None),
    ("a while", None),
    ("45", None),
])
def test_parse_minutes(text, minutes):
    assert trips.parse_minutes(text) == minutes


def test_plan_minutes_uses_defaults_for_unreadable_times():
    plan = trips.plan_minutes({"steps": _steps()})
    assert plan == {"a": 105, "b": 20, "c": 150, "d": trips.DEFAULT_MINUTES["move"], "e": 55}


def test_due_step_follows_the_last_done_time():
    steps = _steps()
    plan = trips.plan_minutes({"steps": steps})
    step, ends = trips.due_step(T0, steps, {}, plan)
    assert step["id"] == "a" and ends == T0 + timedelta(minutes=105)

    late = T0 + timedelta(minutes=130)
    step, ends = trips.due_step(T0, steps, {"a": late.isoformat()}, plan)
    assert step["id"] == "b" and ends == late + timedelta(minutes=20)

    every = {s["id"]: (T0 + timedelta(hours=1)).isoformat() for s in steps}
    assert trips.due_step(T0, steps, every, plan) is None


def test_mark_done_only_the_step_in_hand():
    steps = _steps()
    now = T0 + timedelta(minutes=90)
    done = trips.mark_done(T0, steps, {}, "a", None, now)
    assert done == {"a": now.isoformat()}
    # A later step first, or one already done, is not the step in hand.
    assert trips.mark_done(T0, steps, {}, "c", None, now) is None
    assert trips.mark_done(T0, steps, done, "a", None, now) is None


def test_mark_done_keeps_the_tap_time_within_the_step():
    steps = _steps()
    now = T0 + timedelta(minutes=95)
    tapped = T0 + timedelta(minutes=88)
    assert trips.mark_done(T0, steps, {}, "a", tapped, now)["a"] == tapped.isoformat()
    # Before the step began, or in the future: held to the step's start, or now.
    assert trips.mark_done(T0, steps, {}, "a", T0 - timedelta(hours=1), now)["a"] == T0.isoformat()
    assert trips.mark_done(T0, steps, {}, "a", now + timedelta(hours=1), now)["a"] == now.isoformat()
    done_a = {"a": (T0 + timedelta(minutes=60)).isoformat()}
    held = trips.mark_done(T0, steps, done_a, "b", T0 + timedelta(minutes=10), now)
    assert held["b"] == done_a["a"]


def test_undo_last_and_all_done():
    steps = _steps()
    every = {s["id"]: T0.isoformat() for s in steps}
    assert trips.all_done(steps, every)
    undone = trips.undo_last(steps, every)
    assert "e" not in undone and not trips.all_done(steps, undone)
    assert trips.undo_last(steps, {}) == {}


def test_reminder_text():
    steps = _steps()
    assert trips.reminder_text(steps, steps[0]) == (
        "Done at Eiffel Tower?", "Next: Metro to Louvre. Mark it done to update your times.",
    )
    assert trips.reminder_text(steps, steps[1])[0] == "Arrived at Louvre?"
    assert trips.reminder_text(steps, steps[4]) == (
        "Done at Notre-Dame?", "That's the last stop. Mark it done to finish your trip.",
    )
