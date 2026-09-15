"""Where the traveller asked the trip to start and finish.

The route planner picks the cities itself and keeps them in one coherent
region, so nobody spends half the trip in transit. Entry and exit outrank that:
the traveller may have a flight already booked into one city, or a wedding to
get to in another. Both are optional and independent - either may be given
alone, and the planner chooses the other end.

When the two pull the route further than the days comfortably cover, it is
built anyway and the plan says so, the way a budget that will not stretch is
explained rather than quietly trimmed.
"""
import pytest

from app.services import odyssey_ai_service as svc
from app.services.odyssey_ai_service import RoutePlan


def _prompt(**kw):
    args = dict(
        destination="India", days=5, mood="Cultural", travelers=2,
        geo=None, origin_line="",
    )
    args.update(kw)
    return svc._route_prompt(**args)


# ── The rules the planner is given ─────────────────────────────────────────

def test_nothing_is_said_when_neither_end_was_chosen():
    p = _prompt()
    assert "TRAVELLER STARTS" not in p
    assert "TRAVELLER FINISHES" not in p


def test_an_entry_city_becomes_the_first_leg_and_sets_the_arrival_airport():
    p = _prompt(entry_city="Kandy")
    assert "THE TRAVELLER STARTS AT Kandy" in p
    assert '"arrival_airport" MUST be the airport with scheduled flights nearest Kandy' in p
    # A city with no airport of its own is reached by road, not refused.
    assert "the nearest one that has, and the traveller reaches Kandy from it by road" in p


def test_an_exit_city_becomes_the_last_leg_and_sets_the_departure_airport():
    p = _prompt(exit_city="Galle")
    assert "THE TRAVELLER FINISHES AT Galle" in p
    assert '"departure_airport" MUST be the airport nearest it' in p


def test_either_end_may_be_given_alone():
    """Blank means "you choose", not "use the other one"."""
    entry_only = _prompt(entry_city="Kandy")
    exit_only = _prompt(exit_city="Galle")
    assert "TRAVELLER FINISHES" not in entry_only
    assert "TRAVELLER STARTS" not in exit_only


def test_both_ends_add_the_no_backtracking_rule():
    p = _prompt(entry_city="Delhi", exit_city="Chennai")
    assert "Order the cities between Delhi and Chennai" in p
    assert "rather than dropping either end" in p


def test_the_same_city_at_both_ends_is_a_round_trip_not_a_route():
    p = _prompt(entry_city="Delhi", exit_city="delhi")
    assert "Order the cities between" not in p
    assert "THE TRAVELLER STARTS AT Delhi" in p


def test_the_chosen_ends_are_allowed_to_beat_the_clustering_rule():
    """Stated in the prompt, because the model is told to cluster right below."""
    p = _prompt(entry_city="Delhi")
    assert "whatever the clustering rule below would otherwise prefer" in p
    assert p.index("THE TRAVELLER STARTS") < p.index("CLUSTER THE ROUTE")


# ── Telling the traveller when their two ends are far apart ────────────────

def _route(a, b, lat1, lng1, lat2, lng2):
    return RoutePlan(legs=[
        {"city": a, "latitude": lat1, "longitude": lng1},
        {"city": b, "latitude": lat2, "longitude": lng2},
    ])


DELHI_CHENNAI = ("Delhi", "Chennai", 28.61, 77.21, 13.08, 80.27)      # ~1,756 km
ROME_FLORENCE = ("Rome", "Florence", 41.90, 12.50, 43.77, 11.26)      # ~230 km


@pytest.mark.parametrize("days", [3, 4, 5])
def test_a_short_trip_between_distant_ends_is_flagged(days):
    notice = svc.stretched_route_notice(
        _route(*DELHI_CHENNAI), days, "Delhi", "Chennai")
    assert "1,756 km apart" in notice
    assert f"{days} days" in notice
    assert "Both were asked for, so the route keeps them." in notice


@pytest.mark.parametrize("days", [8, 14])
def test_the_same_ends_over_more_days_are_not_flagged(days):
    assert svc.stretched_route_notice(
        _route(*DELHI_CHENNAI), days, "Delhi", "Chennai") == ""


def test_neighbouring_cities_are_never_flagged():
    assert svc.stretched_route_notice(
        _route(*ROME_FLORENCE), 4, "Rome", "Florence") == ""


def test_nothing_is_said_unless_both_ends_were_chosen():
    route = _route(*DELHI_CHENNAI)
    assert svc.stretched_route_notice(route, 4) == ""
    assert svc.stretched_route_notice(route, 4, entry_city="Delhi") == ""
    assert svc.stretched_route_notice(route, 4, exit_city="Chennai") == ""


def test_a_round_trip_is_not_a_stretch():
    assert svc.stretched_route_notice(
        _route("Delhi", "Delhi", 28.61, 77.21, 28.61, 77.21), 4, "Delhi", "Delhi") == ""


def test_a_route_with_no_coordinates_says_nothing_rather_than_guessing():
    route = RoutePlan(legs=[{"city": "Delhi"}, {"city": "Chennai"}])
    assert svc.stretched_route_notice(route, 4, "Delhi", "Chennai") == ""
    assert svc.stretched_route_notice(RoutePlan(legs=[]), 4, "Delhi", "Chennai") == ""
