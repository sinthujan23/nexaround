"""What an accommodation row is allowed to claim a night costs.

Hotels are searched city by city — `generate_hotel_strategies_for_legs` gives
each leg its own coordinates, its own dates and its own `leg_index`. The
itinerary then threw that grouping away: one min/max across every city was
printed on every day of the trip.

On a live 14-day Japan plan that read "INR 4,507 - 28,232 / night" on all five
cities at once. The floor is an Osaka hotel; a traveller budgeting it for the
Hakone leg, 400 km away, is short by 3x, because Hakone's own rooms start at
14,932. The same string overstated Osaka by putting a Hakone ryokan's ceiling
on it.

The rule pinned here: **a day quotes the city it sleeps in, or says plainly
that it is falling back.**
"""
import pytest

from app.services.odyssey_ai_service import (
    nightly_ranges,
    stay_basis_for_day,
    stay_cost_row,
)


def _room(nightly, leg_index, city):
    return {
        "name": f"{city} hotel",
        "price_per_night": f"INR {nightly}",
        "leg_index": leg_index,
        "city": city,
    }


@pytest.fixture
def japan():
    """The five-city plan that exposed this, with its real rates."""
    return {"strategies": [
        _room(4507, 0, "Osaka"),   _room(6404, 0, "Osaka"),
        _room(4676, 1, "Kyoto"),   _room(7833, 1, "Kyoto"),
        _room(11404, 2, "Kanazawa"), _room(13820, 2, "Kanazawa"),
        _room(14932, 3, "Hakone"), _room(28232, 3, "Hakone"),
        _room(6344, 4, "Tokyo"),   _room(8916, 4, "Tokyo"),
    ]}


@pytest.fixture
def japan_legs():
    return [
        {"city": "Osaka", "start_day": 1, "end_day": 3},
        {"city": "Kyoto", "start_day": 4, "end_day": 6},
        {"city": "Kanazawa", "start_day": 7, "end_day": 8},
        {"city": "Hakone", "start_day": 9, "end_day": 11},
        {"city": "Tokyo", "start_day": 12, "end_day": 14},
    ]


def test_each_leg_keeps_its_own_range(japan):
    trip, by_leg = nightly_ranges(japan, "INR")
    assert trip == "INR 4,507 - 28,232", "the trip-wide range still exists as a fallback"
    assert by_leg[0] == "INR 4,507 - 6,404"
    assert by_leg[3] == "INR 14,932 - 28,232"
    assert len(by_leg) == 5


def test_the_hakone_day_no_longer_advertises_an_osaka_rate(japan, japan_legs):
    """The exact regression, at the day the traveller would have read it."""
    trip, by_leg = nightly_ranges(japan, "INR")
    rng, city = stay_basis_for_day(9, japan_legs, by_leg, trip)
    assert city == "Hakone"
    assert rng == "INR 14,932 - 28,232"
    assert "4,507" not in rng, "an Osaka floor 400 km away"

    cost, basis = stay_cost_row(rng, city)
    assert cost == "INR 14,932 - 28,232 / night"
    assert "in Hakone" in basis
    assert "for this trip" not in basis, "the wording that made a global range look deliberate"


@pytest.mark.parametrize("day,city,low", [
    (1, "Osaka", "4,507"), (3, "Osaka", "4,507"),
    (4, "Kyoto", "4,676"), (7, "Kanazawa", "11,404"),
    (11, "Hakone", "14,932"), (14, "Tokyo", "6,344"),
])
def test_every_day_maps_to_the_city_it_sleeps_in(japan, japan_legs, day, city, low):
    trip, by_leg = nightly_ranges(japan, "INR")
    rng, got = stay_basis_for_day(day, japan_legs, by_leg, trip)
    assert got == city
    assert rng.startswith(f"INR {low}")


def test_a_leg_whose_search_came_back_empty_falls_back_to_the_trip(japan_legs):
    """Two cities searched, five legs planned: the other three still price.

    The fallback is load-bearing, not defensive - a leg can fail its search,
    and a rate from a neighbouring city is closer than no rate at all.
    """
    stays = {"strategies": [_room(4507, 0, "Osaka"), _room(28232, 3, "Hakone")]}
    trip, by_leg = nightly_ranges(stays, "INR")
    assert stay_basis_for_day(5, japan_legs, by_leg, trip) == (trip, "Kyoto")
    assert stay_basis_for_day(9, japan_legs, by_leg, trip)[0] == "INR 28,232"


def test_a_single_city_plan_is_unchanged(japan_legs):
    """One leg means the per-city range and the trip range are the same string."""
    stays = {"strategies": [_room(4507, 0, "Osaka"), _room(6404, 0, "Osaka")]}
    trip, by_leg = nightly_ranges(stays, "INR")
    assert by_leg[0] == trip == "INR 4,507 - 6,404"


def test_a_day_outside_every_leg_still_prices(japan, japan_legs):
    trip, by_leg = nightly_ranges(japan, "INR")
    rng, city = stay_basis_for_day(99, japan_legs, by_leg, trip)
    assert (rng, city) == (trip, "")
    assert stay_cost_row(rng, city)[1].endswith("found for this trip: INR 4,507 - 28,232.")


def test_one_room_in_a_city_prints_a_single_figure(japan_legs):
    stays = {"strategies": [_room(9000, 2, "Kanazawa")]}
    _, by_leg = nightly_ranges(stays, "INR")
    assert by_leg[2] == "INR 9,000", "no ' - ' when there is nothing to range between"


def test_no_hotels_at_all_says_so_instead_of_inventing_a_range():
    trip, by_leg = nightly_ranges({}, "INR")
    assert (trip, by_leg) == ("", {})
    assert stay_cost_row("", "Osaka") == (
        "See Stays tab", "See the Stays tab for hotel pricing options.",
    )


def test_an_unpriced_or_mislabelled_room_cannot_move_a_range():
    """A strategy with no parseable rate, or a bool where the leg index goes."""
    stays = {"strategies": [
        _room(4507, 0, "Osaka"),
        {"name": "no price", "leg_index": 0, "city": "Osaka"},
        {"name": "bool leg", "price_per_night": "INR 1", "leg_index": True, "city": "?"},
        "not a dict",
    ]}
    trip, by_leg = nightly_ranges(stays, "INR")
    assert by_leg == {0: "INR 4,507"}
    assert trip == "INR 1 - 4,507", "the stray rate still counts trip-wide, but lands on no leg"
