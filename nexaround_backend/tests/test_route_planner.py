"""The route planner and the flights searched for the route it draws.

Client report: an India trip came back as a wildlife-safari route whose first
park was ~1,000 km from Delhi, while the flight landed at DEL, nothing said
how to get from one to the other, and no return flight was shown. The flight
search used to run before the cities were chosen, so it could only ever aim
for the destination string; the gateways are an output of the route now, the
return leg is searched from where the trip actually ends, and the itinerary
prompt is told to open with the transfer in and close with the transfer out.
Nothing here touches the network.
"""
import asyncio
import re
from types import SimpleNamespace
import json

import pytest

from app.services import odyssey_ai_service as svc
from app.services import serpapi_service
from app.services.geo_resolver import DestinationContext
from app.services.odyssey_ai_service import (
    RoutePlan,
    _build_prompt,
    _validate_route,
    plan_city_legs,
    plan_route,
)
from app.services.serpapi_service import (
    attach_return_leg,
    extract_flight_strategies_from_serpapi,
    extract_open_jaw_strategies_from_serpapi,
)


def _india():
    return DestinationContext(
        query="India", name="India", country="India", country_code="IN",
        latitude=20.5937, longitude=78.9629, types=("country",), source="places",
    )


def _paris():
    return DestinationContext(
        query="Paris", name="Paris", country="France", country_code="FR",
        latitude=48.8566, longitude=2.3522, source="places",
    )


# A coherent central-India wildlife route: land at Nagpur, three parks within
# a few hundred km of each other, fly home from Jabalpur.
COHERENT = {
    "region": "Central India wildlife circuit",
    "legs": [
        {"city": "Nagpur", "country": "IN", "start_day": 1, "end_day": 1,
         "latitude": 21.15, "longitude": 79.09, "arrive_by": "none", "from_previous_km": 0},
        {"city": "Pench", "country": "IN", "start_day": 2, "end_day": 4,
         "latitude": 21.75, "longitude": 79.30, "arrive_by": "car", "from_previous_km": 90},
        {"city": "Kanha", "country": "IN", "start_day": 5, "end_day": 7,
         "latitude": 22.33, "longitude": 80.63, "arrive_by": "car", "from_previous_km": 200},
        {"city": "Jabalpur", "country": "IN", "start_day": 8, "end_day": 9,
         "latitude": 23.18, "longitude": 79.99, "arrive_by": "car", "from_previous_km": 165},
    ],
    "arrival_airport": {"iata": "NAG", "city": "Nagpur", "name": "Dr. Babasaheb Ambedkar International"},
    "departure_airport": {"iata": "JLR", "city": "Jabalpur", "name": "Jabalpur Airport"},
}

# The reported shape: landing at Delhi for a route that starts 1,000 km away.
DISTANT_GATEWAY = {
    "region": "Central India",
    "legs": [
        {"city": "Bandhavgarh", "country": "IN", "start_day": 1, "end_day": 4,
         "latitude": 23.70, "longitude": 81.03, "arrive_by": "car", "from_previous_km": 900},
        {"city": "Kanha", "country": "IN", "start_day": 5, "end_day": 9,
         "latitude": 22.33, "longitude": 80.63, "arrive_by": "car", "from_previous_km": 250},
    ],
    "arrival_airport": {"iata": "DEL", "city": "Delhi", "name": "Indira Gandhi International"},
    "departure_airport": {"iata": "DEL", "city": "Delhi", "name": "Indira Gandhi International"},
}

AIRPORTS = {
    "NAG": {"latitude": 21.09, "longitude": 79.05, "country_code": "IN", "name": "Nagpur Airport"},
    "JLR": {"latitude": 23.18, "longitude": 80.05, "country_code": "IN", "name": "Jabalpur Airport"},
    "DEL": {"latitude": 28.56, "longitude": 77.10, "country_code": "IN", "name": "Indira Gandhi International"},
    "CDG": {"latitude": 49.01, "longitude": 2.55, "country_code": "FR", "name": "Charles de Gaulle"},
    "CMB": {"latitude": 7.18, "longitude": 79.88, "country_code": "LK", "name": "Bandaranaike International"},
}


@pytest.fixture
def located(monkeypatch):
    """Airport coordinates without Places: the static table above."""
    async def _geo(code, geo, budget=None, city=""):
        return AIRPORTS.get(code)
    monkeypatch.setattr(svc, "_airport_geo", _geo)


def _script(monkeypatch, *responses):
    """Feed successive planner responses to `_call_gemini`, recording prompts."""
    calls = []

    async def _fake(prompt, api_key, **kw):
        calls.append({"prompt": prompt, **kw})
        payload = responses[min(len(calls) - 1, len(responses) - 1)]
        return json.dumps(payload), []

    monkeypatch.setattr(svc, "_call_gemini", _fake)
    return calls


def _plan(**kw):
    args = dict(
        destination="India", days=9, mood="Adventurous", travelers=2, api_key="k",
        start_date="2026-11-01", geo=_india(), departure_city="Colombo",
        departure_country="Sri Lanka", include_flights=True,
    )
    args.update(kw)
    return asyncio.run(plan_route(**args))


# ── _validate_route ─────────────────────────────────────────────────────────

def test_a_coherent_route_has_no_reasons():
    plan, reasons = _validate_route(COHERENT, "India", 9, "2026-11-01", _india())
    assert reasons == []
    assert [l["city"] for l in plan.legs] == ["Nagpur", "Pench", "Kanha", "Jabalpur"]
    assert plan.arrival["iata"] == "NAG" and plan.departure["iata"] == "JLR"
    assert plan.source == "planner"


def test_legs_carry_the_planners_geography():
    plan, _ = _validate_route(COHERENT, "India", 9, "2026-11-01", _india())
    pench = plan.legs[1]
    assert pench["latitude"] == 21.75 and pench["longitude"] == 79.3
    assert pench["arrive_by"] == "car" and pench["from_previous_km"] == 90
    # Nights are still derived, never trusted.
    assert sum(l["nights"] for l in plan.legs) == 8


def test_a_long_hop_by_car_is_a_reason():
    far = json.loads(json.dumps(COHERENT))
    # Jaipur is ~700 km from both its neighbours: two hops too long for a car.
    far["legs"][1].update({"city": "Jaipur", "latitude": 26.91, "longitude": 75.79})
    _, reasons = _validate_route(far, "India", 9, "2026-11-01", _india())
    assert len(reasons) == 2
    assert "Jaipur" in reasons[0] and "flight or train" in reasons[0]
    assert "Kanha" in reasons[1]


def test_a_long_hop_by_flight_is_fine():
    far = json.loads(json.dumps(COHERENT))
    far["legs"][1].update({"city": "Jaipur", "latitude": 26.91, "longitude": 75.79, "arrive_by": "flight"})
    far["legs"][2]["arrive_by"] = "train"
    _, reasons = _validate_route(far, "India", 9, "2026-11-01", _india())
    assert reasons == []


def test_missing_coordinates_are_tolerated():
    bare = json.loads(json.dumps(COHERENT))
    for leg in bare["legs"]:
        leg.pop("latitude"); leg.pop("longitude")
    plan, reasons = _validate_route(bare, "India", 9, "2026-11-01", _india())
    assert reasons == [] and len(plan.legs) == 4
    assert "latitude" not in plan.legs[0]


