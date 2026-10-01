"""Cities whose hotels Google lists without a price, and legs placed in the wrong spot.

Client report, 2026-10-01 (plan de5ce7c1, Luanda -> Kalandula -> Ndalatando):
"Stays show only one city stay." Google Hotels did list Pousada Calandula in
Kalandula and three hotels in Ndalatando, but with no `rate_per_night`: no
booking site sells those rooms online. The extractor dropped every unpriced
property, so both towns had no hotels, the day cards printed Luanda's rate
range as "hotel options in Kalandula", and the budget said the search "came
back empty". The same plan's route put Kalandula 220 km from the town.
"""
import asyncio
import copy

import pytest

from app.services import odyssey_ai_service as svc
from app.services.geo_resolver import DestinationContext
from app.services.odyssey_ai_service import (
    budget_basis,
    nightly_ranges,
    required_stay_cost,
    stay_basis_for_day,
    stay_cost_lines,
    stay_cost_row,
)
from app.services.serpapi_service import (
    extract_hotel_strategies_from_serpapi,
    property_has_rate,
)

# Captured at import, before conftest's `_leg_lookup_off` swaps it out per test.
REAL_LEG_GEO = svc._leg_geo

AIRPORT = {
    "name": "Dr. Antonio Agostinho Neto Angola International Airport",
    "transportations": [{"type": "Taxi", "duration": "2 hr 53 min"}],
}

# What Google returned for Kalandula and Ndalatando on 2026-11-11/12, trimmed.
POUSADA = {
    "type": "hotel", "name": "Pousada Calandula", "overall_rating": 4.1, "reviews": 195,
    "amenities": ["Breakfast", "Free Wi-Fi", "Pool"], "nearby_places": [AIRPORT],
}
TERMINUS = {
    "type": "hotel", "name": "Hotel Terminus Ndalatando", "overall_rating": 3.8, "reviews": 605,
    "amenities": ["Kid-friendly"], "nearby_places": [AIRPORT],
}
IU = {
    "type": "hotel", "name": "iu Hotel N'dalatando", "overall_rating": 3.7, "reviews": 58,
    "hotel_class": "3-star hotel", "extracted_hotel_class": 3, "nearby_places": [AIRPORT],
}


def _priced(name, nightly, hotel_class=3):
    return {
        "type": "hotel", "name": name, "overall_rating": 4.0, "reviews": 100,
        "hotel_class": f"{hotel_class}-star hotel", "extracted_hotel_class": hotel_class,
        "rate_per_night": {"lowest": f"${nightly}", "extracted_lowest": nightly},
        "nearby_places": [AIRPORT, {"name": "Ilha de Luanda"}],
    }


def _extract(properties, **kw):
    args = dict(
        destination="Kalandula", currency="USD", check_in_date="2026-11-11",
        check_out_date="2026-11-12", travelers=2, nights=1,
    )
    args.update(kw)
    return extract_hotel_strategies_from_serpapi({"properties": properties}, **args)


# ── The Stays tab ───────────────────────────────────────────────────────────

def test_rate_detection():
    assert not property_has_rate(POUSADA)
    assert property_has_rate(_priced("A", 50))
    assert property_has_rate({"rate_per_night": {"lowest": "$50"}})
    assert not property_has_rate({"rate_per_night": {"extracted_lowest": 0}})


def test_a_town_with_no_online_rates_still_shows_its_hotels():
    result = _extract([POUSADA])
    [card] = result["strategies"]
    assert card["name"] == "Pousada Calandula"
    assert card["rating"] == "4.1 ★" and card["reviews"] == 195
    # Empty, so the app hides the price and Est. Total and gives no tier badge.
    assert card["price_per_night"] == "" and card["total_estimated_cost"] == ""
    assert "contact the hotel" in card["description"]
    assert "excellent guest reviews" not in card["description"]
    assert card["booking_url"].startswith("https://www.google.com/search?q=Pousada+Calandula")


