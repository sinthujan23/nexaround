"""Geographic grounding for Odyssey generation.

Client report: a trip to **Port Blair** — renamed **Sri Vijaya Puram** in 2024 —
came back with the Stays tab full of real Andaman hotels while the itinerary
toured Kandy and the flight landed at Colombo. Hotels were right because Google
Hotels resolves the place itself; everywhere a model saw the bare destination
string, "Sri Vijaya Puram" read as Sri Lankan.

These tests pin the three defences: the static tables that make the airport
correct for free, the country gate on city legs, and the drift scan that reads
a finished plan. Nothing here touches the network.
"""
import asyncio

import pytest

from app.services import geo_resolver, trip_cost_floor
from app.services.geo_resolver import DestinationContext, GeoBudget
from app.services.odyssey_ai_service import (
    _AIRPORT_CODES,
    _build_prompt,
    _resolve_airport_code,
    _validate_legs,
    detect_geo_drift,
)


def _ctx(code="IN", country="India", name="Sri Vijaya Puram", lat=11.6234, lng=92.7265):
    return DestinationContext(
        query=name, name=name, country=country, country_code=code,
        admin_area="Andaman and Nicobar Islands", aliases=("port blair",),
        latitude=lat, longitude=lng, source="places",
    )


# ── The free scanner ────────────────────────────────────────────────────────

def test_scanner_catches_the_reported_city():
    """"Arrival and Kandy Exploration" on an Indian trip."""
    assert geo_resolver.foreign_place_hits(
        "Arrival and Kandy Exploration", "IN"
    ) == {"kandy": "LK"}


def test_scanner_catches_a_demonym():
    """"Sri Lankan rice and curry" — the cuisine, not the city."""
    assert geo_resolver.foreign_place_hits(
        "Try authentic Sri Lankan rice and curry.", "IN"
    ) == {"sri lanka": "LK"}


def test_scanner_does_not_read_paris_out_of_parish():
    """The suffix set deliberately excludes a bare "h"."""
    assert geo_resolver.foreign_place_hits("Visit the old parish church", "LK") == {}


def test_scanner_ignores_names_below_the_length_floor():
    """"goa", "nice" and "male" collide with ordinary English."""
    text = "a nice viewpoint for male travellers near the goad"
    assert geo_resolver.foreign_place_hits(text, "LK") == {}


def test_scanner_is_silent_when_the_trip_is_actually_there():
    """The same Kandy plan is correct for a Sri Lankan trip."""
    assert geo_resolver.foreign_place_hits("Arrival and Kandy Exploration", "LK") == {}


def test_scanner_allows_the_travellers_own_country():
    """Departure city and nationality are named all over a legitimate plan."""
    text = "Travel from Kochi to the islands"
    assert geo_resolver.foreign_place_hits(text, "LK") == {"kochi": "IN"}
    assert geo_resolver.foreign_place_hits(text, "LK", allow=frozenset({"IN"})) == {}


# ── Drift detection over a whole plan ───────────────────────────────────────

REPORTED_PLAN = {
    "summary": "An 8-day Sri Lankan adventure.",
    "day_plans": [{
        "theme": "Arrival and Kandy Exploration",
        "activities": [
            {"type": "attraction", "name": "Visit Temple of the Sacred Tooth Relic",
             "tip": "Witness the evening ceremony."},
            {"type": "dining", "name": "Dinner in Kandy",
             "tip": "Try authentic Sri Lankan rice and curry."},
        ],
    }],
}

CORRECTED_PLAN = {
    "summary": "An 8-day Andaman island adventure.",
    "day_plans": [{
        "theme": "Arrival and Port Blair Exploration",
        "activities": [
            {"type": "attraction", "name": "Visit Cellular Jail",
             "tip": "See the light and sound show."},
            {"type": "dining", "name": "Dinner at Aberdeen Bazaar",
             "tip": "Try fresh Andaman seafood."},
        ],
    }],
}


def test_drift_flags_the_reported_plan():
    drift = asyncio.run(detect_geo_drift(REPORTED_PLAN, _ctx(), sample=0))
    assert drift.ok is False
    assert "kandy" in drift.offending
    # The reasons are fed back to the model verbatim, so they must name the place.
    assert any("Kandy" in r for r in drift.reasons)