def test_a_metro_code_is_rejected_with_a_reason():
    bad = json.loads(json.dumps(COHERENT))
    bad["arrival_airport"] = {"iata": "LON", "city": "London"}
    plan, reasons = _validate_route(bad, "India", 9, "2026-11-01", _india())
    assert plan.arrival is None
    assert any("LON" in r for r in reasons)


def test_structurally_broken_legs_still_fall_back_to_one_leg():
    broken = json.loads(json.dumps(COHERENT))
    broken["legs"][1]["start_day"] = 9
    plan, _ = _validate_route(broken, "India", 9, "2026-11-01", _india())
    assert len(plan.legs) == 1 and plan.legs[0]["city"] == "India"


def test_route_plan_trip_type_follows_the_gateways():
    same = RoutePlan(legs=[], arrival_code="DEL", departure_code="DEL")
    multi = RoutePlan(legs=[], arrival_code="LHR,LGW", departure_code="LGW,LHR")
    jaw = RoutePlan(legs=[], arrival_code="NAG", departure_code="JLR")
    assert same.trip_type == "round_trip" and multi.trip_type == "round_trip"
    assert jaw.trip_type == "open_jaw"
    assert RoutePlan(legs=[]).trip_type == ""


# ── plan_route ──────────────────────────────────────────────────────────────

def test_the_gateways_come_from_the_route(located, monkeypatch):
    calls = _script(monkeypatch, COHERENT)
    plan = _plan()
    assert len(calls) == 1
    assert calls[0]["response_schema"] is svc._ROUTE_SCHEMA
    assert calls[0]["operation"] == "odyssey_route"
    assert plan.arrival_code == "NAG" and plan.departure_code == "JLR"
    assert plan.trip_type == "open_jaw"
    assert plan.arrival["latitude"] == 21.09          # located, for the distance checks
    assert plan.reasons == []


def test_the_planner_is_told_where_the_traveller_starts(located, monkeypatch):
    calls = _script(monkeypatch, COHERENT)
    _plan(departure_city="Nearby", departure_country="", departure_latitude=8.58, departure_longitude=81.23)
    prompt = calls[0]["prompt"]
    assert "Nearby" not in prompt
    assert "8.5800, 81.2300" in prompt
    assert "whole country" in prompt                   # country-level clustering rule


def test_a_distant_gateway_triggers_one_replan_and_keeps_the_better_route(located, monkeypatch):
    calls = _script(monkeypatch, DISTANT_GATEWAY, COHERENT)
    plan = _plan()
    assert len(calls) == 2
    assert "DEL" in calls[1]["prompt"] and "Bandhavgarh" in calls[1]["prompt"]
    assert "NOT WORKABLE" in calls[1]["prompt"]
    assert plan.arrival_code == "NAG" and plan.reasons == []


def test_a_replan_that_is_no_better_is_discarded(located, monkeypatch):
    calls = _script(monkeypatch, DISTANT_GATEWAY, DISTANT_GATEWAY)
    plan = _plan()
    assert len(calls) == 2
    # Kept, with its problems recorded — never collapsed to a single leg.
    assert [l["city"] for l in plan.legs] == ["Bandhavgarh", "Kanha"]
    assert plan.arrival_code == "DEL" and plan.reasons


def test_a_distant_gateway_reached_by_a_flagged_flight_is_accepted(located, monkeypatch):
    via_flight = json.loads(json.dumps(DISTANT_GATEWAY))
    via_flight["legs"][0]["arrive_by"] = "flight"                 # DEL → domestic hop
    via_flight["departure_airport"] = {"iata": "JLR", "city": "Jabalpur"}   # home from nearby
    calls = _script(monkeypatch, via_flight)
    plan = _plan()
    assert len(calls) == 1
    assert plan.arrival_code == "DEL" and plan.departure_code == "JLR"
    assert plan.reasons == []


def test_an_airport_in_the_wrong_country_is_replaced(located, monkeypatch):
    wrong = json.loads(json.dumps(COHERENT))
    wrong["arrival_airport"] = {"iata": "CMB", "city": "Colombo"}
    _script(monkeypatch, wrong, wrong)

    async def _resolve(place, country, api_key, **kw):
        return "NAG" if place == "Nagpur" else ""
    monkeypatch.setattr(svc, "_resolve_airport_code", _resolve)

    plan = _plan()
    assert plan.arrival_code == "NAG"
    assert any("CMB" in r for r in plan.reasons)


def test_a_multi_airport_gateway_city_is_widened_for_the_search(located, monkeypatch):
    london = {
        "region": "England",
        "legs": [
            {"city": "London", "country": "GB", "start_day": 1, "end_day": 3,
             "latitude": 51.51, "longitude": -0.13, "arrive_by": "none", "from_previous_km": 0},
            {"city": "Bath", "country": "GB", "start_day": 4, "end_day": 5,
             "latitude": 51.38, "longitude": -2.36, "arrive_by": "train", "from_previous_km": 185},
        ],
        "arrival_airport": {"iata": "LHR", "city": "London"},
        "departure_airport": {"iata": "LHR", "city": "London"},
    }
    _script(monkeypatch, london)
    uk = DestinationContext(query="England", name="England", country="United Kingdom",
                            country_code="GB", latitude=52.3, longitude=-1.2, source="places")
    plan = _plan(destination="England", days=5, geo=uk)
    assert plan.arrival_code == svc._AIRPORT_CODES["london"]
    assert plan.trip_type == "round_trip"


def test_no_flights_means_no_places_spend_but_the_route_still_runs(monkeypatch):
    _script(monkeypatch, COHERENT)
    looked_up = []

    async def _geo(code, geo, budget=None):
        looked_up.append(code)
        return AIRPORTS.get(code)
    monkeypatch.setattr(svc, "_airport_geo", _geo)

    plan = _plan(include_flights=False)
    assert looked_up == []
    assert len(plan.legs) == 4 and plan.arrival_code == ""


def test_a_planner_failure_degrades_to_a_single_leg(monkeypatch):
    async def _boom(prompt, api_key, **kw):
        raise RuntimeError("503")
    monkeypatch.setattr(svc, "_call_gemini", _boom)
    plan = _plan()
    assert len(plan.legs) == 1 and plan.legs[0]["city"] == "India"
    assert plan.source == "fallback" and plan.arrival_code == ""


def test_short_trips_skip_the_planner(monkeypatch):
    calls = _script(monkeypatch, COHERENT)
    plan = _plan(days=1)
    assert calls == [] and len(plan.legs) == 1


def test_plan_city_legs_still_returns_the_legs(located, monkeypatch):
    _script(monkeypatch, COHERENT)
    legs = asyncio.run(plan_city_legs(
        destination="India", days=9, mood="Adventurous", travelers=2, api_key="k",
        start_date="2026-11-01", geo=_india(),
    ))
    assert [l["city"] for l in legs] == ["Nagpur", "Pench", "Kanha", "Jabalpur"]


