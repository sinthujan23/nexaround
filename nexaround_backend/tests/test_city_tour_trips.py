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

    # Rides are not ticked: next is the stop, after the metro and its own time.
    late = T0 + timedelta(minutes=130)
    step, ends = trips.due_step(T0, steps, {"a": late.isoformat()}, plan)
    assert step["id"] == "c" and ends == late + timedelta(minutes=20 + 150)
    # A ride ticked by an app from before still counts.
    step, ends = trips.due_step(T0, steps, {"a": late.isoformat(), "b": late.isoformat()}, plan)
    assert step["id"] == "c" and ends == late + timedelta(minutes=150)

    every = {s["id"]: (T0 + timedelta(hours=1)).isoformat() for s in steps}
    assert trips.due_step(T0, steps, every, plan) is None


def test_mark_done_any_step_in_any_order():
    steps = _steps()
    now = T0 + timedelta(minutes=90)
    done = trips.mark_done(T0, steps, {}, "a", None, now)
    assert done == {"a": now.isoformat()}
    # A stop further on can be ticked first, and the one passed over later.
    ahead = trips.mark_done(T0, steps, {}, "c", None, now)
    assert ahead == {"c": now.isoformat()}
    later = now + timedelta(minutes=5)
    assert trips.mark_done(T0, steps, ahead, "a", None, later) == {**ahead, "a": later.isoformat()}
    # One already done (a second tap), or not in the day, changes nothing.
    assert trips.mark_done(T0, steps, done, "a", None, now) is None
    assert trips.mark_done(T0, steps, {}, "gone", None, now) is None


def test_the_step_in_hand_follows_the_furthest_step_marked():
    steps = _steps()
    plan = trips.plan_minutes({"steps": steps})
    at = T0 + timedelta(minutes=40)
    # "c" ticked first: "a" was passed over, and "e" is in hand (walk "d" on the way).
    step, ends = trips.due_step(T0, steps, {"c": at.isoformat()}, plan)
    assert step["id"] == "e" and ends == at + timedelta(minutes=plan["d"] + plan["e"])
    # Ticking the passed-over stop later does not move the stop in hand.
    both = {"c": at.isoformat(), "a": (at + timedelta(minutes=30)).isoformat()}
    step, ends = trips.due_step(T0, steps, both, plan)
    assert step["id"] == "e" and ends == at + timedelta(minutes=plan["d"] + plan["e"])
    assert trips.furthest(steps, {}) == -1 and trips.furthest(steps, both) == 2


def test_any_step_can_be_taken_back():
    steps = _steps()
    done = {"a": T0.isoformat(), "c": T0.isoformat()}
    assert trips.unmark(done, "a") == {"c": T0.isoformat()}
    assert trips.unmark(done, "b") == done
    step, _ = trips.due_step(T0, steps, trips.unmark(done, "c"), trips.plan_minutes({"steps": steps}))
    assert step["id"] == "c"


def test_the_trip_finishes_when_its_last_stop_is_ticked():
    steps = _steps()
    end = T0 + timedelta(hours=5)
    # Stops passed over do not hold it back; taking the last one back reopens it.
    assert trips.finished_time(steps, {"e": end.isoformat()}) == end
    assert trips.finished_time(steps, {"a": end.isoformat()}) is None
    assert trips.finished_time([], {}) is None
    assert trips.due_step(T0, steps, {"e": end.isoformat()}, {}) is None
    # A ride or break after the last stop doesn't need ticking.
    tail = [*steps, {"id": "f", "type": "move", "mode": "walk"}]
    assert trips.finished_time(tail, {"e": end.isoformat()}) == end
    assert trips.due_step(T0, tail, {"e": end.isoformat()}, {}) is None


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


def test_an_undone_skip_is_no_longer_skipped():
    steps = _steps()
    done = {"a": T0.isoformat(), "b": (T0 + timedelta(minutes=5)).isoformat()}
    assert trips.still_skipped(["b"], done) == ["b"]
    undone = trips.undo_last(steps, done)
    assert trips.still_skipped(["b"], undone) == []
    assert trips.still_skipped(None, done) == []


def test_the_trip_view_lists_skipped_steps():
    class Trip:
        id = "t1"
        tour_id = "g1"
        day_id = None
        started_at = T0
        finished_at = None
        done = {"a": T0.isoformat(), "b": T0.isoformat()}
        skipped = ["b", "gone"]

    view = trips.view(Trip(), {"steps": _steps()})
    assert view["skipped"] == ["b"]
    assert set(view["done"]) == {"a", "b"}


