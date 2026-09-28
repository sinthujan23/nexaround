"""The airport-to-town journey: train if one runs, else bus, else the road.

Client report (2026-09-27, Dubai -> Andorra): "first check is for airport,
then train, then bus, then other means". Google Directions answers that from
real timetables; these tests feed it canned answers. No network.
"""
import asyncio

import pytest

from app.services import ground_route_service as svc
from app.services import place_cache_service


def _step(vehicle, metres, name):
    return {
        "travel_mode": "TRANSIT",
        "distance": {"value": metres},
        "transit_details": {"line": {"vehicle": {"type": vehicle}, "short_name": name}},
    }


def _answer(*steps, seconds=16200, metres=206000, fare="€33.00"):
    route = {"legs": [{
        "duration": {"value": seconds},
        "distance": {"value": metres},
        "steps": [{"travel_mode": "WALKING", "distance": {"value": 300}}, *steps],
    }]}
    if fare:
        route["fare"] = {"text": fare}
    return {"status": "OK", "routes": [route]}


# The real answer for Barcelona airport -> Andorra la Vella, asked with
# transit_mode=rail: Google still returns the coach, because no train runs.
BCN_TO_ANDORRA = _answer(_step("BUS", 205000, "Andbus"))


def test_no_train_means_the_bus_google_returns_anyway():
    route = svc.parse_transit(BCN_TO_ANDORRA)
    assert route["mode"] == "bus"
    assert route["lines"] == ["Andbus"]
    assert route["duration_min"] == 270
    assert route["fare"] == "€33.00"


def test_a_train_wins_when_one_runs():
    route = svc.parse_transit(_answer(_step("HEAVY_RAIL", 120000, "RE"), fare=""))
    assert route["mode"] == "train"


def test_the_longest_ride_decides_the_mode():
    """A metro hop to the coach station does not make a bus trip a train trip."""
    route = svc.parse_transit(_answer(_step("SUBWAY", 4000, "L9"), _step("INTERCITY_BUS", 190000, "Alsa")))
    assert route["mode"] == "bus"
    assert route["lines"] == ["L9", "Alsa"]


def test_ferry_and_tram_are_named_as_themselves():
    assert svc.parse_transit(_answer(_step("FERRY", 30000, "")))["mode"] == "ferry"
    assert svc.parse_transit(_answer(_step("TRAM", 9000, "T1")))["mode"] == "tram"


def test_no_transit_answer_is_none():
    assert svc.parse_transit({"status": "ZERO_RESULTS", "routes": []}) is None
    assert svc.parse_transit({}) is None
    assert svc.parse_transit(_answer(fare="")) is None  # walking only


def test_driving_answer():
    route = svc.parse_driving({"status": "OK", "routes": [{"legs": [{
        "duration": {"value": 7200}, "distance": {"value": 150000}}]}]})
    assert route == {
        "mode": "car", "duration_min": 120, "distance_km": 150,
        "fare": "", "lines": [], "source": "Google Maps",
    }


def test_describe_reads_like_an_instruction():
    text = svc.describe(svc.parse_transit(BCN_TO_ANDORRA))
    assert text == "bus (Andbus), about 4 h 30 min, 206 km, fare about €33.00 per person"
    assert svc.describe({"mode": "car", "duration_min": 45, "distance_km": 30}) == (
        "car or taxi, about 45 min, 30 km"
    )
    assert svc.describe(None) == ""


@pytest.fixture
def cache(monkeypatch):
    store = {}

    async def get_raw(key):
        return store.get(key, (None,))[0]

    async def set_raw(key, value, ttl=0):
        store[key] = (value, ttl)

    monkeypatch.setattr(place_cache_service, "get_raw", get_raw)
    monkeypatch.setattr(place_cache_service, "set_raw", set_raw)
    return store


def _stub_google(monkeypatch, *answers):
    calls = []

    async def fake(client, api_key, params, op):
        calls.append(params)
        answer = answers[min(len(calls) - 1, len(answers) - 1)]
        if isinstance(answer, Exception):
            raise answer
        return answer

    monkeypatch.setattr(svc, "_directions", fake)
    return calls


BCN = (41.2971, 2.0785)
ANDORRA = (42.5078, 1.5211)


def test_one_transit_call_then_the_cache(cache, monkeypatch):
    calls = _stub_google(monkeypatch, BCN_TO_ANDORRA)
    first = asyncio.run(svc.best_route(BCN, ANDORRA, "key"))
    again = asyncio.run(svc.best_route(BCN, ANDORRA, "key"))
    assert first["mode"] == "bus" and again == first
    assert len(calls) == 1
    assert calls[0]["mode"] == "transit" and calls[0]["transit_mode"] == "rail"
    (value, ttl), = cache.values()
    assert ttl == svc._CACHE_TTL


def test_no_transit_falls_back_to_the_road(cache, monkeypatch):
    road = {"status": "OK", "routes": [{"legs": [{
        "duration": {"value": 5400}, "distance": {"value": 90000}}]}]}
    calls = _stub_google(monkeypatch, {"status": "ZERO_RESULTS", "routes": []}, road)
    route = asyncio.run(svc.best_route(BCN, ANDORRA, "key"))
    assert route["mode"] == "car"
    assert [c["mode"] for c in calls] == ["transit", "driving"]


def test_nothing_at_all_is_remembered_for_a_day(cache, monkeypatch):
    _stub_google(monkeypatch, {"status": "ZERO_RESULTS", "routes": []})
    assert asyncio.run(svc.best_route(BCN, ANDORRA, "key")) is None
    (value, ttl), = cache.values()
    assert value == svc._MISS and ttl == svc._MISS_TTL


def test_a_failure_is_not_cached(cache, monkeypatch):
    _stub_google(monkeypatch, RuntimeError("quota"))
    assert asyncio.run(svc.best_route(BCN, ANDORRA, "key")) is None
    assert cache == {}


def test_missing_inputs_ask_nothing(cache, monkeypatch):
    calls = _stub_google(monkeypatch, BCN_TO_ANDORRA)
    assert asyncio.run(svc.best_route(None, ANDORRA, "key")) is None
    assert asyncio.run(svc.best_route(BCN, ANDORRA, "")) is None
    assert calls == []
