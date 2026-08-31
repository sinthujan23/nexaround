"""The flight tiers a traveller actually sees on the Odyssey Flights tab.

Before this, Minimum/Recommended/Comfortable were labels the app stuck onto one
LLM-written list by price rank, so all three tabs showed the same fares — and
the fares themselves had no defined basis (one-way or return? one seat or the
whole party?). These tests pin down the replacement: three genuinely different
itineraries selected from live Google Flights results, every price per
traveller for the whole return journey.
"""
import pytest

from app.services.serpapi_service import extract_flight_strategies_from_serpapi


def _leg(dep, arr, airline, number, minutes=300):
    return {
        "departure_airport": {"id": dep, "name": f"{dep} Airport", "time": "2026-09-12 01:30"},
        "arrival_airport": {"id": arr, "name": f"{arr} Airport", "time": "2026-09-12 06:00"},
        "duration": minutes,
        "airline": airline,
        "flight_number": number,
        "travel_class": "Economy",
    }


def _option(price, legs, total_duration, layovers=0):
    return {
        "flights": legs,
        "layovers": [{"duration": 120, "id": "XXX"} for _ in range(layovers)],
        "total_duration": total_duration,
        "price": price,
        "type": "Round trip",
    }


# A realistic spread: a cheap slow triple-hop, a mid one-stop, a fast non-stop.
FIXTURE = {
    "best_flights": [
        _option(
            780,
            [_leg("CMB", "DXB", "Emirates", "EK 651"), _leg("DXB", "LHR", "Emirates", "EK 001")],
            1040,
            layovers=1,
        ),
    ],
    "other_flights": [
        _option(
            612,
            [
                _leg("CMB", "KUL", "AirAsia", "AK 46"),
                _leg("KUL", "DOH", "AirAsia", "AK 12"),
                _leg("DOH", "LGW", "Norwegian", "DY 7"),
            ],
            1680,
            layovers=2,
        ),
        _option(
            1140,
            [_leg("CMB", "LHR", "Qatar Airways", "QR 665", minutes=660)],
            660,
            layovers=0,
        ),
    ],
    "price_insights": {"lowest_price": 612, "typical_price_range": [700, 1200]},
}


def _extract(travelers=1, return_date="2026-09-26", data=None):
    return extract_flight_strategies_from_serpapi(
        data if data is not None else FIXTURE,
        departure_city="Colombo",
        destination="London",
        currency="USD",
        outbound_date="2026-09-12",
        return_date=return_date,
        travelers=travelers,
    )


def _by_tier(result):
    return {s["tier"]: s for s in result["strategies"]}


# ── The bug that prompted this: three tabs, one price ───────────────────────

def test_the_three_tiers_are_three_different_flights():
    tiers = _by_tier(_extract())
    assert set(tiers) == {"minimum", "recommended", "comfortable"}

    identities = {tuple(s["flight_numbers"]) for s in tiers.values()}
    assert len(identities) == 3, "a tier is showing another tier's itinerary"

    prices = {s["price_per_traveler"] for s in tiers.values()}
    assert len(prices) == 3, "tiers must not share a price"


def test_minimum_is_cheapest_and_comfortable_has_fewest_stops():
    tiers = _by_tier(_extract())
    assert tiers["minimum"]["price_per_traveler"] == 612
    assert tiers["comfortable"]["stops"] == 0
    assert tiers["comfortable"]["price_per_traveler"] == 1140
    # Best value lands between the two extremes.
    assert tiers["minimum"]["price_per_traveler"] < tiers["recommended"]["price_per_traveler"]
    assert tiers["recommended"]["price_per_traveler"] < tiers["comfortable"]["price_per_traveler"]


def test_comfortable_is_never_the_slowest_option():
    tiers = _by_tier(_extract())
    assert tiers["comfortable"]["total_duration_minutes"] < tiers["minimum"]["total_duration_minutes"]


# ── The price contract: per traveller, round trip ───────────────────────────

def test_group_total_is_derived_from_the_per_traveller_fare():
    tiers = _by_tier(_extract(travelers=3))
    for s in tiers.values():
        assert s["price_total"] == pytest.approx(s["price_per_traveler"] * 3)
        assert s["price_basis"] == "per_traveler"
        assert s["travelers"] == 3