def test_tips_do_not_claim_live_rates_that_do_not_exist():
    tips = " ".join(_extract([POUSADA])["general_tips"])
    assert "live rates" not in tips
    assert "Est. Total" not in tips
    assert "Kalandula list no online rate for 2026-11-11 to 2026-11-12" in tips


def test_priced_hotels_come_first_and_unpriced_fill_the_rest():
    result = _extract(
        [TERMINUS, _priced("Cheap", 30), IU, _priced("Dear", 90)], destination="Ndalatando",
    )
    names = [s["name"] for s in result["strategies"]]
    assert names == ["Cheap", "Dear", "Hotel Terminus Ndalatando", "iu Hotel N'dalatando"]
    tips = " ".join(result["general_tips"])
    assert "live rates" in tips and "list no online rate" in tips


def test_four_priced_hotels_leave_no_room_for_unpriced_ones():
    result = _extract([POUSADA] + [_priced(f"H{i}", 40 + i) for i in range(5)])
    assert "Pousada Calandula" not in [s["name"] for s in result["strategies"]]


def test_the_location_line_never_names_the_airport():
    assert _extract([POUSADA])["strategies"][0]["location"] == "Kalandula"
    assert _extract([_priced("A", 50)])["strategies"][0]["location"] == "Ilha de Luanda"


# ── The search ladder ───────────────────────────────────────────────────────

def _run_ladder(monkeypatch, results_by_class):
    tried = []

    class _ScriptedSerp:
        def __init__(self, key):
            pass

        async def search_hotels(self, *, min_hotel_class=0, **kw):
            tried.append(min_hotel_class)
            return {"properties": copy.deepcopy(results_by_class.get(min_hotel_class, []))}

    async def _no_gemini(*a, **kw):
        raise AssertionError("an invented hotel was asked for while real ones were listed")

    monkeypatch.setattr(svc, "SerpApiService", _ScriptedSerp)
    monkeypatch.setattr(svc, "_call_gemini", _no_gemini)
    result = asyncio.run(svc.generate_hotel_strategies(
        destination="Ndalatando", days=2, budget=50_000, currency="LKR", travelers=2,
        hotel_check_in_date="2026-11-12", hotel_check_out_date="2026-11-13",
        api_key="", serpapi_key="k",
    ))
    return tried, [s["name"] for s in result.get("strategies", [])]


def test_an_unpriced_rung_widens_the_search_for_a_priced_one(monkeypatch):
    tried, names = _run_ladder(monkeypatch, {3: [IU], 0: [_priced("Guesthouse", 20, 0), TERMINUS]})
    assert tried == [3, 0]
    assert names[0] == "Guesthouse", "a priced room is what the budget needs"


def test_when_nothing_anywhere_is_priced_the_listed_hotels_are_kept(monkeypatch):
    tried, names = _run_ladder(monkeypatch, {3: [IU], 0: [IU, TERMINUS]})
    assert tried == [3, 0]
    assert names == ["iu Hotel N'dalatando"], "the first, higher-class rung's hotels"


def test_the_exact_kalandula_search(monkeypatch):
    tried, names = _run_ladder(monkeypatch, {0: [POUSADA]})
    assert tried == [3, 0]
    assert names == ["Pousada Calandula"]


def test_unpriced_classed_hotels_cannot_crowd_out_priced_guesthouses():
    """`_prefer_classed` drops unclassed properties only when enough classed
    ones carry a price."""
    unpriced_classed = [dict(IU, name=f"Classed {i}") for i in range(3)]
    result = svc._prefer_classed(
        {"properties": unpriced_classed + [_priced("Guesthouse", 20, 0)]}, "Ndalatando",
    )
    assert "Guesthouse" in [p["name"] for p in result["properties"]]


# ── Day cards and the budget ───────────────────────────────────────────────

LEGS = [
    {"city": "Luanda", "start_day": 1, "end_day": 2, "nights": 2},
    {"city": "Kalandula", "start_day": 3, "end_day": 3, "nights": 1},
    {"city": "Ndalatando", "start_day": 4, "end_day": 4, "nights": 1},
    {"city": "Luanda", "start_day": 5, "end_day": 5, "nights": 0},
]