# ── Open-jaw flights ────────────────────────────────────────────────────────

def _leg(dep, arr, airline, number, minutes=300, day="2026-11-01"):
    return {
        "departure_airport": {"id": dep, "name": f"{dep} Airport", "time": f"{day} 01:30"},
        "arrival_airport": {"id": arr, "name": f"{arr} Airport", "time": f"{day} 06:00"},
        "duration": minutes, "airline": airline, "flight_number": number, "travel_class": "Economy",
    }


def _option(price, legs, total_duration, layovers=0, token=""):
    o = {
        "flights": legs,
        "layovers": [{"duration": 120, "id": "XXX"} for _ in range(layovers)],
        "total_duration": total_duration,
        "price": price,
        "type": "Round trip",
    }
    if token:
        o["departure_token"] = token
    return o


OUTBOUND = {
    "best_flights": [
        _option(180, [_leg("CMB", "NAG", "IndiGo", "6E 1201", 200)], 200),
    ],
    "other_flights": [
        _option(140, [_leg("CMB", "MAA", "IndiGo", "6E 202", 90), _leg("MAA", "NAG", "IndiGo", "6E 471", 100)], 400, layovers=1),
        _option(260, [_leg("CMB", "NAG", "SriLankan", "UL 141", 190)], 190),
    ],
}

RETURN = {
    "best_flights": [
        _option(150, [_leg("JLR", "CMB", "Air India", "AI 660", 240, day="2026-11-09")], 240),
    ],
    "other_flights": [
        _option(110, [_leg("JLR", "DEL", "IndiGo", "6E 555", 120, day="2026-11-09"), _leg("DEL", "CMB", "IndiGo", "6E 900", 220, day="2026-11-09")], 480, layovers=1),
    ],
}

ROUND_TRIP = {
    "best_flights": [
        _option(320, [_leg("CMB", "DEL", "IndiGo", "6E 1201", 230)], 230, token="tok-min"),
        _option(410, [_leg("CMB", "DEL", "SriLankan", "UL 195", 220)], 220, token="tok-rec"),
    ],
    "other_flights": [
        _option(520, [_leg("CMB", "DEL", "Air India", "AI 282", 210)], 210, token="tok-com"),
    ],
}

ROUND_TRIP_RETURN = {
    "best_flights": [
        _option(415, [_leg("DEL", "CMB", "SriLankan", "UL 196", 225, day="2026-11-09")], 225),
        _option(440, [_leg("DEL", "CMB", "Air India", "AI 281", 215, day="2026-11-09")], 215),
    ],
}


def _open_jaw(travelers=1, currency="USD"):
    return extract_open_jaw_strategies_from_serpapi(
        OUTBOUND, RETURN, departure_city="Colombo", destination="India", currency=currency,
        outbound_date="2026-11-01", return_date="2026-11-09", travelers=travelers,
        arrival_city="Nagpur", departure_gateway_city="Jabalpur",
    )


def test_open_jaw_prices_are_both_legs_together():
    result = _open_jaw()
    minimum = next(s for s in result["strategies"] if s["tier"] == "minimum")
    assert minimum["price_per_traveler"] == 140 + 110
    assert minimum["outbound"]["price_per_traveler"] == 140
    assert minimum["return"]["price_per_traveler"] == 110
    assert minimum["trip_type"] == "open_jaw"


def test_open_jaw_carries_both_routes_and_durations():
    result = _open_jaw()
    s = next(s for s in result["strategies"] if s["tier"] == "minimum")
    assert s["route"] == "CMB → NAG" and s["return_route"] == "JLR → CMB"
    assert s["outbound_duration_minutes"] == 400 and s["return_duration_minutes"] == 480
    assert s["total_duration_minutes"] == 880
    assert s["return"]["flight_numbers"] == ["6E 555", "6E 900"]


def test_open_jaw_tiers_are_distinct_pairs():
    result = _open_jaw()
    pairs = {(s["outbound"]["flight_numbers"][0], s["return"]["flight_numbers"][0]) for s in result["strategies"]}
    assert len(pairs) == len(result["strategies"]) >= 2
    comfortable = next(s for s in result["strategies"] if s["tier"] == "comfortable")
    assert comfortable["outbound"]["stops"] == 0 and comfortable["return"]["stops"] == 0


def test_open_jaw_cards_do_not_share_a_header():
    """Both cards of an open jaw can fly out together and differ only on the
    way home, so a header naming the outbound carrier read the same on two."""
    titles = [s["title"] for s in _open_jaw()["strategies"]]
    assert len(set(titles)) == len(titles)
    assert not any(
        w in t.lower() for t in titles
        for w in ("best", "value", "cheapest", "fastest", "fewest")
    )


def test_open_jaw_more_options_are_tagged_by_leg():
    result = _open_jaw()
    legs = {o["leg"] for o in result["more_options"]}
    assert legs <= {"outbound", "return"}
    assert all(o["route"] in ("CMB → NAG", "JLR → CMB") for o in result["more_options"])


def test_open_jaw_group_total_is_derived():
    result = _open_jaw(travelers=3)
    s = result["strategies"][0]
    assert s["price_total"] == round(s["price_per_traveler"] * 3, 2)


def test_open_jaw_with_one_empty_direction_returns_nothing():
    assert extract_open_jaw_strategies_from_serpapi(
        OUTBOUND, {}, departure_city="Colombo", destination="India", currency="USD",
    ) == {}


# ── Round trip: the return leg via departure_token ──────────────────────────

def _round_trip():
    return extract_flight_strategies_from_serpapi(
        ROUND_TRIP, departure_city="Colombo", destination="Delhi", currency="USD",
        outbound_date="2026-11-01", return_date="2026-11-09", travelers=2,
    )


def test_round_trip_tokens_are_returned_out_of_band():
    result = _round_trip()
    assert result["_departure_tokens"]["minimum"] == "tok-min"
    assert all("departure_token" not in s for s in result["strategies"])
    assert all(s["return"] is None for s in result["strategies"])
    assert all(o["leg"] == "outbound" for o in result["more_options"])


def test_attaching_the_return_leg_uses_the_combined_fare():
    result = _round_trip()
    rec = next(s for s in result["strategies"] if s["tier"] == "recommended")
    assert attach_return_leg(rec, ROUND_TRIP_RETURN, currency="USD", return_date="2026-11-09")
    assert rec["return"]["origin"] == "DEL" and rec["return"]["destination"] == "CMB"
    assert rec["return_route"] == "DEL → CMB"
    assert rec["return"]["flight_numbers"] == ["UL 196"]
    assert rec["return"]["price_per_traveler"] is None      # priced as the whole trip
    assert rec["price_per_traveler"] == 415 and rec["price_total"] == 830
    assert rec["return_duration_minutes"] == 225
    assert rec["total_duration_minutes"] == rec["outbound_duration_minutes"] + 225


def test_attaching_nothing_leaves_the_strategy_alone():
    result = _round_trip()
    s = result["strategies"][0]
    before = dict(s)
    assert not attach_return_leg(s, {}, currency="USD")
    assert s == before


# ── generate_flight_strategies with a route ─────────────────────────────────

