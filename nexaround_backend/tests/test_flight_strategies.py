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


def test_a_strictly_worse_option_is_not_a_choice():
    """Same fare, one more stop, ten minutes longer — there is nothing to choose.

    This was shown as a second card on the grounds that the stop count
    differed. A traveller offered USD 500 non-stop in 4h40 has no reason to
    read USD 500 one-stop in 4h50; the card only made the tab look fuller.
    """
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
    strategies = _extract(data=data)["strategies"]
    assert len(strategies) == 1
    assert strategies[0]["price_per_traveler"] == 500
    assert strategies[0]["stops"] == 0


def test_a_connection_earns_a_card_when_it_buys_something():
    """The same connection is a real offer once it is cheaper than flying direct."""
    data = {
        "best_flights": [
            _option(500, [_leg("CMB", "DXB", "A", "A 1", minutes=280)], 280),
            _option(
                430,
                [_leg("CMB", "KUL", "B", "B 1"), _leg("KUL", "DXB", "B", "B 2")],
                330,
                layovers=1,
            ),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert [s["price_per_traveler"] for s in strategies] == [430, 500]
    assert [s["stops"] for s in strategies] == [1, 0]


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


# ── The price ladder ────────────────────────────────────────────────────────
#
# Tiers used to be claimed one at a time, each by its own criterion, and
# "comfortable" claimed before "recommended". Comfortable took the best fare on
# the route and Recommended picked from what was left. Selection now runs over
# the price/time frontier instead, so a card can only appear above another by
# costing more AND arriving sooner — and the tier name is just the price rank.


def _ladder(result):
    return [
        (s["price_per_traveler"], s["total_duration_minutes"])
        for s in result["strategies"]
    ]


def test_every_card_costs_more_and_arrives_sooner_than_the_one_above():
    rungs = _ladder(_extract())
    assert len(rungs) == 3
    for (cheap, slow), (dear, quick) in zip(rungs, rungs[1:]):
        assert dear > cheap, "a card costs no more than the one above it"
        assert quick < slow, "a card costs more without arriving sooner"


def test_the_middle_card_is_never_the_dearest_fare():
    """The Colombo->Edinburgh regression, in miniature.

    Live on 2026-09-14 the tab showed 132,462 / 45h35 / 3 stops,
    183,456 / 30h55 / 3 stops and 139,016 / 33h05 / 2 stops — and put "Best
    Value Route" on the middle one. It was the dearest fare on the card and
    tied for the most stops. The Budget tab prices itself off the Recommended
    fare, so it inherited the 44,440 difference as well.
    """
    data = {
        "best_flights": [
            _option(
                132462,
                [_leg("CMB", "AUH", "Etihad", "EY 1"), _leg("AUH", "OSL", "SAS", "SK 2"),
                 _leg("OSL", "EDI", "SAS", "SK 3")],
                2735, layovers=3,
            ),
            _option(
                183456,
                [_leg("CMB", "DOH", "Qatar Airways", "QR 1"), _leg("DOH", "LHR", "Qatar Airways", "QR 2"),
                 _leg("LHR", "EDI", "Qatar Airways", "QR 3")],
                1855, layovers=3,
            ),
        ],
        "other_flights": [
            _option(
                139016,
                [_leg("CMB", "DOH", "Qatar Airways", "QR 4"), _leg("DOH", "EDI", "Qatar Airways", "QR 5")],
                1985, layovers=2,
            ),
        ],
    }
    tiers = _by_tier(_extract(data=data))
    assert tiers["recommended"]["price_per_traveler"] == 139016
    assert tiers["recommended"]["price_per_traveler"] < tiers["comfortable"]["price_per_traveler"]
    assert _ladder(_extract(data=data)) == [(132462, 2735), (139016, 1985), (183456, 1855)]


def test_a_fare_above_the_ceiling_is_never_shown():
    """Odyssey plans to a budget: a fare that breaks it is not a tier.

    Seen live on a Switzerland Odyssey, where the Fastest card came back at
    1,303,482 against a 389,995 Best Value — 3.3x the fare, same stop count.
    """
    data = {
        "best_flights": [
            _option(100, [_leg("CMB", "AUH", "A", "A 1"), _leg("AUH", "ZRH", "A", "A 2")], 1800, layovers=2),
            _option(130, [_leg("CMB", "DOH", "B", "B 1")], 1500, layovers=1),
        ],
        "other_flights": [
            _option(500, [_leg("CMB", "AUH", "C", "C 1"), _leg("AUH", "ZRH", "C", "C 2")],
                    1400, layovers=2),
        ],
    }
    fares = [s["price_per_traveler"] for s in _extract(data=data)["strategies"]]
    assert fares == [100, 130]
    # Dropped knowingly: it was the quickest itinerary on the route, but 5x the
    # cheapest fare buys 100 minutes. Two stops, like the fare it is measured
    # against — a *non-stop* at this price is kept, and has its own test below.
    assert 500 not in fares


def test_a_direct_flight_is_shown_however_dear_it_is():
    """"Is there a direct flight?" is the traveller's question, not ours.

    A live Colombo->Gatwick search carried exactly one non-stop, at 71,538
    against a 35,237 cheapest connection — 2.03x, and the fare ceiling dropped
    it for being 3% over. The price is the traveller's to weigh; withholding
    the only direct flight on the route is not a budget decision.
    """
    data = {
        "best_flights": [
            _option(100, [_leg("CMB", "AUH", "A", "A 1"), _leg("AUH", "LGW", "A", "A 2")], 1800, layovers=2),
            _option(130, [_leg("CMB", "DOH", "B", "B 1"), _leg("DOH", "LGW", "B", "B 2")], 1500, layovers=2),
        ],
        "other_flights": [
            _option(500, [_leg("CMB", "LGW", "C", "C 1", minutes=700)], 700, layovers=0),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert 500 in [s["price_per_traveler"] for s in strategies]
    direct = [s for s in strategies if s["stops"] == 0]
    assert len(direct) == 1
    # Price order still holds, so the direct fare lands on the dearest card and
    # the budget, which reads the middle one, does not move.
    assert direct[0]["tier"] == "comfortable"
    assert [s["price_per_traveler"] for s in strategies] == [100, 130, 500]


def test_only_the_best_direct_fare_escapes_the_ceiling():
    """One exemption, not an open door for every non-stop on the route.

    Cached Cairo->Aswan results list the same non-stop from 5,360 up to 19,396.
    If the exemption were per-option rather than per-route, a business-class
    seat on the same aircraft could reach the middle card — the one the budget
    prices itself from.
    """
    data = {
        "best_flights": [
            _option(100, [_leg("CMB", "AUH", "A", "A 1"), _leg("AUH", "LGW", "A", "A 2")], 1800, layovers=2),
        ],
        "other_flights": [
            _option(500, [_leg("CMB", "LGW", "C", "C 1", minutes=700)], 700, layovers=0),
            _option(900, [_leg("CMB", "LGW", "D", "D 1", minutes=690)], 690, layovers=0),
        ],
    }
    fares = [s["price_per_traveler"] for s in _extract(data=data)["strategies"]]
    assert fares == [100, 500]
    assert 900 not in fares


def test_a_route_with_no_direct_flight_is_unaffected():
    """28 of 30 live routes in cache have no non-stop at all — they must not move."""
    data = {
        "best_flights": [
            _option(100, [_leg("CMB", "AUH", "A", "A 1"), _leg("AUH", "ZRH", "A", "A 2")], 1800, layovers=2),
            _option(130, [_leg("CMB", "DOH", "B", "B 1"), _leg("DOH", "ZRH", "B", "B 2")], 1500, layovers=2),
        ],
        "other_flights": [
            _option(500, [_leg("CMB", "DXB", "C", "C 1"), _leg("DXB", "ZRH", "C", "C 2")], 1400, layovers=2),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert [s["price_per_traveler"] for s in strategies] == [100, 130]
    assert all(s["stops"] > 0 for s in strategies)


def test_a_cheap_direct_flight_needs_no_exemption():
    """Cairo->Aswan: the non-stop is also the cheapest fare, so it is Minimum."""
    data = {
        "best_flights": [
            _option(5360, [_leg("CAI", "ASW", "Air Cairo", "SM 1", minutes=80)], 80, layovers=0),
            _option(9000, [_leg("CAI", "LXR", "X", "X 1"), _leg("LXR", "ASW", "X", "X 2")], 300, layovers=2),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert strategies[0]["tier"] == "minimum"
    assert strategies[0]["stops"] == 0
    assert strategies[0]["price_per_traveler"] == 5360


def test_the_direct_card_names_itself_in_its_header():
    """No badge needed: the header already states the connections."""
    data = {
        "best_flights": [
            _option(100, [_leg("CMB", "AUH", "A", "A 1"), _leg("AUH", "LGW", "A", "A 2")], 1800, layovers=2),
        ],
        "other_flights": [
            _option(500, [_leg("CMB", "LGW", "C", "C 1", minutes=705)], 705, layovers=0),
        ],
    }
    titles = [s["title"] for s in _extract(data=data)["strategies"]]
    assert "Non-stop · 11h 45m" in titles


def test_the_fast_card_is_the_cheapest_of_the_near_identical_ones():
    """Ten minutes off a 34-hour trip is not worth 33,999.

    Taken from a live Colombo->Italy open jaw: 148,904 arriving 34h20 sat
    beside 114,905 arriving 34h30, and the dearer one was being shown.
    """
    data = {
        "best_flights": [
            _option(109782, [_leg("CMB", "AUH", "Etihad", "EY 1"), _leg("AUH", "FCO", "ITA", "AZ 2"),
                             _leg("FCO", "NAP", "ITA", "AZ 3")], 3810, layovers=3),
            _option(110743, [_leg("CMB", "AUH", "Etihad", "EY 4"), _leg("AUH", "FCO", "ITA", "AZ 5"),
                             _leg("FCO", "NAP", "ITA", "AZ 6")], 3110, layovers=3),
        ],
        "other_flights": [
            _option(114905, [_leg("CMB", "DOH", "Qatar Airways", "QR 7"), _leg("DOH", "FCO", "ITA", "AZ 8"),
                             _leg("FCO", "NAP", "ITA", "AZ 9"), _leg("NAP", "BRI", "ITA", "AZ 10")],
                    2070, layovers=4),
            _option(148904, [_leg("CMB", "DOH", "Qatar Airways", "QR 11"), _leg("DOH", "FCO", "ITA", "AZ 12"),
                             _leg("FCO", "NAP", "ITA", "AZ 13"), _leg("NAP", "BRI", "ITA", "AZ 14")],
                    2060, layovers=4),
        ],
    }
    fares = [s["price_per_traveler"] for s in _extract(data=data)["strategies"]]
    assert fares == [109782, 110743, 114905]
    assert 148904 not in fares


def test_stop_count_never_outranks_time_in_transit():
    """Fewer stops is not "more comfortable" when it costs 18 extra hours.

    From a live Egypt Odyssey: a 2-stop 43h50 fare at 117,826 was ranked above
    a 3-stop 25h10 at 90,651 because it stopped once less.
    """
    data = {
        "best_flights": [
            _option(86083, [_leg("CMB", "SHJ", "Air Arabia", "G9 1"), _leg("SHJ", "CAI", "Air Arabia", "G9 2"),
                            _leg("CAI", "LXR", "Air Arabia", "G9 3")], 1670, layovers=3),
            _option(90651, [_leg("CMB", "DOH", "Qatar Airways", "QR 1"), _leg("DOH", "CAI", "Qatar Airways", "QR 2"),
                            _leg("CAI", "LXR", "Qatar Airways", "QR 3")], 1540, layovers=3),
        ],
        "other_flights": [
            _option(117826, [_leg("CMB", "DXB", "Emirates", "EK 1"), _leg("DXB", "CAI", "Emirates", "EK 2")],
                    2630, layovers=2),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert [s["price_per_traveler"] for s in strategies] == [86083, 90651]
    assert all(s["stops"] == 3 for s in strategies)


def test_an_exact_tie_is_broken_by_the_connection():
    """Same fare, same total time — the non-stop is the only real offer."""
    data = {
        "best_flights": [
            _option(500, [_leg("CMB", "KUL", "B", "B 1"), _leg("KUL", "DXB", "B", "B 2")],
                    280, layovers=1),
            _option(500, [_leg("CMB", "DXB", "A", "A 1", minutes=280)], 280, layovers=0),
        ],
    }
    strategies = _extract(data=data)["strategies"]
    assert len(strategies) == 1
    assert strategies[0]["stops"] == 0


# ── Card copy: facts about this itinerary, never a verdict on the others ────


def test_the_header_states_the_connections_and_the_time():
    tiers = _by_tier(_extract())
    assert tiers["minimum"]["title"] == "2 stops · 28h 0m"
    assert tiers["recommended"]["title"] == "1 stop · 17h 20m"
    assert tiers["comfortable"]["title"] == "Non-stop · 11h 0m"


def test_no_two_cards_share_a_header():
    """Headers are built from the two fields the fares are ranked on, so two
    cards on one route cannot read the same. Carrier was tried first and read
    identically on two cards of one open jaw."""
    titles = [s["title"] for s in _extract()["strategies"]]
    assert len(set(titles)) == len(titles)


def test_no_card_claims_to_be_better_than_another():
    """A verdict can be wrong; a fact about one itinerary cannot.

    "Best Value Route" was printed over the dearest, most-stopped fare on a
    live Colombo->Edinburgh search, and "Fastest route" over an itinerary with
    one more connection than the card beneath it.
    """
    verdicts = ("best", "value", "cheapest", "fastest", "fewest", "recommend",
                "save", "lowest", "premium", "worth", "balance")
    for s in _extract()["strategies"]:
        copy = f"{s['title']} {s['estimated_savings']} {s['tip']}".lower()
        for word in verdicts:
            assert word not in copy, f"card copy still judges: {word!r} in {copy!r}"


def test_the_badge_and_tip_are_blank_so_older_builds_drop_them():
    """Both are rendered only when non-empty, so emptying them is safe in the
    field — unlike blanking `title`, which every build draws unconditionally."""
    for s in _extract()["strategies"]:
        assert s["estimated_savings"] == ""
        assert s["tip"] == ""
        assert s["title"], "an empty title would leave a blank card header"



# ── Which fare the budget note describes ────────────────────────────────────

def _fs(*strategies):
    return {"strategies": list(strategies)}


def _fare(tier, price, stops, live=True):
    s = {"tier": tier, "price_per_traveler": float(price), "stops": stops}
    if live:
        s["is_live_price"] = True
    return s


def test_an_estimated_fare_is_never_reported_as_direct():
    """`_structure_ai_flight_strategies` defaults a missing `stops` to 0.

    A model that simply said nothing about connections would otherwise have the
    budget note announce "Based on Best Value Direct Flight" for a route nobody
    checked. Only a live Google fare can answer this question.
    """
    from app.services.odyssey_ai_service import budget_flight_basis

    assert budget_flight_basis(_fs(_fare("recommended", 500, 0))) == "direct"
    assert budget_flight_basis(
        _fs(_fare("recommended", 500, 0, live=False)),
    ) == "estimated"


def test_the_basis_describes_the_fare_the_budget_actually_used():
    """The budget reads the Recommended card, so the note must describe it."""
    from app.services.odyssey_ai_service import budget_flight_basis

    # Direct flight on the dearest card, which the budget does not price from.
    assert budget_flight_basis(_fs(
        _fare("minimum", 35237, 1),
        _fare("recommended", 38417, 1),
        _fare("comfortable", 71538, 0),
    )) == "connecting"

    # Cairo->Aswan: the non-stop is also the cheapest, so it is the budget's.
    assert budget_flight_basis(_fs(
        _fare("minimum", 5360, 0),
        _fare("recommended", 9000, 2),
    ), tier="minimum") == "direct"


def test_a_thin_route_falls_back_to_the_fare_the_budget_fell_back_to():
    """Two cards means no `recommended`; `_tier_flight_cost` takes the cheapest."""
    from app.services.odyssey_ai_service import budget_flight_basis

    assert budget_flight_basis(_fs(
        _fare("minimum", 5360, 0),
        _fare("comfortable", 15339, 0),
    )) == "direct"
    assert budget_flight_basis(_fs(
        _fare("minimum", 35237, 2),
        _fare("comfortable", 71538, 0),
    )) == "connecting"


def test_no_fare_at_all_describes_no_flight():
    """Seen on a stored Colombo plan: no flight cards, yet the note named one."""
    from app.services.odyssey_ai_service import budget_flight_basis, _budget_notes

    assert budget_flight_basis(None) == "none"
    assert budget_flight_basis({}) == "none"
    assert budget_flight_basis(_fs()) == "none"
    assert budget_flight_basis(_fs(_fare("recommended", 0, 0))) == "none"

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="none", no_airfare=False,
    )
    assert "transit" not in n
    assert "flight" not in n["summary"]
    assert n["summary"] == "Cheapest 3-star+ room, 1 per person"