def test_reminder_text():
    steps = _steps()
    assert trips.reminder_text(steps, steps[0]) == (
        "Done at Eiffel Tower?", "Next: Metro to Louvre. Mark it visited to update your times.",
    )
    assert trips.reminder_text(steps, steps[4]) == (
        "Done at Notre-Dame?", "That's the last stop. Mark it visited to finish your trip.",
    )


# ── Trips follow one day ─────────────────────────────────────────────────────

def _two_days():
    from app.services import city_tours as ct
    return ct.normalize({
        "city": "Paris", "country": "France",
        "days": [
            {"title": "Day one", "starts_at": "09:00", "steps": [
                {"type": "stop", "name": "Eiffel Tower", "lat": 48.85, "lng": 2.29, "time_here": "2 hr"},
                {"type": "break", "title": "Lunch / Rest", "duration": "45 min"},
            ]},
            {"title": "Day two", "starts_at": "09:00", "steps": [
                {"type": "stop", "name": "Louvre", "lat": 48.86, "lng": 2.33, "time_here": "3 hr"},
            ]},
        ],
    })


def test_a_trip_follows_its_own_day():
    content = _two_days()
    first, second = content["days"]
    assert [s["name"] for s in trips.trip_steps(content, second["id"])] == ["Louvre"]
    # A trip from before days follows the first day.
    assert [s.get("name") or s.get("title") for s in trips.trip_steps(content, None)] == ["Eiffel Tower", "Lunch / Rest"]
    assert trips.trip_steps(content, "no-such-day") == []


def test_breaks_plan_their_own_minutes():
    content = _two_days()
    minutes = trips.plan_minutes(content)
    brk = content["days"][0]["steps"][1]
    assert minutes[brk["id"]] == 45
    assert trips.step_minutes({"type": "break", "duration": ""}) == 45


def test_stop_reminder_names_the_break_next():
    steps = [
        {"id": "a", "type": "stop", "name": "Louvre"},
        {"id": "b", "type": "break", "title": "Lunch / Rest"},
        {"id": "c", "type": "stop", "name": "Musée d'Orsay"},
    ]
    title, body = trips.reminder_text(steps, steps[0])
    assert title == "Done at Louvre?" and body.startswith("Next: Lunch / Rest.")


def test_a_live_guide_from_before_days_still_plans_its_trip():
    from app.services import city_tours as ct
    stored = {"city": "Paris", "steps": [
        {"id": "s1", "type": "stop", "name": "Eiffel Tower", "time_here": "1 h"},
        {"id": "s2", "type": "move", "mode": "walk", "duration": "10 min"},
        {"id": "s3", "type": "stop", "name": "Louvre", "time_here": "2 h"},
    ]}
    assert [s["id"] for s in trips.trip_steps(stored, None)] == ["s1", "s2", "s3"]
    assert [s["id"] for s in trips.trip_steps(stored, ct.LEGACY_DAY_ID)] == ["s1", "s2", "s3"]
    assert trips.plan_minutes(stored) == {"s1": 60, "s2": 10, "s3": 120}


# ── A day done keeps its ticks when the next day starts ─────────────────────

def _trip(day_id, finished=True):
    from types import SimpleNamespace
    return SimpleNamespace(day_id=day_id, finished_at=T0 if finished else None)


def test_starting_a_day_keeps_other_days_finished():
    content = _two_days()
    first, second = (d["id"] for d in content["days"])
    # Day 1 finished stays when Day 2 starts.
    assert not trips.ends_on_start(_trip(first), second, content)
    # A running trip ends, whatever its day.
    assert trips.ends_on_start(_trip(first, finished=False), second, content)
    # Starting a day again ends that day's earlier trip.
    assert trips.ends_on_start(_trip(second), second, content)
    # A trip from before days is the first day's.
    assert trips.ends_on_start(_trip(None), first, content)
    assert not trips.ends_on_start(_trip(None), second, content)


def test_other_days_lists_each_finished_day_once():
    content = _two_days()
    first, second = (d["id"] for d in content["days"])
    in_hand = _trip(second, finished=False)
    day_one = _trip(first)
    older_day_one = _trip(None)
    assert trips.other_days([in_hand, day_one, older_day_one], content) == [day_one]
    # The trip in hand's own day is never listed again.
    assert trips.other_days([day_one, older_day_one], content) == []
    # Only finished ones.
    assert trips.other_days([in_hand, _trip(first, finished=False)], content) == []
    assert trips.other_days([], content) == []