def test_drift_passes_the_corrected_plan():
    drift = asyncio.run(detect_geo_drift(CORRECTED_PLAN, _ctx(), sample=0))
    assert drift.ok is True
    assert drift.reasons == []


def test_drift_passes_the_same_plan_for_a_sri_lankan_trip():
    lk = _ctx(code="LK", country="Sri Lanka", name="Kandy", lat=7.29, lng=80.63)
    assert asyncio.run(detect_geo_drift(REPORTED_PLAN, lk, sample=0)).ok is True


def test_drift_is_skipped_when_the_destination_never_resolved():
    unresolved = DestinationContext(query="Nowhere", source="unresolved")
    assert asyncio.run(detect_geo_drift(REPORTED_PLAN, unresolved, sample=0)).ok is True


def test_drift_tier2_makes_no_calls_when_disabled(monkeypatch):
    """sample=0 must not reach Google at all, even on a clean plan."""
    calls = []

    async def _boom(*a, **k):
        calls.append(a)
        raise AssertionError("Tier 2 must not run")

    monkeypatch.setattr(geo_resolver.google_places_client, "resolve_place_geo", _boom)
    assert asyncio.run(detect_geo_drift(CORRECTED_PLAN, _ctx(), sample=0)).ok is True
    assert calls == []


# ── City legs: the country gate ─────────────────────────────────────────────

SRI_LANKAN_LEGS = [
    {"city": "Kandy", "country": "LK", "start_day": 1, "end_day": 4},
    {"city": "Galle", "country": "LK", "start_day": 5, "end_day": 8},
]


def test_legs_in_the_wrong_country_collapse_to_a_single_leg():
    """The model volunteered country="LK" and nothing used to read it."""
    legs = _validate_legs(SRI_LANKAN_LEGS, "Sri Vijaya Puram", 8, "", _ctx())
    assert [l["city"] for l in legs] == ["Sri Vijaya Puram"]
    assert legs[0]["country"] == "IN"


def test_legs_are_untouched_without_a_resolved_destination():
    """Backward compatibility: geo=None must behave exactly as before."""
    legs = _validate_legs(SRI_LANKAN_LEGS, "Sri Vijaya Puram", 8, "", None)
    assert [l["city"] for l in legs] == ["Kandy", "Galle"]


def test_legs_in_the_right_country_survive():
    lk = _ctx(code="LK", country="Sri Lanka", name="Sri Lanka", lat=7.87, lng=80.77)
    legs = _validate_legs(SRI_LANKAN_LEGS, "Sri Lanka", 8, "", lk)
    assert [l["city"] for l in legs] == ["Kandy", "Galle"]


def test_legs_without_a_country_field_are_tolerated():
    """Silence is not disagreement — our own table has never heard of most towns."""
    raw = [
        {"city": "Havelock Island", "start_day": 1, "end_day": 4},
        {"city": "Neil Island", "start_day": 5, "end_day": 8},
    ]
    legs = _validate_legs(raw, "Sri Vijaya Puram", 8, "", _ctx())
    assert [l["city"] for l in legs] == ["Havelock Island", "Neil Island"]


# ── Airports ────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("query", [
    "Port Blair", "Sri Vijaya Puram", "Andaman Islands", "Andamans",
    "Havelock Island", "Swaraj Dweep", "Andaman and Nicobar Islands",
])
def test_andaman_spellings_resolve_to_ixz(query):
    """Static and alias-driven, so no API key and no model are involved."""
    assert asyncio.run(_resolve_airport_code(query, "", "")) == "IXZ"


def test_port_blair_never_resolves_to_colombo():
    """The exact regression: a real, bookable flight to the wrong country."""
    for query in ("Port Blair", "Sri Vijaya Puram", "Andaman Islands"):
        assert asyncio.run(_resolve_airport_code(query, "", "")) != "CMB"


def test_sri_lankan_cities_still_resolve_to_colombo():
    assert asyncio.run(_resolve_airport_code("Kandy", "", "")) == "CMB"
    assert asyncio.run(_resolve_airport_code("Colombo", "", "")) == "CMB"


