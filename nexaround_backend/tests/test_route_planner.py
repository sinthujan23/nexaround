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
    async def _geo(code, geo, budget=None):
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

    async def _no_prose(data, **kw):
        return data
    monkeypatch.setattr(svc, "_add_flight_prose", _no_prose)
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


def test_without_a_route_the_destination_is_resolved_as_before(serp):
    result = _flights(None, destination="Delhi")
    assert serp.searches[0]["destination"] == "DEL"
    assert result["trip_type"] == "round_trip"
    assert result["arrival_airport"]["iata"] == "DEL" and result["departure_airport"]["iata"] == "DEL"


def test_a_gateway_shared_with_the_origin_means_no_flights(serp):
    route = RoutePlan(legs=[{"city": "Kandy", "start_day": 1, "end_day": 9, "nights": 8}],
                      arrival_code="CMB", departure_code="CMB")
    assert _flights(route) == {}
    assert serp.searches == []


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
    assert "Kanha (sleep in Kanha) — arrive from Pench by car, ~200 km" in prompt


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