def _stays():
    return {"strategies": [
        {"name": "FAIAS", "price_per_night": "INR 7,750", "hotel_class": 4, "leg_index": 0, "city": "Luanda"},
        {"name": "Skyna", "price_per_night": "INR 17,418", "hotel_class": 4, "leg_index": 0, "city": "Luanda"},
        {"name": "Pousada Calandula", "price_per_night": "", "hotel_class": 0, "leg_index": 1, "city": "Kalandula"},
    ]}


def test_the_kalandula_day_says_its_range_is_borrowed():
    trip, by_leg = nightly_ranges(_stays(), "INR")
    assert 1 not in by_leg, "an unpriced hotel must not make a range"
    rng, city, borrowed = stay_basis_for_day(3, LEGS, by_leg, trip)
    assert (rng, city, borrowed) == ("INR 7,750 - 17,418", "Kalandula", True)
    cost, basis = stay_cost_row(rng, city, borrowed)
    assert cost == "INR 7,750 - 17,418 / night"
    assert basis == (
        "No online hotel rates in Kalandula; range from the trip's other cities: "
        "INR 7,750 - 17,418."
    )
    assert "hotel options in Kalandula" not in basis


def test_the_luanda_day_is_unchanged():
    trip, by_leg = nightly_ranges(_stays(), "INR")
    rng, city, borrowed = stay_basis_for_day(1, LEGS, by_leg, trip)
    assert not borrowed
    assert stay_cost_row(rng, city, borrowed)[1] == (
        "Nightly rate range across hotel options in Luanda: INR 7,750 - 17,418."
    )


def test_the_last_day_back_in_luanda_uses_luanda_s_own_rates():
    """Day 5 sits on a 0-night Luanda leg nobody searched; Luanda has rates."""
    trip, by_leg = nightly_ranges(_stays(), "INR")
    assert stay_basis_for_day(5, LEGS, by_leg, trip) == ("INR 7,750 - 17,418", "Luanda", False)


def test_the_class_tip_names_its_city():
    """Tips from every leg land in one list on the Stays tab."""
    tips = _extract([_priced("A", 50, 4)], destination="Luanda")["general_tips"]
    assert "Every hotel in Luanda here is 4-star class or above." in tips


def test_an_unpriced_hotel_never_becomes_a_zero_cost_room():
    lines = {ln["city"]: ln for ln in stay_cost_lines(_stays(), LEGS, 2, "minimum")}
    assert lines["Kalandula"]["nightly"] == 7750, "priced from the trip's other rooms"
    assert lines["Kalandula"]["basis"] == "pooled"
    assert lines["Kalandula"]["unpriced"] == 1
    assert lines["Ndalatando"]["unpriced"] == 0
    assert required_stay_cost(_stays(), LEGS, 2) == 7750 * 2 * 2 + 7750 * 2 + 7750 * 2


def _caveat(stays):
    breakdown = {"stay": 1.0, "transit": 0.0, "food": 1.0, "activities": 1.0, "total": 3.0}
    block = budget_basis(
        tier="minimum", breakdown=breakdown, flight_strategies={}, hotel_strategies=stays,
        city_legs=LEGS, travelers=2, days=5, currency="INR", food_share=0.5,
        no_airfare=True, at_star_floor=False,
    )
    return block["stay"]["caveat"]


def test_the_budget_names_each_town_and_why():
    assert _caveat(_stays()) == (
        "Hotels in Kalandula list no online price and the hotel search for "
        "Ndalatando came back empty, so those nights are priced from the rest "
        "of the trip's rooms."
    )


def test_two_unpriced_towns_are_named_together():
    stays = _stays()
    stays["strategies"].append(
        {"name": "Hotel Terminus", "price_per_night": "", "leg_index": 2, "city": "Ndalatando"},
    )
    assert _caveat(stays).startswith("Hotels in Kalandula and Ndalatando list no online price, so")


# ── Where the legs are ──────────────────────────────────────────────────────