def test_new_airport_entries_are_not_metro_codes():
    from app.services.odyssey_ai_service import _METRO_CODES
    for name, code in _AIRPORT_CODES.items():
        for part in code.split(","):
            assert part not in _METRO_CODES, f"{name} maps to metro code {part}"


# ── Prompt grounding ────────────────────────────────────────────────────────

def _prompt(geo, legs=None):
    return _build_prompt(
        destination="Sri Vijaya Puram", mood="Adventurous", budget=150000,
        days=8, currency="INR", travelers=3, legs=legs, geo=geo,
    )


def test_single_leg_trip_still_gets_a_geographic_constraint():
    """The hole the bug fell through: route_rules only fires for multi-city."""
    one_leg = [{"city": "Sri Vijaya Puram", "start_day": 1, "end_day": 8}]
    prompt = _prompt(_ctx(), legs=one_leg)
    assert "FIXED ROUTE" not in prompt          # correctly absent for one city
    assert "DESTINATION IDENTITY" in prompt     # but the country is still pinned
    assert "It is in India" in prompt


def test_prompt_states_country_region_coords_and_former_name():
    prompt = _prompt(_ctx())
    assert "Country (authoritative): India (IN)" in prompt
    assert "Region / state: Andaman and Nicobar Islands" in prompt
    assert "11.6234, 92.7265" in prompt
    assert "Port Blair" in prompt


def test_prompt_is_unchanged_when_the_destination_did_not_resolve():
    prompt = _prompt(None)
    assert "DESTINATION IDENTITY" not in prompt
    assert "- Destination: Sri Vijaya Puram" in prompt


def test_correction_block_names_the_offending_places():
    prompt = _build_prompt(
        destination="Sri Vijaya Puram", mood="Adventurous", budget=150000,
        days=8, currency="INR", travelers=3, geo=_ctx(),
        correction='The day theme "Arrival and Kandy Exploration" names "kandy".',
    )
    assert "GEOGRAPHICALLY WRONG" in prompt
    assert "Kandy" in prompt


# ── Resolver ────────────────────────────────────────────────────────────────

def test_client_coordinates_with_a_known_country_make_no_places_call(monkeypatch):
    """The app already knows this; paying Google to confirm it is waste."""
    called = []

    async def _boom(*a, **k):
        called.append(a)
        return None

    monkeypatch.setattr(geo_resolver.google_places_client, "resolve_place_geo", _boom)
    ctx = asyncio.run(geo_resolver._resolve_uncached(
        "Sri Vijaya Puram", place_id="abc", latitude=11.62, longitude=92.72,
        address_hint="Andaman and Nicobar Islands, India", budget=None,
    ))
    assert ctx.country_code == "IN"
    assert ctx.source == "client"
    assert called == []


def test_resolver_degrades_to_the_static_table(monkeypatch):
    async def _none(*a, **k):
        return None

    monkeypatch.setattr(geo_resolver.google_places_client, "resolve_place_geo", _none)
    ctx = asyncio.run(geo_resolver._resolve_uncached(
        "Port Blair", place_id="", latitude=None, longitude=None,
        address_hint="", budget=None,
    ))
    assert ctx.country_code == "IN"
    assert ctx.source == "static"


def test_resolver_never_raises(monkeypatch):
    async def _explode(*a, **k):
        raise RuntimeError("Places is down")

    monkeypatch.setattr(geo_resolver.google_places_client, "resolve_place_geo", _explode)
    ctx = asyncio.run(geo_resolver.resolve_destination("Somewhere Unknown"))
    assert ctx.resolved is False
    assert ctx.source == "unresolved"


def test_unresolved_context_produces_no_prompt_block():
    ctx = DestinationContext(query="Nowhere", source="unresolved")
    assert ctx.resolved is False
    assert "DESTINATION IDENTITY" not in _prompt(ctx)


def test_renames_resolve_both_ways():
    assert geo_resolver.aliases_for("Port Blair") == {"sri vijaya puram"}
    assert geo_resolver.aliases_for("Sri Vijaya Puram") == {"port blair"}
    assert geo_resolver.aliases_for("Paris") == set()


# ── Lookup budget ───────────────────────────────────────────────────────────

