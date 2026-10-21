"""Active explorers per week, and who comes back most (admin Users page).

`_activity_view` turns per-day activity into buckets. Nothing here needs a
database: the endpoint's SQL only feeds it `days` and `people`.
"""
import uuid
from datetime import date, datetime, timedelta, timezone

from app.api.v1.admin import _activity_view

A, B, C = (uuid.uuid4() for _ in range(3))
WEEKS = [date(2026, 10, 5), date(2026, 10, 12)]  # Mondays


def monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def person(joined: date, last_hour: int) -> dict:
    return {
        "display_name": "x", "email": "x@example.com", "avatar_url": None,
        "joined": joined, "last": datetime(2026, 10, 18, last_hour, tzinfo=timezone.utc),
    }


PEOPLE = {
    A: person(date(2026, 9, 1), 1),
    B: person(date(2026, 10, 13), 2),   # signed up in the second week
    C: person(date(2026, 9, 1), 3),
}
DAYS = {
    date(2026, 9, 28): {C: (5, 500)},             # before the window: ignored
    date(2026, 10, 6): {A: (2, 60), C: (1, 30)},
    date(2026, 10, 7): {A: (1, 30)},
    date(2026, 10, 13): {A: (1, 10), B: (3, 90)},
    date(2026, 10, 14): {B: (0, 0)},              # API activity, no session
}


def test_buckets_count_each_explorer_once_per_week():
    view = _activity_view(WEEKS, monday, DAYS, PEOPLE)
    first, second = view.buckets
    assert (first.start, first.active, first.sessions, first.app_seconds) == (WEEKS[0], 2, 4, 120)
    assert (second.active, second.sessions, second.app_seconds) == (2, 4, 100)


def test_new_means_signed_up_in_that_bucket():
    first, second = _activity_view(WEEKS, monday, DAYS, PEOPLE).buckets
    assert first.new == 0
    assert second.new == 1


def test_most_frequent_ranks_by_buckets_active_then_sessions():
    top = _activity_view(WEEKS, monday, DAYS, PEOPLE).top
    assert [(t.id, t.active_periods, t.sessions) for t in top] == [
        (A, 2, 4), (B, 1, 3), (C, 1, 1),
    ]