ANGOLA = DestinationContext(
    query="Angola", name="Angola", country="Angola", country_code="AO",
    latitude=-11.2, longitude=17.87, types=("country",), source="places",
)
KALANDULA = {"latitude": -9.0782, "longitude": 16.0018, "country_code": "AO", "types": ["locality"]}


@pytest.fixture
def places(monkeypatch):
    """Real `_leg_geo`, scripted Places, in-memory cache."""
    calls, cache = [], {}

    async def _get(key):
        return cache.get(key)

    async def _set(key, value, ttl=None):
        cache[key] = value

    answers = {}

    async def _resolve(query, bias_lat=None, bias_lng=None, **kw):
        calls.append((query, bias_lat, bias_lng))
        return answers.get(query)

    monkeypatch.setattr(svc, "_leg_geo", REAL_LEG_GEO)
    monkeypatch.setattr(svc.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(svc.place_cache_service, "set_raw", _set)
    monkeypatch.setattr(svc.google_places_client, "resolve_place_geo", _resolve)
    return calls, answers


def _legs(lat, lng, city="Kalandula"):
    return [{"city": city, "latitude": lat, "longitude": lng}]


def test_a_leg_220_km_off_is_moved_to_the_town(places):
    calls, answers = places
    answers["Kalandula, Angola"] = KALANDULA
    legs = _legs(-7.25, 15.01)
    moved = asyncio.run(svc._locate_legs(legs, ANGOLA))
    assert legs[0]["latitude"] == -9.0782 and legs[0]["longitude"] == 16.0018
    assert moved and moved[0].startswith("Kalandula 2")
    assert calls == [("Kalandula, Angola", -7.25, 15.01)], "biased to the planner's point"


def test_a_leg_close_enough_is_left_alone(places):
    _, answers = places
    answers["Kalandula, Angola"] = KALANDULA
    legs = _legs(-9.10, 16.10)  # ~11 km away
    assert asyncio.run(svc._locate_legs(legs, ANGOLA)) == []
    assert legs[0]["latitude"] == -9.10


def test_a_leg_with_no_coordinates_gets_google_s(places):
    _, answers = places
    answers["Kalandula, Angola"] = KALANDULA
    legs = [{"city": "Kalandula"}]
    asyncio.run(svc._locate_legs(legs, ANGOLA))
    assert legs[0]["latitude"] == -9.0782


@pytest.mark.parametrize("answer", [
    dict(KALANDULA, country_code="CD"),          # a namesake across the border
    dict(KALANDULA, types=["country", "political"]),  # Google did not know the town
    dict(KALANDULA, types=["administrative_area_level_1"]),
    None,
])
def test_an_answer_that_is_not_the_town_moves_nothing(places, answer):
    _, answers = places
    answers["Kalandula, Angola"] = answer
    legs = _legs(-7.25, 15.01)
    assert asyncio.run(svc._locate_legs(legs, ANGOLA)) == []
    assert legs[0]["latitude"] == -7.25


def test_a_repeat_lookup_is_served_from_the_cache(places):
    calls, answers = places
    answers["Kalandula, Angola"] = KALANDULA
    for _ in range(2):
        asyncio.run(svc._locate_legs(_legs(-7.25, 15.01), ANGOLA))
    assert len(calls) == 1


def test_lookups_leave_room_for_the_airports(places):
    calls, answers = places
    budget = svc.geo_resolver.GeoBudget(limit=3)
    legs = [{"city": c, "latitude": 0.0, "longitude": 0.0} for c in ("A", "B", "C")]
    asyncio.run(svc._locate_legs(legs, ANGOLA, budget, reserve=2))
    assert len(calls) == 1 and budget.left == 2


def test_the_route_is_checked_against_the_corrected_coordinates(monkeypatch, places):
    """The fix lands before `_validate_route`, so hop checks see the real town."""
    _, answers = places
    answers["Kalandula, Angola"] = KALANDULA
    route = {
        "legs": [
            {"city": "Luanda", "start_day": 1, "end_day": 2, "latitude": -8.8383,
             "longitude": 13.2344, "arrive_by": "flight"},
            {"city": "Kalandula", "start_day": 3, "end_day": 3, "latitude": -7.25,
             "longitude": 15.01, "arrive_by": "car"},
        ],
    }

    async def _fake(prompt, api_key, **kw):
        import json
        return json.dumps(route), []

    monkeypatch.setattr(svc, "_call_gemini", _fake)
    plan = asyncio.run(svc.plan_route(
        destination="Angola", days=3, mood="Adventurous", travelers=2, api_key="k",
        start_date="2026-11-09", geo=ANGOLA, include_flights=False,
    ))
    kalandula = plan.legs[1]
    assert (kalandula["latitude"], kalandula["longitude"]) == (-9.0782, 16.0018)


# ── A town's hotels must be in the town ─────────────────────────────────────

ROSKILDE = (55.6415, 12.0803)


def _at(prop, lat, lng):
    return dict(prop, gps_coordinates={"latitude": lat, "longitude": lng})


GLOSTRUP = _at(_priced("Glostrup Park Hotel", 194, 4), 55.6640, 12.4020)  # ~20 km
IN_ROSKILDE = _at(_priced("Hotel Prindsen", 150, 3), 55.6420, 12.0810)
IN_ROSKILDE_UNPRICED = _at(dict(POUSADA, name="Roskilde Guesthouse"), 55.6430, 12.0790)


def _run_near(monkeypatch, results_by_class):
    tried = []

    class _ScriptedSerp:
        def __init__(self, key):
            pass

        async def search_hotels(self, *, min_hotel_class=0, **kw):
            tried.append(min_hotel_class)
            return {"properties": copy.deepcopy(results_by_class.get(min_hotel_class, []))}

    monkeypatch.setattr(svc, "SerpApiService", _ScriptedSerp)
    result = asyncio.run(svc.generate_hotel_strategies(
        destination="Roskilde", days=2, budget=20_000, currency="USD", travelers=1,
        hotel_check_in_date="2026-11-18", hotel_check_out_date="2026-11-19",
        api_key="", serpapi_key="k", latitude=ROSKILDE[0], longitude=ROSKILDE[1],
    ))
    return tried, [s["name"] for s in result.get("strategies", [])]


def test_suburban_four_stars_send_the_search_to_the_town_s_own_hotels(monkeypatch):
    tried, names = _run_near(monkeypatch, {4: [GLOSTRUP], 0: [IN_ROSKILDE]})
    assert tried == [4, 0]
    assert names == ["Hotel Prindsen"]


def test_with_nothing_in_town_the_suburban_hotels_are_still_shown(monkeypatch):
    tried, names = _run_near(monkeypatch, {4: [GLOSTRUP]})
    assert tried == [4, 0]
    assert names == ["Glostrup Park Hotel"]


def test_the_town_s_own_unpriced_hotel_beats_a_priced_one_out_of_town(monkeypatch):
    _, names = _run_near(monkeypatch, {4: [GLOSTRUP], 0: [IN_ROSKILDE_UNPRICED]})
    assert names == ["Roskilde Guesthouse"]


def test_one_hotel_in_town_is_enough_to_keep_the_rung(monkeypatch):
    """A big city's list mixes centre and suburbs; that is not a wrong town."""
    tried, names = _run_near(monkeypatch, {4: [GLOSTRUP, _at(_priced("Centre", 160, 4), *ROSKILDE)]})
    assert tried == [4]
    assert set(names) == {"Glostrup Park Hotel", "Centre"}


def test_a_hotel_without_coordinates_is_not_evidence_of_the_wrong_town():
    assert svc._any_hotel_near([_priced("No GPS", 100)], *ROSKILDE)
    assert svc._any_hotel_near([GLOSTRUP], None, None)
    assert not svc._any_hotel_near([GLOSTRUP], *ROSKILDE)


# ── Ride-app buttons and long drives ────────────────────────────────────────

ANGOLA_LEGS = [
    {"city": "Luanda", "start_day": 1, "end_day": 2, "latitude": -8.8383, "longitude": 13.2344},
    {"city": "Kalandula", "start_day": 3, "end_day": 3, "latitude": -9.0901, "longitude": 15.9553},
    {"city": "Ndalatando", "start_day": 4, "end_day": 4, "latitude": -9.2978, "longitude": 14.9116},
    {"city": "Luanda", "start_day": 5, "end_day": 5, "latitude": -8.8383, "longitude": 13.2344},
]
NBJ = {"iata": "NBJ", "city": "Luanda", "latitude": -9.048, "longitude": 13.50}


def _day(n, *names):
    return {"kind": "day", "day": n, "activities": [
        {"name": nm, "type": "transport"} for nm in names
    ]}


def _km(days, day_no):
    [day] = [d for d in days if d["day"] == day_no]
    return {a["name"]: a.get("intercity_km") for a in day["activities"]}


def test_the_angola_drives_from_the_test_run():
    days = [
        _day(1, "Arrival at Luanda International Airport (NBJ)", "Transfer to Luanda"),
        _day(2),
        _day(3, "Car Transfer to Kalandula"),
        _day(4, "Car Transfer to Ndalatando via Pedras Negras"),
        _day(5, "Car Transfer to Luanda", "Transfer to Luanda Airport (NBJ)"),
    ]
    marked = svc._mark_long_drives(days, ANGOLA_LEGS, arrival=NBJ, departure=NBJ)
    assert 290 < _km(days, 3)["Car Transfer to Kalandula"] < 320
    assert _km(days, 4)["Car Transfer to Ndalatando via Pedras Negras"] is None, "~115 km keeps its buttons"
    assert 180 < _km(days, 5)["Car Transfer to Luanda"] < 200
    assert _km(days, 5)["Transfer to Luanda Airport (NBJ)"] is None, "the airport is ~40 km out"
    assert _km(days, 1) == {
        "Arrival at Luanda International Airport (NBJ)": None, "Transfer to Luanda": None,
    }
    assert marked == 2


def test_a_long_drive_to_the_airport_on_the_last_day():
    legs = [ANGOLA_LEGS[0] | {"end_day": 3}, ANGOLA_LEGS[1] | {"start_day": 4, "end_day": 5}]
    days = [_day(1), _day(4), _day(5, "Transfer: Kalandula → Luanda airport", "Taxi to the falls")]
    svc._mark_long_drives(days, legs, arrival=NBJ, departure=NBJ)
    assert _km(days, 5)["Transfer: Kalandula → Luanda airport"] > 150
    assert _km(days, 5)["Taxi to the falls"] is None


def test_colombo_to_kandy_keeps_its_buttons():
    """~95 km: PickMe and Uber run out-of-town rides there."""
    legs = [
        {"city": "Colombo", "start_day": 1, "end_day": 2, "latitude": 6.9271, "longitude": 79.8612},
        {"city": "Kandy", "start_day": 3, "end_day": 4, "latitude": 7.2906, "longitude": 80.6337},
    ]
    days = [_day(1), _day(2), _day(3, "Travel: Colombo → Kandy"), _day(4)]
    assert svc._mark_long_drives(days, legs) == 0


def test_an_unnamed_drive_is_marked_only_when_it_is_the_day_s_one_ride():
    days = [_day(1), _day(2), _day(3, "Scenic drive north"), _day(4), _day(5)]
    svc._mark_long_drives(days, ANGOLA_LEGS)
    assert _km(days, 3)["Scenic drive north"] > 150

    days = [_day(1), _day(2), _day(3, "Scenic drive north", "Taxi to dinner"), _day(4), _day(5)]
    svc._mark_long_drives(days, ANGOLA_LEGS)
    assert _km(days, 3) == {"Scenic drive north": None, "Taxi to dinner": None}


def test_an_airport_code_only_matches_as_a_word():
    far = {"iata": "LAD", "latitude": -9.09, "longitude": 15.95}  # placed far on purpose
    legs = [ANGOLA_LEGS[0] | {"end_day": 2}]
    days = [_day(1, "Shuttle to the salad bar"), _day(2)]
    svc._mark_long_drives(days, legs, arrival=far)
    assert _km(days, 1)["Shuttle to the salad bar"] is None