def test_budget_is_a_hard_ceiling():
    b = GeoBudget(2)
    assert b.take() and b.take()
    assert b.take() is False
    assert b.spent == 2


def test_verify_place_refused_by_budget_reports_unchecked():
    """A starved check must read as "unknown", never as "wrong"."""
    check = asyncio.run(geo_resolver.verify_place(
        "Cellular Jail", near=_ctx(), budget=GeoBudget(0),
    ))
    assert check.checked is False
    assert check.ok is True


# ── Cross-language table contract ───────────────────────────────────────────

def test_andaman_places_are_known_to_the_country_table():
    """Powers the free drift scan, and must stay mirrored in the Dart copy."""
    for name in ("port blair", "sri vijaya puram", "andaman", "andaman islands"):
        assert trip_cost_floor.PLACE_COUNTRY[name] == "IN"


# ── Departure side: the "Nearby" sentinel ───────────────────────────────────
#
# Second client report: a traveller in Trincomalee was quoted MAA -> IXZ. The
# destination (IXZ) was right; the ORIGIN was invented. The app's reverse
# geocode had failed and sent the literal word "Nearby" as the departure city,
# and asked "which airports serve Nearby?", the model answered MAA rather than
# declining. Same shape as the Andaman bug, on the other endpoint.

from app.services.odyssey_ai_service import (  # noqa: E402
    _country_fallback_code,
    _is_non_place,
    generate_flight_strategies,
)


@pytest.mark.parametrize("token", [
    "Nearby", "nearby", "  NEARBY  ", "unknown", "current location",
    "my location", "n/a", "none", "-",
])
def test_sentinels_are_recognised_as_non_places(token):
    assert _is_non_place(token) is True


@pytest.mark.parametrize("place", ["Trincomalee", "Kandy", "Port Blair", "Paris"])
def test_real_places_are_not_mistaken_for_sentinels(place):
    assert _is_non_place(place) is False


def test_nearby_never_resolves_to_an_airport():
    """The exact regression: no api_key here, but the guard fires first."""
    assert asyncio.run(_resolve_airport_code("Nearby", "Nearby", "")) == ""


def test_nearby_with_a_known_country_falls_back_to_that_country():
    """A traveller somewhere in Sri Lanka departs CMB, not somewhere invented."""
    assert asyncio.run(_resolve_airport_code("Nearby", "Sri Lanka", "")) == "CMB"


def test_empty_departure_with_a_known_country_still_resolves():
    assert asyncio.run(_resolve_airport_code("", "Sri Lanka", "")) == "CMB"


def test_country_fallback_ignores_a_sentinel_country():
    assert _country_fallback_code("Nearby") == ""
    assert _country_fallback_code("") == ""
    assert _country_fallback_code("Sri Lanka") == "CMB"


def test_a_real_departure_city_still_wins_over_its_country():
    """The city's own airport, not the country's, where one is known."""
    assert asyncio.run(_resolve_airport_code("Trincomalee", "Sri Lanka", "")) == "CMB"
    assert asyncio.run(_resolve_airport_code("Pune", "India", "")) == "PNQ"


def test_flights_are_skipped_when_an_endpoint_cannot_be_resolved():
    """No Flights tab beats a confident flight from the wrong airport.

    Without a SerpApi key every flight comes from the Gemini estimation
    prompt, which always names *some* airport — so the route has to be
    settled before that prompt is ever reached.
    """
    result = asyncio.run(generate_flight_strategies(
        departure_city="Nearby", departure_country="Nearby",
        destination="Sri Vijaya Puram", days=8, budget=150000,
        currency="INR", travelers=3, api_key="", serpapi_key="",
    ))
    assert result == {}


def test_flights_survive_when_both_endpoints_resolve_statically():
    """The guard must not starve a route the static table already knows."""
    async def _run():
        # Same-airport pairs return {} for a different, pre-existing reason,
        # so use two genuinely distinct endpoints.
        from app.services.odyssey_ai_service import _resolve_airport_code as r
        return (await r("Trincomalee", "Sri Lanka", ""),
                await r("Sri Vijaya Puram", "India", ""))

    origin, dest = asyncio.run(_run())
    assert origin == "CMB" and dest == "IXZ"
    assert origin != dest  # a real, distinct route survives the guard