def test_per_traveller_fare_does_not_change_with_party_size():
    """The fare is one seat's price; only the derived total scales."""
    solo = _by_tier(_extract(travelers=1))
    group = _by_tier(_extract(travelers=4))
    for tier in solo:
        assert solo[tier]["price_per_traveler"] == group[tier]["price_per_traveler"]


def test_trip_type_is_marked_round_trip_when_a_return_was_searched():
    for s in _extract()["strategies"]:
        assert s["trip_type"] == "round_trip"
        assert s["return_date"] == "2026-09-26"


def test_trip_type_is_marked_one_way_without_a_return_date():
    """A one-way fare must announce itself rather than passing as a return fare."""
    for s in _extract(return_date="")["strategies"]:
        assert s["trip_type"] == "one_way"


def test_prices_are_flagged_as_live():
    for s in _extract()["strategies"]:
        assert s["is_live_price"] is True
        assert s["price_source"] == "google_flights_serpapi"
        assert s["currency"] == "USD"


def test_legacy_price_string_agrees_with_the_structured_fare():
    """Older app builds read estimated_price_range; it must not drift."""
    for s in _extract()["strategies"]:
        digits = s["estimated_price_range"].replace(",", "")
        assert str(int(s["price_per_traveler"])) in digits


# ── Small or degenerate result sets ─────────────────────────────────────────

def test_a_thin_result_set_returns_fewer_tiers_rather_than_duplicates():
    thin = {"best_flights": [_option(500, [_leg("CMB", "LHR", "SriLankan", "UL 503")], 660)]}
    result = _extract(data=thin)
    identities = [tuple(s["flight_numbers"]) for s in result["strategies"]]
    assert len(identities) == len(set(identities)), "same flight shown under two tiers"
    assert len(result["strategies"]) <= 3


def test_identical_duplicate_options_are_collapsed():
    dupe = _option(700, [_leg("CMB", "LHR", "SriLankan", "UL 503")], 660)
    result = _extract(data={"best_flights": [dupe, dict(dupe)], "other_flights": []})
    assert len(result["strategies"]) == 1


def test_unpriced_options_are_discarded():
    data = {
        "best_flights": [_option(0, [_leg("CMB", "LHR", "X", "X 1")], 660)],
        "other_flights": [_option(900, [_leg("CMB", "LGW", "Y", "Y 2")], 700)],
    }
    result = _extract(data=data)
    assert all(s["price_per_traveler"] > 0 for s in result["strategies"])
    assert len(result["strategies"]) == 1


def test_no_results_returns_empty_so_the_caller_can_fall_back():
    assert _extract(data={}) == {}
    assert _extract(data={"best_flights": [], "other_flights": []}) == {}


def test_ranks_are_sequential_from_one():
    result = _extract()
    assert [s["rank"] for s in result["strategies"]] == [1, 2, 3]


# ── Routes that genuinely have one fare level ───────────────────────────────

def test_two_flights_at_the_same_price_do_not_fill_two_tiers():
    """Different flight numbers, same offer: 359/non-stop/4h40 twice is one card.

    Observed live on CMB->DXB, where Minimum and Recommended both came back at
    USD 359, non-stop, 4h 40m — indistinguishable to a traveller, and exactly
    the "all three tabs show the same price" complaint.
    """
    data = {
        "best_flights": [
            _option(359, [_leg("CMB", "DXB", "Emirates", "EK 651", minutes=280)], 280),
            _option(359, [_leg("CMB", "DXB", "Emirates", "EK 653", minutes=280)], 280),
        ],
        "other_flights": [
            _option(426, [_leg("CMB", "DXB", "SriLankan", "UL 225", minutes=260)], 260),
        ],
    }
    result = _extract(data=data)
    tiers = {s["tier"] for s in result["strategies"]}
    assert "recommended" not in tiers, "a near-identical offer was given its own tier"
    assert tiers == {"minimum", "comfortable"}


def test_a_price_gap_alone_does_not_earn_a_tier():
    """Same flight time, same stops, just dearer — there is nothing to recommend."""
    data = {
        "best_flights": [
            _option(359, [_leg("CMB", "DXB", "Emirates", "EK 651", minutes=280)], 280),
            _option(395, [_leg("CMB", "DXB", "Emirates", "EK 653", minutes=280)], 280),
        ],
        "other_flights": [
            _option(600, [_leg("CMB", "DXB", "SriLankan", "UL 225", minutes=250)], 250),
        ],
    }
    tiers = {s["tier"] for s in _extract(data=data)["strategies"]}
    assert tiers == {"minimum", "comfortable"}


