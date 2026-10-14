"""The "Near you" order of the Travel Stories feed.

Stories are grouped by distance band and shown newest first inside a band;
a story with no position goes last. Nothing needs a database: the ordering
is a pure function over (story, distance) pairs.
"""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from app.api.v1.travel_stories import _distance_m, _order_nearby

TRINCOMALEE = (8.5874, 81.2152)
NOW = datetime(2026, 10, 14, tzinfo=timezone.utc)


def story(name, lat, lng, days_old):
    return SimpleNamespace(
        name=name, latitude=lat, longitude=lng,
        created_at=NOW - timedelta(days=days_old),
    )


def ordered(stories, here=TRINCOMALEE):
    pairs = [(s, _distance_m(s, *here)) for s in stories]
    return [s.name for s, _ in _order_nearby(pairs)]


def test_nearer_band_comes_first_even_when_older():
    stories = [
        story("tokyo_new", 35.658, 139.702, 0),
        story("colombo", 6.927, 79.861, 5),
        story("nilaveli_old", 8.700, 81.192, 300),
    ]
    assert ordered(stories) == ["nilaveli_old", "colombo", "tokyo_new"]


def test_newest_first_inside_a_band():
    # Both within 25 km of Trincomalee; the nearer one is older.
    stories = [
        story("near_but_old", 8.600, 81.215, 200),
        story("bit_further_but_new", 8.722, 81.203, 1),
    ]
    assert ordered(stories) == ["bit_further_but_new", "near_but_old"]


def test_stories_without_a_position_go_last():
    stories = [
        story("no_coords", None, None, 0),
        story("zero_zero", 0.0, 0.0, 0),
        story("tokyo", 35.658, 139.702, 30),
    ]
    assert ordered(stories)[0] == "tokyo"
    assert set(ordered(stories)[1:]) == {"no_coords", "zero_zero"}


def test_distance_is_none_without_a_position():
    assert _distance_m(story("x", None, 81.0, 0), *TRINCOMALEE) is None
    assert _distance_m(story("x", 0.0, 0.0, 0), *TRINCOMALEE) is None


def test_distance_is_metres():
    pigeon_island = story("p", 8.722, 81.203, 0)
    d = _distance_m(pigeon_island, *TRINCOMALEE)
    assert 14_000 < d < 16_000
