"""A route the traveller was shown, approved, and generation then reuses.

For a country like India or China the region a plan picks is the single
biggest decision in it, and it used to be made silently inside generation.
The preview endpoint runs the same `plan_route` call up front so the traveller
can accept, edit or reshuffle it before the expensive grounded itinerary pass
is paid for.

The rule these tests hold to: a preset is *checked*, never trusted. It arrives
from the client, where the city list may have been edited, and the interesting
failure is silent — `_validate_legs` degrades an unusable leg list to a single
leg without reporting a reason, so a preset whose days no longer tile 1..N
would otherwise be accepted as a one-city trip nobody asked for.
"""
import asyncio
import json
from unittest.mock import patch

import pytest

from app.services import odyssey_ai_service as svc


GOLDEN_TRIANGLE = {
    "legs": [
        {"city": "Delhi", "country": "IN", "start_day": 1, "end_day": 2,
         "latitude": 28.61, "longitude": 77.21, "arrive_by": "flight", "from_previous_km": 0},
        {"city": "Agra", "country": "IN", "start_day": 3, "end_day": 3,
         "latitude": 27.18, "longitude": 78.01, "arrive_by": "train", "from_previous_km": 230},
        {"city": "Jaipur", "country": "IN", "start_day": 4, "end_day": 5,
         "latitude": 26.91, "longitude": 75.79, "arrive_by": "bus", "from_previous_km": 240},
    ],
    "arrival_airport": {"iata": "DEL", "city": "Delhi", "name": "Indira Gandhi"},
    "departure_airport": {"iata": "JAI", "city": "Jaipur", "name": "Jaipur"},
    "region": "Golden Triangle",
}


def _copy(route: dict) -> dict:
    return json.loads(json.dumps(route))


def _planner_returning(route: dict, calls: list):
    async def _fake(prompt, key, **kwargs):
        calls.append(prompt)
        return json.dumps(route), []
    return _fake


def _plan(**kwargs):
    calls: list = []
    with patch.object(svc, "_call_gemini", _planner_returning(GOLDEN_TRIANGLE, calls)):
        plan = asyncio.run(svc.plan_route(
            destination="India", days=5, mood="Cultural", travelers=2,
            api_key="test-key", **kwargs,
        ))
    return plan, calls


def test_approved_route_is_reused_without_asking_the_model_again():
    """The whole point: accepting a preview must not re-plan the trip."""
    plan, calls = _plan(preset=_copy(GOLDEN_TRIANGLE))
    assert [leg["city"] for leg in plan.legs] == ["Delhi", "Agra", "Jaipur"]
    assert plan.source == "preset"
    assert calls == [], "a preset the traveller approved was planned a second time"


def test_preset_days_that_no_longer_tile_are_rejected_not_collapsed():
    """Editing the city list can leave overlapping days.

    `_validate_legs` answers that with a single leg and no reason, so without
    the city-list comparison in `plan_route` this preset would be accepted as
    a one-city trip.
    """
    broken = _copy(GOLDEN_TRIANGLE)
    broken["legs"][1]["end_day"] = 4               # overlaps Jaipur

    collapsed, _ = svc._validate_route(broken, "India", 5, "", None)
    assert [leg["city"] for leg in collapsed.legs] == ["India"], (
        "guarding this is only necessary because the collapse is silent"
    )

    plan, calls = _plan(preset=broken)
    assert plan.source == "planner", "a collapsed preset was accepted"
    assert len(calls) == 1, "rejecting a preset must fall back to planning the trip"


def test_preset_with_an_impossible_hop_is_rejected():
    """The same coherence check any planned route faces, applied to a preset."""
    far = _copy(GOLDEN_TRIANGLE)
    far["legs"][2].update(city="Chennai", latitude=13.08, longitude=80.27)
    plan, calls = _plan(preset=far)
    assert plan.source == "planner"
    assert len(calls) == 1


def test_no_preset_plans_exactly_as_before():
    plan, calls = _plan()
    assert plan.source == "planner"
    assert len(calls) == 1


def test_shuffle_tells_the_planner_which_cities_were_turned_down():
    _, calls = _plan(exclude_cities=["Delhi", "Agra", "Jaipur"])
    prompt = calls[0]
    assert "already been shown" in prompt
    for city in ("Delhi", "Agra", "Jaipur"):
        assert city in prompt
    assert "do not simply pick" in prompt, (
        "excluding three cities must not just move the route one town over"
    )


def test_shuffle_rule_is_absent_when_nothing_was_turned_down():
    for exclude in (None, [], ["", "  "]):
        _, calls = _plan(exclude_cities=exclude)
        assert "already been shown" not in calls[0]


def test_preview_payload_round_trips_through_the_validator():
    """What the traveller is shown must be re-readable as what they approved."""
    plan, _ = _plan()
    payload = svc.route_preview_payload(plan)
    assert sorted(payload) == [
        "arrival_airport", "departure_airport", "legs", "region", "source",
    ]
    again, reasons = svc._validate_route(payload, "India", 5, "", None)
    assert reasons == []
    assert [leg["city"] for leg in again.legs] == [leg["city"] for leg in plan.legs]


def test_nights_are_recomputed_from_the_days_not_taken_from_the_client():
    """A preset that lies about nights must not mis-state the stay budget."""
    lying = _copy(GOLDEN_TRIANGLE)
    for leg in lying["legs"]:
        leg["nights"] = 99
    plan, _ = _plan(preset=lying)
    assert [leg["nights"] for leg in plan.legs] == [2, 1, 1]
    assert sum(leg["nights"] for leg in plan.legs) == 4, "5 days is 4 nights"