def test_a_different_stop_count_is_always_a_different_offer():
    """Same price, but non-stop vs one-stop is a real choice."""
    data = {
        "best_flights": [
            _option(500, [_leg("CMB", "DXB", "A", "A 1", minutes=280)], 280),
            _option(
                500,
                [_leg("CMB", "KUL", "B", "B 1"), _leg("KUL", "DXB", "B", "B 2")],
                290,
                layovers=1,
            ),
        ],
    }
    assert len(_extract(data=data)["strategies"]) == 2


# ── Airport code resolution ─────────────────────────────────────────────────
#
# SerpApi's google_flights engine 400s on free-text places and returns zero
# results for IATA *metro* codes. Passing city names, as this service did, meant
# every live flight search failed silently into Gemini estimation. These pin the
# two rules that keep the live path alive.

import asyncio

from app.services.odyssey_ai_service import (
    _METRO_CODES,
    _resolve_airport_code,
)


def _resolve(place, country="", api_key=""):
    return asyncio.run(_resolve_airport_code(place, country, api_key))


def test_known_cities_resolve_without_calling_the_model():
    # No api_key: anything needing Gemini returns "", so a hit here is static.
    assert _resolve("Colombo", "Sri Lanka") == "CMB"
    assert _resolve("Dubai") == "DXB"


def test_a_town_with_no_airport_maps_to_its_nearest_hub():
    assert _resolve("Kinniya", "Sri Lanka") == "CMB"


def test_multi_airport_cities_expand_to_every_airport():
    """'LON' returns nothing from Google Flights; the four airports return 20+."""
    assert _resolve("London") == "LHR,LGW,STN,LTN"
    assert _resolve("New York") == "JFK,EWR,LGA"


def test_a_code_passed_straight_through_is_accepted():
    assert _resolve("CMB") == "CMB"
    assert _resolve("Colombo (CMB)", "Sri Lanka") == "CMB"


def test_metro_codes_never_reach_a_search():
    """A metro code is expanded or dropped — never used as-is."""
    assert _resolve("LON") != "LON"
    for code in _METRO_CODES:
        resolved = _resolve(code)
        assert resolved != code, f"{code} would return zero flight results"


def test_static_table_contains_no_metro_codes():
    from app.services.odyssey_ai_service import _AIRPORT_CODES
    for city, codes in _AIRPORT_CODES.items():
        for code in codes.split(","):
            assert code not in _METRO_CODES, f"{city} maps to metro code {code}"


def test_an_unresolvable_place_returns_empty_rather_than_guessing():
    """Empty tells the caller to skip the search instead of burning a credit."""
    assert _resolve("Xyzzy Nowhere Township") == ""


def test_a_dominated_option_never_becomes_the_recommendation():
    """Costlier, slower AND more stops than the cheapest is not a recommendation.

    Observed live on CMB->DXB: USD 386 / 1 stop / 6h40 was offered as
    "Recommended" beside a USD 359 / non-stop / 4h40 "Minimum".
    """
    data = {
        "best_flights": [
            _option(359, [_leg("CMB", "DXB", "Emirates", "EK 651", minutes=280)], 280),
            _option(
                386,
                [_leg("CMB", "AUH", "Etihad", "EY 1"), _leg("AUH", "DXB", "Etihad", "EY 2")],
                400,
                layovers=1,
            ),
        ],
        "other_flights": [
            _option(426, [_leg("CMB", "DXB", "SriLankan", "UL 225", minutes=260)], 260),
        ],
    }
    tiers = {s["tier"] for s in _extract(data=data)["strategies"]}
    assert tiers == {"minimum", "comfortable"}


def test_a_pricier_but_faster_option_is_still_a_valid_recommendation():
    """Paying more to save four hours is a real trade-off, not domination."""
    data = {
        "best_flights": [
            _option(808, [_leg("CMB", "LGW", "Air Arabia", "G9 509", minutes=1330)], 1330, layovers=1),
            _option(839, [_leg("CMB", "LGW", "Air Arabia", "G9 503", minutes=1065)], 1065, layovers=1),
        ],
        "other_flights": [
            _option(1397, [_leg("CMB", "LHR", "SriLankan", "UL 503", minutes=680)], 680),
        ],
    }
    tiers = {s["tier"] for s in _extract(data=data)["strategies"]}
    assert tiers == {"minimum", "recommended", "comfortable"}