class _RecordingSerp:
    """Stands in for SerpApiService; answers from the fixtures above."""
    searches = []

    def __init__(self, key, **kw):
        pass

    async def search_flights(self, **kw):
        _RecordingSerp.searches.append(kw)
        if kw.get("one_way"):
            return OUTBOUND if kw["departure_city"] == "CMB" else RETURN
        return ROUND_TRIP

    async def search_flights_return(self, **kw):
        _RecordingSerp.searches.append({"_return": True, **kw})
        return ROUND_TRIP_RETURN


@pytest.fixture
def serp(monkeypatch):
    _RecordingSerp.searches = []
    monkeypatch.setattr(svc, "SerpApiService", _RecordingSerp)
    # Nothing is stubbed past the search itself. A prose pass used to be
    # stubbed out here, and while it was stubbed it went on rewriting every
    # card title in production — the tests could not see it.
    return _RecordingSerp


def _flights(route, **kw):
    args = dict(
        departure_city="Colombo", departure_country="Sri Lanka", destination="India",
        days=9, budget=3000, currency="USD", travelers=2, flight_start_date="2026-11-01",
        flight_end_date="2026-11-09", api_key="", serpapi_key="k", destination_geo=_india(),
        route_plan=route,
    )
    args.update(kw)
    return asyncio.run(svc.generate_flight_strategies(**args))


def test_open_jaw_route_searches_two_one_ways(serp):
    route = RoutePlan(
        legs=COHERENT["legs"], arrival=COHERENT["arrival_airport"], departure=COHERENT["departure_airport"],
        arrival_code="NAG", departure_code="JLR", source="planner",
    )
    result = _flights(route)
    kinds = [(s["departure_city"], s["destination"], s["outbound_date"], s.get("one_way")) for s in serp.searches]
    assert kinds == [("CMB", "NAG", "2026-11-01", True), ("JLR", "CMB", "2026-11-09", True)]
    assert result["trip_type"] == "open_jaw"
    assert result["arrival_airport"]["iata"] == "NAG" and result["departure_airport"]["iata"] == "JLR"
    assert result["origin_airport"] == "CMB"
    assert "_departure_tokens" not in result
    s = result["strategies"][0]
    assert "one+way+flights+from+CMB+to+NAG" in s["booking_url"]
    assert "one+way+flights+from+JLR+to+CMB+on+2026-11-09" in s["return"]["booking_url"]
    assert s["outbound"]["booking_url"] == s["booking_url"]


def test_same_gateway_route_is_a_round_trip_with_one_return_lookup(serp):
    route = RoutePlan(
        legs=[{"city": "Delhi", "start_day": 1, "end_day": 9, "nights": 8}],
        arrival={"iata": "DEL", "city": "Delhi"}, departure={"iata": "DEL", "city": "Delhi"},
        arrival_code="DEL", departure_code="DEL", source="planner",
    )
    result = _flights(route)
    assert [s.get("_return", False) for s in serp.searches] == [False, True]
    assert serp.searches[0]["return_date"] == "2026-11-09" and not serp.searches[0].get("one_way")
    assert serp.searches[1]["departure_token"] == "tok-rec"
    assert result["trip_type"] == "round_trip"
    rec = next(s for s in result["strategies"] if s["tier"] == "recommended")
    assert rec["return"]["origin"] == "DEL" and rec["return"]["booking_url"] == ""
    others = [s for s in result["strategies"] if s["tier"] != "recommended"]
    assert all(s["return"] is None for s in others)


def test_card_copy_survives_the_whole_pipeline(serp):
    """The headers the extractor writes must reach the app unaltered.

    `_add_flight_prose` sat between the two and rewrote title, description and
    tip with model-written copy — "Budget-Friendly Colombo to Moscow" over a
    factual header, "the best chance at securing your fare" in the tip. Every
    test that touched this path stubbed it out, so nothing caught it. This
    asserts on the output of the real pipeline instead.
    """
    route = RoutePlan(
        legs=[{"city": "Delhi", "start_day": 1, "end_day": 9, "nights": 8}],
        arrival={"iata": "DEL", "city": "Delhi"}, departure={"iata": "DEL", "city": "Delhi"},
        arrival_code="DEL", departure_code="DEL", source="planner",
    )
    strategies = _flights(route)["strategies"]
    assert strategies
    for s in strategies:
        assert s["tip"] == "" and s["estimated_savings"] == ""
        assert re.match(r"^(Non-stop|\d+ stops?) · \d+h \d+m$", s["title"]), s["title"]
        copy = f"{s['title']} {s['description']} {s['tip']}".lower()
        for word in ("best", "value", "cheapest", "fastest", "fewest", "budget-friendly"):
            assert word not in copy, f"{word!r} reached the app in {copy!r}"


def test_without_a_route_the_destination_is_resolved_as_before(serp):
    result = _flights(None, destination="Delhi")
    assert serp.searches[0]["destination"] == "DEL"
    assert result["trip_type"] == "round_trip"
    assert result["arrival_airport"]["iata"] == "DEL" and result["departure_airport"]["iata"] == "DEL"


def test_a_gateway_shared_with_the_origin_means_no_flights(serp):
    route = RoutePlan(legs=[{"city": "Kandy", "start_day": 1, "end_day": 9, "nights": 8}],
                      arrival_code="CMB", departure_code="CMB")
    result = _flights(route)
    assert result["strategies"] == []
    assert result["unavailable_reason"] == "same_airport"
    assert "no flight to book" in result["unavailable_message"]
    assert serp.searches == [], "a shared gateway must not cost a search"


# ── The itinerary prompt ────────────────────────────────────────────────────

def _confirmed(trip_type="open_jaw"):
    return {
        "title": "Best Value Route", "route": "CMB → NAG", "return_route": "JLR → CMB",
        "currency": "USD", "price_per_traveler": 330, "trip_type": trip_type,
        "outbound_date": "2026-11-01", "return_date": "2026-11-09",
        "outbound": {"origin": "CMB", "destination": "NAG", "airlines": ["IndiGo"],
                     "departure_time": "2026-11-01 01:30", "arrival_time": "2026-11-01 06:00",
                     "duration": "3h 20m", "stops": 0},
        "return": {"origin": "JLR", "destination": "CMB", "airlines": ["Air India"],
                   "departure_time": "2026-11-09 18:30", "arrival_time": "2026-11-09 22:30",
                   "duration": "4h 0m", "stops": 0},
    }


def _route_for_prompt(first_city="Pench", first_km=None):
    legs = json.loads(json.dumps(COHERENT["legs"]))
    if first_city != "Nagpur":
        legs = legs[1:]
        legs[0]["start_day"] = 1
    arrival = dict(COHERENT["arrival_airport"], **AIRPORTS["NAG"])
    departure = dict(COHERENT["departure_airport"], **AIRPORTS["JLR"])
    return RoutePlan(legs=legs, arrival=arrival, departure=departure,
                     arrival_code="NAG", departure_code="JLR", source="planner")


def _prompt(route, flight):
    return _build_prompt(
        destination="India", mood="Adventurous", budget=3000, days=9, currency="USD",
        travelers=2, confirmed_flight=flight, departure_city="Colombo",
        departure_country="Sri Lanka", geo=_india(), route_plan=route,
    )


