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


# ── One country, both ends ─────────────────────────────────────────────────
#
# TL and client, 2026-09-15: the country dropdown goes, Entry becomes required
# and takes either a country or a city, Exit stays optional — and a trip cannot
# start in one country and finish in another. The app holds the Exit search to
# the Entry's country, so the pair should always agree; the prompt says what to
# do when they do not, because the API can be called without the app.

def _sri_lanka():
    from app.services.geo_resolver import DestinationContext
    return DestinationContext(
        query="Sri Lanka", name="Sri Lanka", country="Sri Lanka",
        country_code="LK", latitude=7.87, longitude=80.77,
        types=("country",), source="places",
    )


def test_an_end_outside_the_country_is_dropped_not_obeyed():
    p = _prompt(destination="Sri Lanka", geo=_sri_lanka(),
                entry_city="Kandy", exit_city="Chennai")
    assert "If either of those two places is not in Sri Lanka" in p
    assert "choose that end yourself" in p
    assert "A trip starts and finishes in the same country" in p


def test_the_country_rule_outranks_the_two_ends():
    """Both are in the prompt; the order they resolve in has to be stated."""
    p = _prompt(destination="Sri Lanka", geo=_sri_lanka(),
                entry_city="Kandy", exit_city="Galle")
    assert "the country rule below outranks both" in p
    assert p.index("THE TRAVELLER STARTS") < p.index("EVERY leg must be a real city")


def test_the_rule_is_only_stated_when_an_end_was_asked_for():
    p = _prompt(destination="Sri Lanka", geo=_sri_lanka())
    assert "is not in Sri Lanka" not in p


def test_no_country_resolved_means_no_country_rule_to_state():
    """Nothing to hold the ends to, so nothing is claimed about them."""
    p = _prompt(entry_city="Kandy", exit_city="Galle")
    assert "THE TRAVELLER STARTS AT Kandy" in p
    assert "ignore that one" not in p


def test_a_country_named_as_the_destination_still_takes_an_entry_city():
    """Entry is now the destination field, so "Sri Lanka" and "Kandy" both
    arrive here — the planner opens at the city when one was named."""
    p = _prompt(destination="Sri Lanka", geo=_sri_lanka(), entry_city="Kandy")
    assert "THE TRAVELLER STARTS AT Kandy" in p
    assert "TRAVELLER FINISHES" not in p


# ── The coordinates behind the two names ───────────────────────────────────
#
# The app picks entry and exit from Google and knows where they are to the
# metre. Sending only the name made the planner infer the location, and its
# inference becomes that leg's coordinates — which the hotel search and every
# distance check downstream are then measured against.

def test_the_coordinates_the_app_picked_are_stated():
    p = _prompt(entry_city="Kandy", exit_city="Galle",
                entry_latlng=(7.2906, 80.6337), exit_latlng=(6.0535, 80.2210))
    assert "STARTS AT Kandy at 7.2906, 80.6337" in p
    assert "FINISHES AT Galle at 6.0535, 80.2210" in p
    assert p.count("with exactly those coordinates") == 2


def test_a_name_without_coordinates_still_works():
    """Older app builds send no coordinates; the rule just loses its anchor."""
    p = _prompt(entry_city="Kandy", exit_city="Galle")
    assert "STARTS AT Kandy." in p
    assert "with exactly those coordinates" not in p


def test_one_end_located_and_the_other_not():
    p = _prompt(entry_city="Kandy", exit_city="Galle", entry_latlng=(7.2906, 80.6337))
    assert "STARTS AT Kandy at 7.2906" in p
    assert "FINISHES AT Galle." in p
    assert p.count("with exactly those coordinates") == 1


@pytest.mark.parametrize("bad", [
    (None, None), (7.29, None), (None, 80.63), (), (7.29,), "7.29,80.63", None,
    ("not", "a number"),
])
def test_an_unusable_pair_is_ignored_rather_than_printed(bad):
    """A half-pair or a malformed one says nothing, instead of an anchor that
    points somewhere the traveller never picked."""
    p = _prompt(entry_city="Kandy", entry_latlng=bad)
    assert "STARTS AT Kandy." in p
    assert "with exactly those coordinates" not in p