def test_prompt_states_both_confirmed_legs():
    prompt = _prompt(_route_for_prompt(), _confirmed())
    assert "CONFIRMED FLIGHTS" in prompt
    assert "OUTBOUND 2026-11-01: CMB → NAG, IndiGo" in prompt
    assert "RETURN 2026-11-09: JLR → CMB, Air India" in prompt
    assert "open-jaw — land at NAG, fly home from JLR" in prompt


def test_prompt_demands_the_arrival_transfer_when_the_first_night_is_elsewhere():
    prompt = _prompt(_route_for_prompt(first_city="Pench"), _confirmed())
    assert "ARRIVAL LOGISTICS" in prompt
    assert "Transfer: Nagpur airport → Pench" in prompt
    assert "at 2026-11-01 06:00" in prompt
    assert "DEPARTURE LOGISTICS" not in prompt        # last leg IS Jabalpur


def test_prompt_skips_the_arrival_transfer_when_the_first_night_is_the_gateway_city():
    prompt = _prompt(_route_for_prompt(first_city="Nagpur"), _confirmed())
    assert "ARRIVAL LOGISTICS" not in prompt


def test_prompt_demands_the_departure_transfer_when_the_last_night_is_elsewhere():
    route = _route_for_prompt()
    route.legs = route.legs[:-1]
    route.legs[-1]["end_day"] = 9
    prompt = _prompt(route, _confirmed())
    assert "DEPARTURE LOGISTICS" in prompt
    assert "Transfer: Kanha → Jabalpur airport" in prompt
    assert "at 2026-11-09 18:30" in prompt


def test_prompt_anchors_a_country_on_the_routes_cities_not_the_centroid():
    prompt = _prompt(_route_for_prompt(), _confirmed())
    assert "The route's cities are at: Pench (21.75, 79.30)" in prompt
    assert "within roughly 400 km of there" not in prompt


def test_prompt_route_table_shows_how_each_leg_is_reached():
    prompt = _prompt(_route_for_prompt(), _confirmed())
    assert "Kanha at 22.33, 80.63 (sleep in Kanha) — arrive from Pench by car, ~200 km" in prompt


def test_prompt_without_a_flight_targets_the_first_leg_by_ground():
    prompt = _prompt(_route_for_prompt(), None)
    assert "GETTING TO PENCH (NO FLIGHT BOOKED" in prompt
    assert "ARRIVAL LOGISTICS" not in prompt and "CONFIRMED FLIGHTS" not in prompt


def test_prompt_for_a_legacy_flight_without_legs_still_works():
    legacy = {"title": "Cheapest Fare", "route": "CMB → DEL", "currency": "USD",
              "price_per_traveler": 300, "trip_type": "round_trip"}
    prompt = _prompt(None, legacy)
    assert "OUTBOUND: CMB → DEL" in prompt
    assert "- RETURN: from the arrival airport back to the origin" in prompt
    assert "round trip via DEL" in prompt


# ── SerpApi response cache ──────────────────────────────────────────────────

def test_cache_key_never_contains_the_api_key():
    key = serpapi_service._cache_key({"engine": "google_flights", "api_key": "secret", "departure_id": "CMB"})
    assert "secret" not in key and key.startswith("serpapi:v1:google_flights:")
    assert key == serpapi_service._cache_key({"engine": "google_flights", "api_key": "other", "departure_id": "CMB"})


def test_a_cached_search_makes_no_http_call(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    store = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value
    monkeypatch.setattr(serpapi_service.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(serpapi_service.place_cache_service, "set_raw", _set)

    calls = []

    class _Resp:
        status_code = 200
        text = ""
        def json(self):
            return ROUND_TRIP

    class _Client:
        def __init__(self, *a, **kw):
            pass
        async def __aenter__(self):
            return self
        async def __aexit__(self, *a):
            return False
        async def get(self, url, params=None):
            calls.append(params)
            return _Resp()
    monkeypatch.setattr(serpapi_service.httpx, "AsyncClient", _Client)

    serp = serpapi_service.SerpApiService("k")
    first = asyncio.run(serp.search_flights(departure_city="CMB", destination="DEL", outbound_date="2026-11-01", return_date="2026-11-09"))
    second = asyncio.run(serp.search_flights(departure_city="CMB", destination="DEL", outbound_date="2026-11-01", return_date="2026-11-09"))
    assert len(calls) == 1 and first == second == ROUND_TRIP
    assert len(store) == 1


def test_an_empty_result_is_not_cached(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    store = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value
    monkeypatch.setattr(serpapi_service.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(serpapi_service.place_cache_service, "set_raw", _set)

    class _Resp:
        status_code = 200
        text = ""
        def json(self):
            return {"search_metadata": {}}

    class _Client:
        def __init__(self, *a, **kw):
            pass
        async def __aenter__(self):
            return self
        async def __aexit__(self, *a):
            return False
        async def get(self, url, params=None):
            return _Resp()
    monkeypatch.setattr(serpapi_service.httpx, "AsyncClient", _Client)

    asyncio.run(serpapi_service.SerpApiService("k").search_flights(departure_city="CMB", destination="DEL"))
    assert store == {}


def test_cache_errors_are_swallowed(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)

    async def _boom(*a, **kw):
        raise ConnectionError("redis down")
    monkeypatch.setattr(serpapi_service.place_cache_service, "get_raw", _boom)
    monkeypatch.setattr(serpapi_service.place_cache_service, "set_raw", _boom)

    class _Resp:
        status_code = 200
        text = ""
        def json(self):
            return ROUND_TRIP

    class _Client:
        def __init__(self, *a, **kw):
            pass
        async def __aenter__(self):
            return self
        async def __aexit__(self, *a):
            return False
        async def get(self, url, params=None):
            return _Resp()
    monkeypatch.setattr(serpapi_service.httpx, "AsyncClient", _Client)

    result = asyncio.run(serpapi_service.SerpApiService("k").search_flights(departure_city="CMB", destination="DEL"))
    assert result == ROUND_TRIP


# ── Truncated responses ─────────────────────────────────────────────────────

def _long_plan(days):
    return {
        "title": "Rajasthan", "days": days,
        "day_plans": [
            {"day": d, "theme": f"Day {d}", "activities": [
                {"time": "09:00", "name": f"Fort {d}", "cost": "INR 500", "type": "attraction",
                 "tip": 'Say "hello" \\ and mind the {braces} [inside] strings',
                 "restaurants": [{"name": "Dhaba", "cuisine": "Rajasthani", "price_range": "INR 300"}]},
                {"time": "13:00", "name": f"Lunch {d}", "cost": "INR 400", "type": "dining"},
            ]} for d in range(1, days + 1)
        ],
    }


def test_a_response_cut_off_inside_a_restaurant_list_is_recovered():
    full = json.dumps(_long_plan(14))
    cut = full[: int(len(full) * 0.55)]                 # mid-object, deep inside a day
    plan = svc._parse_json(cut)
    assert plan["title"] == "Rajasthan"
    assert 5 <= len(plan["day_plans"]) < 14
    assert all(a["name"] for d in plan["day_plans"] for a in d["activities"])


def test_a_response_cut_off_inside_a_string_is_recovered():
    full = json.dumps(_long_plan(3))
    idx = full.index('mind the {braces}') + 8          # inside the tip string of day 1
    plan = svc._parse_json(full[:idx])
    assert plan["title"] == "Rajasthan"


def test_a_complete_response_is_untouched():
    full = json.dumps(_long_plan(4))
    assert svc._parse_json(full) == _long_plan(4)


def test_garbage_still_raises():
    with pytest.raises(ValueError):
        svc._parse_json("Sorry, I cannot help with that.")


def test_output_budget_scales_with_the_trip():
    assert svc._itinerary_token_budget(3) > 8192
    assert svc._itinerary_token_budget(14) >= 20000
    assert svc._itinerary_token_budget(14) <= svc._ITINERARY_TOKENS_MAX
    assert svc._itinerary_timeout_s(14) > svc._itinerary_timeout_s(3) >= 90


def test_the_header_is_rewritten_when_the_return_leg_lands():
    """A round-trip card is built before its return is priced, so its header
    quoted the outbound alone: "1 stop · 10h 55m" over a 22h 35m journey."""
    result = _round_trip()
    s = next(x for x in result["strategies"] if x["tier"] == "minimum")
    before = s["title"]
    assert attach_return_leg(s, ROUND_TRIP_RETURN, currency="USD", return_date="2026-11-09")
    assert s["title"] != before
    mins = s["total_duration_minutes"]
    assert s["title"].endswith(f"{mins // 60}h {mins % 60}m"), (s["title"], mins)


# ── Locating an airport by its code ─────────────────────────────────────────


def test_an_airport_is_looked_up_with_its_city_and_country(monkeypatch):
    """A bare code is ambiguous and the wrong answer is silent.

    "RAK airport" resolves to Ras Al Khaimah in the UAE. A live Morocco plan
    therefore rejected Marrakesh's own airport as foreign and flew the
    traveller into Casablanca, 197 km from the first city — and cached that
    for a month under a key with no country in it, so every Morocco plan would
    have done the same.
    """
    seen = {}

    async def _verify(query, **kw):
        seen["query"] = query
        return SimpleNamespace(
            checked=True, latitude=31.6, longitude=-8.03,
            country_code="MA", resolved_name="Marrakesh Menara Airport",
        )

    async def _get_raw(key):
        seen["cache_key"] = key
        return None

    async def _set_raw(key, value, ttl=0):
        return None

    monkeypatch.setattr(svc.geo_resolver, "verify_place", _verify)
    monkeypatch.setattr(svc.place_cache_service, "get_raw", _get_raw)
    monkeypatch.setattr(svc.place_cache_service, "set_raw", _set_raw)

    geo = svc.geo_resolver.DestinationContext(
        query="Morocco", country="Morocco", country_code="MA", source="places",
    )
    found = asyncio.run(svc._airport_geo("RAK", geo, None, city="Marrakech"))

    assert found and found["country_code"] == "MA"
    assert "Morocco" in seen["query"], seen["query"]
    assert "Marrakech" in seen["query"], seen["query"]
    assert "RAK" in seen["query"], seen["query"]
    # One country's answer must never be served to another's plan.
    assert "MA" in seen["cache_key"], seen["cache_key"]
    assert not seen["cache_key"].startswith("geo:airport:v1:"), "stale cache generation"


# ── The legs and the itinerary must agree about the travel day ──────────────
#
# The legs book the hotels; the day plans are what the traveller follows. A
# live Rome/Florence/Venice/Milan trip ran every train one day before its leg
# began, so the traveller slept in the next city with a room booked in the
# last one — Rome over-booked by a night, Milan under-booked by one.


def _italy_legs():
    return [
        {"city": "Rome",     "start_day": 1,  "end_day": 5,  "nights": 5},
        {"city": "Florence", "start_day": 6,  "end_day": 9,  "nights": 4},
        {"city": "Venice",   "start_day": 10, "end_day": 12, "nights": 3},
        {"city": "Milan",    "start_day": 13, "end_day": 14, "nights": 1},
    ]


def _italy_days():
    travel = {5: "Train: Rome → Florence", 9: "Train: Florence → Venice",
              12: "Train: Venice → Milan"}
    days = []
    for n in range(1, 15):
        acts = [{"time": "09:00", "name": "Morning at Leisure", "type": "exploration"}]
        if n in travel:
            acts.insert(0, {"time": "08:00", "name": travel[n], "type": "transport"})
        days.append({"day": n, "theme": f"Day {n}", "activities": acts})
    return days


def test_a_leg_boundary_follows_the_day_the_itinerary_travels():
    legs = _italy_legs()
    moved = svc._align_legs_to_itinerary(legs, _italy_days(), 14)
    assert len(moved) == 3, moved
    assert [(l["city"], l["start_day"], l["end_day"]) for l in legs] == [
        ("Rome", 1, 4), ("Florence", 5, 8), ("Venice", 9, 11), ("Milan", 12, 14),
    ]


def test_realigned_nights_still_add_up_to_the_trip():
    legs = _italy_legs()
    svc._align_legs_to_itinerary(legs, _italy_days(), 14)
    # 14 days away is 13 nights: the last day is the flight home.
    assert sum(l["nights"] for l in legs) == 13
    assert [l["nights"] for l in legs] == [4, 4, 3, 2]


def test_legs_that_already_agree_are_left_alone():
    legs = [
        {"city": "Cairo",  "start_day": 1, "end_day": 4,  "nights": 4},
        {"city": "Aswan",  "start_day": 5, "end_day": 14, "nights": 9},
    ]
    days = [{"day": n, "theme": "", "activities":
             ([{"name": "Flight: Cairo → Aswan", "type": "transport"}] if n == 5 else [])}
            for n in range(1, 15)]
    assert svc._align_legs_to_itinerary(legs, days, 14) == []
    assert [(l["start_day"], l["end_day"]) for l in legs] == [(1, 4), (5, 14)]


def test_a_boundary_is_not_moved_so_far_it_empties_a_city():
    """A stray "to Florence" on day 1 must not wipe out Rome."""
    legs = _italy_legs()
    days = [{"day": n, "theme": "", "activities":
             ([{"name": "Transfer to Florence", "type": "transport"}] if n == 1 else [])}
            for n in range(1, 15)]
    moved = svc._align_legs_to_itinerary(legs, days, 14)
    assert legs[0]["start_day"] == 1 and legs[0]["end_day"] == 5
    assert any("no nights" in m for m in moved), moved


def test_stays_are_retotalled_when_a_boundary_moves():
    legs = _italy_legs()
    svc._align_legs_to_itinerary(legs, _italy_days(), 14)
    hotels = {"strategies": [
        {"city": "Rome",  "leg_index": 0, "price_per_night": "EUR 100",
         "nights": 5, "rooms": 2, "total_estimated_cost": "EUR 1,000"},
        {"city": "Milan", "leg_index": 3, "price_per_night": "EUR 80",
         "nights": 1, "rooms": 2, "total_estimated_cost": "EUR 160"},
    ]}
    svc._reprice_stays(hotels, legs, "EUR")
    rome, milan = hotels["strategies"]
    assert (rome["nights"], rome["total_estimated_cost"]) == (4, "EUR 800")
    assert (milan["nights"], milan["total_estimated_cost"]) == (2, "EUR 320")


# ── A route that cannot be flown, versus a lookup that failed ───────────────


class _EmptyRouteSerp:
    """Google answers, and the answer is that nothing flies this route."""

    def __init__(self, key, **kw):
        pass

    async def search_flights(self, **kw):
        return {"_serpapi_status": "no_results"}

    async def search_flights_return(self, **kw):
        return {"_serpapi_status": "no_results"}


class _BrokenSerp:
    """We never got an answer — a timeout, a spent quota, a 500."""

    def __init__(self, key, **kw):
        pass

    async def search_flights(self, **kw):
        return {}

    async def search_flights_return(self, **kw):
        return {}


def _delhi_route():
    return RoutePlan(
        legs=[{"city": "Delhi", "start_day": 1, "end_day": 9, "nights": 8}],
        arrival={"iata": "DEL", "city": "Delhi"}, departure={"iata": "DEL", "city": "Delhi"},
        arrival_code="DEL", departure_code="DEL", source="planner",
    )


def test_an_unflyable_route_returns_no_fares_and_says_why(monkeypatch):
    """No airline flies it, so there is no fare at any price to invent."""
    monkeypatch.setattr(svc, "SerpApiService", _EmptyRouteSerp)
    result = _flights(_delhi_route())
    assert result["strategies"] == []
    assert result["flights_available"] is False
    assert result["unavailable_reason"] == "none_found"
    message = result["unavailable_message"]
    # Named for the traveller, not the routing table: "Delhi", not "DEL".
    assert "Delhi" in message and "2026-11-01" in message, message
    assert "no route" in message.lower()


def test_a_failed_lookup_still_offers_estimated_fares(monkeypatch):
    """Flights probably do exist; the failure was ours, and the cards say so."""
    async def _estimate(prompt, api_key, **kw):
        return json.dumps({"strategies": [{
            "title": "x", "estimated_price_range": "USD 400 - 600",
            "route": "CMB → DEL", "return_route": "DEL → CMB",
            "airlines": ["IndiGo"], "stops": 1, "total_duration": "6h 30m",
            "return_duration": "6h 10m",
        }]}), []

    monkeypatch.setattr(svc, "SerpApiService", _BrokenSerp)
    monkeypatch.setattr(svc, "_call_gemini", _estimate)
    result = _flights(_delhi_route(), api_key="k")
    assert result.get("flights_available") is not False
    assert result.get("unavailable_reason") in (None, "")
    assert result["strategies"], "a failed lookup must not empty the section"
    assert all(s["is_live_price"] is False for s in result["strategies"])


def test_a_domestic_hop_says_take_the_road_not_no_flights(serp):
    """Kinniya and Colombo both resolve to CMB, so nothing flies between them.

    This used to return a bare {} and the section vanished — a traveller
    planning the journey locals make by bus got an itinerary, a hotel list and
    no word on how to get there.
    """
    result = asyncio.run(svc.generate_flight_strategies(
        departure_city="Kinniya", departure_country="Sri Lanka", destination="Colombo",
        days=5, budget=40000, currency="LKR", travelers=2,
        flight_start_date="2026-11-02", flight_end_date="2026-11-06",
        api_key="", serpapi_key="", destination_geo=None, route_plan=None,
    ))
    assert result["strategies"] == []
    assert result["flights_available"] is False
    assert result["unavailable_reason"] == "same_airport"
    message = result["unavailable_message"]
    assert "Kinniya" in message and "Colombo" in message and "CMB" in message
    assert "road or rail" in message
    # Nothing here may read as a fare for a flight that does not exist.
    assert "price_per_traveler" not in result


def test_an_unknown_departure_says_so_rather_than_vanishing(serp):
    result = asyncio.run(svc.generate_flight_strategies(
        departure_city="Xyzzy Nowhere Township", departure_country="", destination="Colombo",
        days=5, budget=40000, currency="LKR", travelers=2,
        flight_start_date="2026-11-02", flight_end_date="2026-11-06",
        api_key="", serpapi_key="", destination_geo=None, route_plan=None,
    ))
    assert result["unavailable_reason"] == "no_airport"
    assert "Xyzzy Nowhere Township" in result["unavailable_message"]


def test_every_empty_flight_section_carries_a_reason(serp):
    """Three different roads to an empty section; none may be silent."""
    cases = [
        ("Kinniya", "Colombo", "same_airport"),
        ("Xyzzy Nowhere Township", "Colombo", "no_airport"),
    ]
    for departure, destination, expected in cases:
        result = asyncio.run(svc.generate_flight_strategies(
            departure_city=departure, departure_country="Sri Lanka", destination=destination,
            days=5, budget=40000, currency="LKR", travelers=2,
            flight_start_date="2026-11-02", flight_end_date="2026-11-06",
            api_key="", serpapi_key="", destination_geo=None, route_plan=None,
        ))
        assert result.get("unavailable_reason") == expected
        assert result.get("unavailable_message"), f"{departure} -> {destination} said nothing"


# ── Getting there when there is no flight ───────────────────────────────────


def _ground_prompt(departure_country, country, country_code, city, home="Kinniya"):
    return svc._build_prompt(
        city, "Cultural", 40000, 5, "LKR", travelers=2,
        departure_city=home, departure_country=departure_country,
        legs=[{"city": city, "start_day": 1, "end_day": 5, "nights": 4,
               "latitude": 6.93, "longitude": 79.86}],
        geo=svc.geo_resolver.DestinationContext(
            query=city, country=country, country_code=country_code, source="places"),
    )


def test_a_domestic_trip_with_no_flight_plans_the_road_journey():
    """Day 1 used to open with sightseeing in the destination, while the
    traveller was really on a six-hour bus — and every day after was wrong."""
    prompt = _ground_prompt("Sri Lanka", "Sri Lanka", "LK", "Colombo")
    assert "GETTING THERE AND BACK" in prompt
    assert "Travel: Kinniya -> Colombo" in prompt
    assert "Travel: Colombo -> Kinniya" in prompt
    assert "bus, train, or private car" in prompt
    # A travel day is not a sightseeing day.
    assert "do not fill a travel day with sightseeing" in prompt
    # And nothing may pretend there was a flight.
    assert "Never write an arrival by air" in prompt


def test_an_international_trip_is_never_sent_overland():
    """Colombo to Italy has no bus. Silence beats bad advice."""
    prompt = _ground_prompt("Sri Lanka", "Italy", "IT", "Rome", home="Colombo")
    assert "GETTING THERE AND BACK" not in prompt


def test_an_unknown_destination_country_is_not_assumed_domestic():
    prompt = svc._build_prompt(
        "Somewhere", "Cultural", 40000, 5, "LKR", travelers=2,
        departure_city="Kinniya", departure_country="Sri Lanka",
        legs=[{"city": "Somewhere", "start_day": 1, "end_day": 5, "nights": 4,
               "latitude": 6.9, "longitude": 79.8}],
        geo=None,
    )
    assert "GETTING THERE AND BACK" not in prompt


def test_a_flight_trip_keeps_its_airport_transfers():
    """The ground block must not displace the arrival logistics."""
    prompt = svc._build_prompt(
        "Colombo", "Cultural", 40000, 5, "LKR", travelers=2,
        departure_city="Kinniya", departure_country="Sri Lanka",
        legs=[{"city": "Colombo", "start_day": 1, "end_day": 5, "nights": 4,
               "latitude": 6.93, "longitude": 79.86}],
        geo=svc.geo_resolver.DestinationContext(
            query="Colombo", country="Sri Lanka", country_code="LK", source="places"),
        confirmed_flight={
            "title": "1 stop · 4h 0m", "route": "MAA → CMB", "currency": "LKR",
            "price_per_traveler": 30000, "trip_type": "round_trip",
            "outbound": {"origin": "MAA", "destination": "CMB"},
        },
    )
    assert "GETTING THERE AND BACK" not in prompt
    # (No ARRIVAL LOGISTICS here: the flight lands at CMB and the first night
    # is in Colombo, so there is no transfer to describe.)
    assert "CONFIRMED FLIGHTS" in prompt


# ── Flights between cities inside the trip ──────────────────────────────────
#
# A leg the planner marks "arrive_by": "flight" is a real ticket, and it was
# the one flight nobody priced: the model wrote a figure and credited it to a
# site it had never asked. Two saved plans put the same one-hour Egyptian hop
# at INR 10,000 and INR 20,000, neither with a booking link.


HOP = {
    "best_flights": [
        _option(90, [_leg("CAI", "ASW", "EgyptAir", "MS 81", minutes=80)], 80),
    ],
    "other_flights": [
        _option(140, [_leg("CAI", "ASW", "Nile Air", "NP 5", minutes=95)], 95),
    ],
}


class _HopSerp:
    searches = []

    def __init__(self, key, **kw):
        pass

    async def search_flights(self, **kw):
        _HopSerp.searches.append(kw)
        return HOP

    async def search_flights_return(self, **kw):
        return {}


def _egypt_legs():
    return [
        {"city": "Cairo", "start_day": 1, "end_day": 4, "nights": 4,
         "latitude": 30.04, "longitude": 31.24, "arrive_by": "none"},
        {"city": "Aswan", "start_day": 5, "end_day": 9, "nights": 4,
         "latitude": 24.09, "longitude": 32.90, "arrive_by": "flight"},
    ]


# Aswan and Luxor are not in the static airport table, so resolving them costs
# a Gemini lookup. These tests are about the hop, not the lookup.
_HOP_CODES = {"Cairo": "CAI", "Aswan": "ASW", "Luxor": "LXR", "Hurghada": "HRG"}


def _hops(monkeypatch, legs=None, **kw):
    _HopSerp.searches = []
    monkeypatch.setattr(svc, "SerpApiService", _HopSerp)

    async def _code(place, country, api_key, **kwargs):
        if place in _HOP_CODES:
            return _HOP_CODES[place]
        # Distinct per city, so a capped run is genuinely capped and not just
        # skipped for sharing an airport with the leg before it.
        return f"Z{str(place)[-1]}" if str(place).startswith("City") else ""

    monkeypatch.setattr(svc, "_resolve_airport_code", _code)
    args = dict(
        legs=legs if legs is not None else _egypt_legs(),
        geo=svc.geo_resolver.DestinationContext(
            query="Egypt", country="Egypt", country_code="EG", source="places"),
        currency="INR", travelers=2, start_date="2026-11-02",
        api_key="", serpapi_key="k",
    )
    args.update(kw)
    return asyncio.run(svc.generate_inter_city_flights(**args))


def test_a_flown_leg_is_priced_from_google(monkeypatch):
    hops = _hops(monkeypatch)
    assert len(hops) == 1
    hop = hops[0]
    assert hop["from_city"] == "Cairo" and hop["to_city"] == "Aswan"
    assert hop["day"] == 5 and hop["date"] == "2026-11-06"   # day 5 of a 2 Nov start
    assert hop["price_per_traveler"] == 90 and hop["price_total"] == 180
    assert hop["is_live_price"] is True
    assert hop["price_source"] == "google_flights_serpapi"
    assert hop["booking_url"], "a priced hop must be bookable"
    # The cheapest of the two, not whichever Google listed first.
    assert hop["airlines"] == ["EgyptAir"]


def test_the_hop_search_is_one_way_on_the_travel_date(monkeypatch):
    _hops(monkeypatch)
    assert len(_HopSerp.searches) == 1
    search = _HopSerp.searches[0]
    assert search["one_way"] is True
    assert search["return_date"] == ""
    assert search["outbound_date"] == "2026-11-06"
    assert search["adults"] == 1, "the fare must stay per-traveller"


def test_legs_reached_by_road_cost_no_search(monkeypatch):
    legs = _egypt_legs()
    legs[1]["arrive_by"] = "train"
    assert _hops(monkeypatch, legs=legs) == []
    assert _HopSerp.searches == []


def test_the_number_of_searches_is_capped(monkeypatch):
    legs = [{"city": f"City{i}", "start_day": i, "end_day": i, "nights": 1,
             "latitude": 30.0, "longitude": 31.0,
             "arrive_by": "none" if i == 1 else "flight"} for i in range(1, 9)]
    hops = _hops(monkeypatch, legs=legs)
    # Seven flown legs offered; only the cap is bought.
    assert sum(1 for l in legs if l["arrive_by"] == "flight") == 7
    assert len(hops) == svc._MAX_HOP_SEARCHES
    assert len(_HopSerp.searches) == svc._MAX_HOP_SEARCHES


def test_no_serpapi_key_means_no_hop_searches(monkeypatch):
    assert _hops(monkeypatch, serpapi_key="") == []


def test_the_itinerary_carries_the_searched_fare_not_the_models(monkeypatch):
    """The prompt asks; this guarantees. The model never owns a flight price."""
    days = [{"day": 5, "activities": [
        {"type": "transport", "name": "Flight: Cairo -> Aswan",
         "cost": "INR 20,000", "price_source": "Skyscanner, Expedia"},
        {"type": "dining", "name": "Lunch in Aswan", "cost": "INR 900"},
    ]}]
    hops = _hops(monkeypatch)
    assert svc._apply_inter_city_fares(days, hops) == 1
    flight, lunch = days[0]["activities"]
    assert flight["cost"] == "INR 180"
    assert flight["price_source"] == "Google Flights"
    assert flight["price_confidence"] == "Fixed"
    assert flight["booking_url"]
    assert "each x 2 travellers" in flight["price_basis"]
    # Nothing else on the day is touched.
    assert lunch["cost"] == "INR 900" and "booking_url" not in lunch


def test_an_unmatched_hop_changes_nothing(monkeypatch):
    days = [{"day": 5, "activities": [{"type": "dining", "name": "Lunch", "cost": "INR 900"}]}]
    before = json.dumps(days, sort_keys=True)
    assert svc._apply_inter_city_fares(days, _hops(monkeypatch)) == 0
    assert json.dumps(days, sort_keys=True) == before
