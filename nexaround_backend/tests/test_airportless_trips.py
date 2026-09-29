"""Countries with no airport, and trips that must be flown into.

Client report (2026-09-27): a Dubai ("Jabal Ali 3") -> Andorra plan searched no
flights, because the planner's Barcelona was rejected as "not in Andorra", and
Day 1 then opened with "Travel from Jabal Ali 3 to Andorra la Vella" — a bus
from Dubai. Andorra has no airport: the trip flies into a neighbour and takes
the coach. And a trip abroad never opens with an overland journey from home.
No network: the airport table is the bundled file, everything else is stubbed.
"""
import asyncio
import json

import pytest

from app.services import airports_service
from app.services import odyssey_ai_service as svc
from app.services.geo_resolver import DestinationContext
from app.services.odyssey_ai_service import RoutePlan, plan_route


def _andorra():
    return DestinationContext(
        query="Andorra", name="Andorra", country="Andorra", country_code="AD",
        latitude=42.5063, longitude=1.5218, types=("country",), source="places",
    )


def _india():
    return DestinationContext(
        query="India", name="India", country="India", country_code="IN",
        latitude=20.5937, longitude=78.9629, types=("country",), source="places",
    )


ANDORRA_LEGS = [
    {"city": "Andorra la Vella", "country": "AD", "start_day": 1, "end_day": 3,
     "latitude": 42.51, "longitude": 1.52, "arrive_by": "car", "from_previous_km": 200},
    {"city": "Encamp", "country": "AD", "start_day": 4, "end_day": 6,
     "latitude": 42.53, "longitude": 1.58, "arrive_by": "car", "from_previous_km": 10},
    {"city": "Santa Coloma", "country": "AD", "start_day": 7, "end_day": 9,
     "latitude": 42.50, "longitude": 1.50, "arrive_by": "car", "from_previous_km": 15},
]


def _route(arrival, departure=None):
    return {
        "region": "Andorra", "legs": ANDORRA_LEGS,
        "arrival_airport": arrival, "departure_airport": departure or arrival,
    }


# ── The airport table ────────────────────────────────────────────────────────

def test_microstates_have_no_airport_and_real_countries_do():
    for code in ("AD", "LI", "MC", "SM", "VA"):
        assert airports_service.has_scheduled_airport(code) is False, code
    for code in ("IN", "AE", "LK", "ES", "FR"):
        assert airports_service.has_scheduled_airport(code) is True, code
    # Only a real country may be declared airportless.
    assert airports_service.has_scheduled_airport("XX") is True
    assert airports_service.has_scheduled_airport("") is True


def test_nearest_large_airports_not_the_nearest_strip():
    """La Seu d'Urgell (LEU) is 21 km from Andorra la Vella and hardly flown."""
    codes = [a.iata for a, _ in airports_service.nearest(42.5078, 1.5211)]
    assert codes == ["GRO", "TLS", "BCN"]
    dubai = [a.iata for a, _ in airports_service.nearest(24.99, 55.07)]
    assert dubai[:2] == ["DWC", "DXB"]
    assert airports_service.nearest(-45.0, -130.0) == []    # South Pacific
    assert airports_service.nearest(None, 1.0) == []


def test_airport_lookup():
    bcn = airports_service.get("bcn")
    assert (bcn.city, bcn.country, bcn.large) == ("Barcelona", "ES", True)
    assert airports_service.get("DWC").city == "Dubai"       # "Dubai(Jebel Ali)" cleaned
    assert airports_service.get("XXX") is None


def test_known_airport_codes_is_all_or_nothing():
    assert svc.known_airport_codes("dwc, DXB") == "DWC,DXB"
    assert svc.known_airport_codes("DWC,XXX") == ""
    assert svc.known_airport_codes("") == ""
    assert svc.known_airport_codes("DXB,DWC,SHJ,AUH,RKT") == ""  # too many


# ── The route planner ────────────────────────────────────────────────────────

def _script(monkeypatch, *responses):
    calls = []

    async def _fake(prompt, api_key, **kw):
        calls.append(prompt)
        return json.dumps(responses[min(len(calls) - 1, len(responses) - 1)]), []

    monkeypatch.setattr(svc, "_call_gemini", _fake)
    return calls


@pytest.fixture
def no_places(monkeypatch):
    """A cross-border gateway is located from the airport table, never Places."""
    async def _boom(*a, **kw):
        raise AssertionError("Places must not be asked about a neighbour's airport")
    monkeypatch.setattr(svc, "_airport_geo", _boom)

    async def _no_resolver(*a, **kw):
        raise AssertionError("the in-country resolver cannot answer for Andorra")
    monkeypatch.setattr(svc, "_resolve_airport_code", _no_resolver)


def _plan(**kw):
    args = dict(
        destination="Andorra", days=9, mood="Adventurous", travelers=2, api_key="k",
        start_date="2026-10-13", geo=_andorra(), departure_city="Jabal Ali 3",
        departure_country="", include_flights=True,
    )
    args.update(kw)
    return asyncio.run(plan_route(**args))


def test_barcelona_is_accepted_for_andorra(monkeypatch, no_places):
    """The exact answer the planner gave on 2026-09-27, and the code refused."""
    _script(monkeypatch, _route({"iata": "BCN", "city": "Barcelona", "name": "El Prat"}))
    plan = _plan()
    assert plan.reasons == []
    # The planner's own pick is searched first, on its own.
    assert plan.arrival_code == "BCN" and plan.departure_code == "BCN"
    assert plan.arrival["latitude"] == pytest.approx(41.2971)
    assert [leg["country"] for leg in plan.legs] == ["AD", "AD", "AD"]


def test_a_gateway_with_no_flights_falls_back_to_the_nearest_neighbours(monkeypatch, no_places):
    # "AND" is not an airport anyone flies to; the planner says it twice.
    _script(monkeypatch, _route({"iata": "AND", "city": "Andorra la Vella"}))
    plan = _plan()
    assert any("no scheduled flights" in r for r in plan.reasons)
    assert plan.arrival_code == "GRO,TLS,BCN"
    assert plan.departure_code == "GRO,TLS,BCN"


def test_the_route_prompt_sends_andorra_next_door_and_keeps_india_home(monkeypatch):
    andorra = svc._route_prompt(
        destination="Andorra", days=9, mood="x", travelers=2, geo=_andorra(), origin_line="",
    )
    assert "Andorra has no airport with scheduled flights" in andorra
    assert "GRO (Girona), TLS (Toulouse), BCN (Barcelona)" in andorra
    assert "Both airports MUST be in Andorra" not in andorra
    india = svc._route_prompt(
        destination="India", days=9, mood="x", travelers=2, geo=_india(), origin_line="",
    )
    assert "Both airports MUST be in India" in india


# ── The flight search ────────────────────────────────────────────────────────

class _RecordingSerp:
    searches = []

    def __init__(self, key, **kw):
        pass

    async def search_flights(self, **kw):
        _RecordingSerp.searches.append(kw)
        return {"_serpapi_status": "no_results"}

    async def search_flights_return(self, **kw):
        return {"_serpapi_status": "no_results"}


def _flights(**kw):
    _RecordingSerp.searches = []
    args = dict(
        departure_city="Dubai", departure_country="United Arab Emirates",
        destination="Andorra", days=9, budget=256000, currency="INR", travelers=2,
        flight_start_date="2026-10-13", flight_end_date="2026-10-21",
        api_key="", serpapi_key="k", destination_geo=_andorra(), route_plan=None,
    )
    args.update(kw)
    return asyncio.run(svc.generate_flight_strategies(**args))


def test_andorra_without_a_route_is_searched_into_its_neighbours(monkeypatch):
    monkeypatch.setattr(svc, "SerpApiService", _RecordingSerp)
    result = _flights()
    assert result.get("unavailable_reason") != "no_airport"
    assert _RecordingSerp.searches, "no flight was searched"
    assert _RecordingSerp.searches[0]["destination"] == "GRO,TLS,BCN"


def test_the_travellers_chosen_airport_is_the_origin(monkeypatch):
    monkeypatch.setattr(svc, "SerpApiService", _RecordingSerp)

    async def _no_resolver(*a, **kw):
        raise AssertionError("a chosen airport needs no lookup")
    monkeypatch.setattr(svc, "_resolve_airport_code", _no_resolver)
    _flights(departure_city="Jabal Ali 3", departure_airport="DWC,DXB")
    assert _RecordingSerp.searches[0]["departure_city"] == "DWC,DXB"


# ── Is the trip abroad? ──────────────────────────────────────────────────────

def _abroad(**kw):
    args = dict(
        departure_country="", departure_latitude=None, departure_longitude=None,
        origin_codes="", geo=_andorra(), first_leg=ANDORRA_LEGS[0],
    )
    args.update(kw)
    return svc._trip_is_abroad(**args)


def test_dubai_to_andorra_is_abroad():
    assert _abroad(origin_codes="DWC,DXB") is True
    assert _abroad(departure_latitude=24.99, departure_longitude=55.07) is True


def test_kinniya_to_colombo_is_not():
    sri_lanka = DestinationContext(
        query="Colombo", name="Colombo", country="Sri Lanka", country_code="LK",
        latitude=6.93, longitude=79.86, source="places",
    )
    leg = {"city": "Colombo", "latitude": 6.93, "longitude": 79.86}
    assert _abroad(origin_codes="CMB", geo=sri_lanka, first_leg=leg) is False
    assert _abroad(departure_country="Sri Lanka", geo=sri_lanka, first_leg=leg) is False


def test_a_short_hop_across_a_border_stays_overland():
    """Singapore to Johor Bahru is a bus ride, not a flight."""
    malaysia = DestinationContext(
        query="Johor Bahru", name="Johor Bahru", country="Malaysia", country_code="MY",
        latitude=1.49, longitude=103.74, source="places",
    )
    leg = {"city": "Johor Bahru", "latitude": 1.49, "longitude": 103.74}
    assert _abroad(origin_codes="SIN", geo=malaysia, first_leg=leg) is False


def test_unknown_home_keeps_the_old_behaviour():
    assert _abroad() is False


# ── The itinerary prompt ────────────────────────────────────────────────────

BCN = {"iata": "BCN", "city": "Barcelona", "name": "Josep Tarradellas Barcelona-El Prat Airport",
       "latitude": 41.2971, "longitude": 2.0785}
BUS = {"mode": "bus", "duration_min": 270, "distance_km": 206, "fare": "€33.00",
       "lines": ["Andbus"], "source": "Google Maps"}


def _prompt(**kw):
    args = dict(
        travelers=2, departure_city="Jabal Ali 3", departure_country="",
        legs=ANDORRA_LEGS, geo=_andorra(),
    )
    args.update(kw)
    return svc._build_prompt("Andorra", "Adventurous", 256000, 9, "INR", **args)


def test_abroad_without_a_fare_opens_at_the_airport_not_at_home():
    prompt = _prompt(abroad=True, gateway_in=BCN, gateway_out=BCN, arrival_ground=BUS,
                     departure_ground=BUS)
    assert "ARRIVING FROM ABROAD" in prompt
    assert '"Arrival at Josep Tarradellas Barcelona-El Prat Airport (BCN)"' in prompt
    assert '"Transfer: Barcelona airport → Andorra la Vella"' in prompt
    assert "bus (Andbus), about 4 h 30 min" in prompt
    assert '"Transfer: Santa Coloma → Barcelona airport"' in prompt
    assert '"Departure from Josep Tarradellas Barcelona-El Prat Airport (BCN)"' in prompt
    # The reported line cannot be asked for any more.
    assert 'named something like "Travel from Jabal Ali 3' not in prompt
    assert "GETTING TO ANDORRA LA VELLA" not in prompt


def test_abroad_with_no_known_airport_still_never_goes_overland():
    prompt = _prompt(abroad=True)
    assert '"Arrive in Andorra la Vella"' in prompt
    assert '"Depart from Santa Coloma"' in prompt
    assert "NEVER write an overland journey from Jabal Ali 3" in prompt


def test_a_trip_that_is_not_abroad_keeps_the_ground_journey():
    prompt = _prompt(abroad=False)
    assert "GETTING TO ANDORRA LA VELLA" in prompt
    assert "ARRIVING FROM ABROAD" not in prompt


def _flight_route():
    return RoutePlan(legs=ANDORRA_LEGS, arrival=BCN, departure=BCN,
                     arrival_code="BCN", departure_code="BCN", source="planner")


FLIGHT = {"title": "Dubai to Barcelona", "route": "DXB → BCN", "trip_type": "round_trip",
          "price_per_traveler": 52000, "currency": "INR"}


def test_a_booked_flight_transfer_uses_googles_mode():
    prompt = _prompt(confirmed_flight=FLIGHT, route_plan=_flight_route(),
                     arrival_ground=BUS, departure_ground=BUS)
    assert '"Transfer: Barcelona airport → Andorra la Vella"' in prompt
    assert "that travels by bus (Andbus), about 4 h 30 min" in prompt
    assert "ARRIVING FROM ABROAD" not in prompt


def test_without_google_the_transfer_follows_the_clients_order():
    prompt = _prompt(confirmed_flight=FLIGHT, route_plan=_flight_route())
    assert "a train if one runs, else a bus or coach, else a car or taxi" in prompt
    assert "Transfer: Barcelona airport → Andorra la Vella\" that states the mode" in prompt


# ── "Travelling from": the nearest airports ─────────────────────────────────

def test_nearest_airports_lead_with_what_the_flight_search_uses(monkeypatch):
    """From Kinniya the nearest large airport is Jaffna, but trips fly from CMB."""
    from app.api.v1 import itineraries

    class _Settings:
        def __init__(self, db):
            pass

        async def get_setting(self, name):
            return "key"

    async def _resolve(place, country, api_key, **kw):
        assert place == "Kinniya" and kw["latitude"] == 8.49
        return "CMB"

    monkeypatch.setattr(itineraries, "SettingsService", _Settings)
    monkeypatch.setattr(svc, "_resolve_airport_code", _resolve)
    result = asyncio.run(itineraries.get_odyssey_nearest_airports(
        lat=8.49, lng=81.18, place="Kinniya", country="", db=None, current_user=None,
    ))
    assert result.suggested == "CMB"
    codes = [a.iata for a in result.airports]
    assert codes[0] == "CMB" and "JAF" in codes
    assert result.airports[0].country == "Sri Lanka"
    assert result.airports[0].distance_km == 204


def test_nearest_airports_fall_back_to_distance(monkeypatch):
    from app.api.v1 import itineraries

    class _Settings:
        def __init__(self, db):
            pass

        async def get_setting(self, name):
            return ""

    async def _resolve(*a, **kw):
        return ""

    monkeypatch.setattr(itineraries, "SettingsService", _Settings)
    monkeypatch.setattr(svc, "_resolve_airport_code", _resolve)
    result = asyncio.run(itineraries.get_odyssey_nearest_airports(
        lat=24.99, lng=55.07, place="", country="", db=None, current_user=None,
    ))
    assert result.suggested == "DWC"
    assert [a.iata for a in result.airports][:2] == ["DWC", "DXB"]


def _san_marino():
    return DestinationContext(
        query="San Marino", name="San Marino", country="San Marino", country_code="SM",
        latitude=43.94, longitude=12.45, types=("country",), source="places",
    )


def _san_marino_route():
    leg = {"city": "San Marino", "country": "SM", "start_day": 1, "end_day": 4,
           "latitude": 43.94, "longitude": 12.45, "arrive_by": "car", "from_previous_km": 25}
    rimini = {"iata": "RMI", "city": "Rimini"}
    return RoutePlan(legs=[leg], arrival=dict(rimini), departure=dict(rimini),
                     arrival_code="RMI", departure_code="RMI", source="planner")


def test_neighbours_are_searched_only_when_the_planned_airport_has_no_flight():
    """New York -> San Marino: Rimini had no route; Florence did."""
    route = _san_marino_route()
    searched = []

    async def search():
        searched.append(route.arrival_code)
        if route.arrival_code == "RMI":
            return {"strategies": [], "unavailable_reason": "none_found"}
        return {"strategies": [{"title": "via FLR"}]}

    result = asyncio.run(svc._flights_with_neighbours(search, route, _san_marino()))
    assert result["strategies"]
    assert searched[0] == "RMI"
    assert searched[1].split(",")[0] == "RMI" and len(searched[1].split(",")) > 1
    assert route.departure_code == route.arrival_code


def test_a_planned_airport_with_flights_is_kept():
    """Monaco flew into Genoa when every neighbour was searched up front."""
    route = _san_marino_route()
    searched = []

    async def search():
        searched.append(route.arrival_code)
        return {"strategies": [{"title": "via RMI"}]}

    asyncio.run(svc._flights_with_neighbours(search, route, _san_marino()))
    assert searched == ["RMI"]


def test_neighbours_only_for_countries_without_an_airport():
    india_route = RoutePlan(
        legs=[{"city": "Nagpur", "latitude": 21.15, "longitude": 79.09,
               "start_day": 1, "end_day": 4}],
        arrival={"iata": "NAG"}, departure={"iata": "NAG"},
        arrival_code="NAG", departure_code="NAG",
    )
    searched = []

    async def search():
        searched.append(india_route.arrival_code)
        return {"strategies": [], "unavailable_reason": "none_found"}

    asyncio.run(svc._flights_with_neighbours(search, india_route, _india()))
    assert searched == ["NAG"]


def test_india_keeps_its_own_airports_only(monkeypatch):
    """The widening is for countries with no airport; India's search is unchanged."""
    async def _geo(code, geo, budget=None, city=""):
        return {"NAG": {"latitude": 21.09, "longitude": 79.05, "country_code": "IN", "name": "Nagpur"}}.get(code)
    monkeypatch.setattr(svc, "_airport_geo", _geo)
    route = {
        "region": "Nagpur",
        "legs": [{"city": "Nagpur", "country": "IN", "start_day": 1, "end_day": 4,
                  "latitude": 21.15, "longitude": 79.09, "arrive_by": "none", "from_previous_km": 0}],
        "arrival_airport": {"iata": "NAG", "city": "Nagpur"},
        "departure_airport": {"iata": "NAG", "city": "Nagpur"},
    }
    _script(monkeypatch, route)
    plan = _plan(destination="India", days=4, geo=_india(), departure_city="Colombo",
                 departure_country="Sri Lanka")
    assert plan.arrival_code == "NAG"


def test_a_junk_code_from_the_airport_lookup_is_dropped(monkeypatch):
    """Jebel Ali came back "DWC,HBH" once; HBH (Alaska) sank the flight search."""
    svc._airport_code_cache.clear()

    async def _fake(prompt, api_key, **kw):
        return "DWC, HBH", []

    monkeypatch.setattr(svc, "_call_gemini", _fake)
    code = asyncio.run(svc._resolve_airport_code("Jabal Ali 3", "", "key"))
    # HBH dropped; DWC then searched with the rest of Dubai.
    assert code == "DWC,DXB"
    svc._airport_code_cache.clear()


def test_an_unknown_answer_alone_is_still_kept(monkeypatch):
    """Only filtered when a real airport remains: a small field missing from the
    table must not turn into "no airport at all"."""
    svc._airport_code_cache.clear()

    async def _fake(prompt, api_key, **kw):
        return "ZZQ", []

    monkeypatch.setattr(svc, "_call_gemini", _fake)
    assert asyncio.run(svc._resolve_airport_code("Somewhere Small", "", "key")) == "ZZQ"
    svc._airport_code_cache.clear()


def test_a_single_home_airport_is_searched_with_its_city_neighbours():
    """DWC alone found no fare to Barcelona; Dubai (all airports) does."""
    assert svc.with_city_airports("DWC") == "DWC,DXB"
    assert svc.with_city_airports("JFK").split(",")[0] == "JFK"
    assert set(svc.with_city_airports("JFK").split(",")) == {"JFK", "LGA", "EWR"}
    assert svc.with_city_airports("BCN") == "BCN"          # no second big airport
    assert svc.with_city_airports("DWC,DXB") == "DWC,DXB"  # a list is left alone
    assert svc.with_city_airports("ZZQ") == "ZZQ"          # unknown: untouched
    assert svc.with_city_airports("") == ""


def test_a_guessed_home_airport_is_widened_but_curated_and_chosen_ones_are_not(monkeypatch):
    svc._airport_code_cache.clear()

    async def _fake(prompt, api_key, **kw):
        return "DWC", []
    monkeypatch.setattr(svc, "_call_gemini", _fake)
    # The model's single answer for a suburb: the whole city is searched.
    assert asyncio.run(svc._resolve_airport_code("Jabal Ali 3", "", "key")) == "DWC,DXB"
    # A curated city is never widened (Colombo stays CMB, not CMB,RML).
    assert asyncio.run(svc._resolve_airport_code("Colombo", "Sri Lanka", "key")) == "CMB"
    svc._airport_code_cache.clear()

    # The traveller's own single pick is searched on its own.
    monkeypatch.setattr(svc, "SerpApiService", _RecordingSerp)
    _flights(departure_city="Jabal Ali 3", departure_airport="DWC")
    assert _RecordingSerp.searches[0]["departure_city"] == "DWC"


# ── New Zealand plan, 2026-09-29: two things future plans must get right ─────

def _nz():
    return DestinationContext(
        query="New Zealand", name="New Zealand", country="New Zealand", country_code="NZ",
        latitude=-41.0, longitude=174.0, types=("country",), source="places",
    )


NZ_LEGS = [
    {"city": "Auckland", "country": "NZ", "start_day": 1, "end_day": 2,
     "latitude": -36.85, "longitude": 174.76},
    {"city": "Wellington", "country": "NZ", "start_day": 3, "end_day": 7,
     "latitude": -41.29, "longitude": 174.78},
]
AKL = {"iata": "AKL", "city": "Auckland", "name": "Auckland Airport",
       "latitude": -37.0082, "longitude": 174.785}
WLG = {"iata": "WLG", "city": "Wellington", "name": "Wellington Airport",
       "latitude": -41.3272, "longitude": 174.8053}


def test_an_airport_18_km_out_gets_its_transfer_stop():
    """Auckland airport is 18 km from town; at a 40 km threshold the plan
    opened at the hotel, with nowhere for the private-car price to go."""
    route = RoutePlan(legs=NZ_LEGS, arrival=AKL, departure=WLG,
                      arrival_code="AKL", departure_code="WLG", source="planner")
    flight = {"title": "Colombo to Auckland", "route": "CMB → AKL", "trip_type": "open_jaw",
              "price_per_traveler": 1800, "currency": "USD"}
    prompt = svc._build_prompt(
        "New Zealand", "Adventurous", 9000, 7, "USD", travelers=2,
        departure_city="Colombo", departure_country="Sri Lanka", legs=NZ_LEGS,
        geo=_nz(), confirmed_flight=flight, route_plan=route,
    )
    assert '"Transfer: Auckland airport → Auckland"' in prompt
    # Wellington airport is 5 km from its centre, and Lisbon's 6: close, but
    # the traveller still has to get into town.
    assert '"Transfer: Wellington → Wellington airport"' in prompt


def test_an_airport_in_town_needs_no_transfer_stop():
    in_town = dict(AKL, latitude=-36.855, longitude=174.765)   # about 1 km out
    route = RoutePlan(legs=NZ_LEGS[:1], arrival=in_town, departure=in_town,
                      arrival_code="AKL", departure_code="AKL", source="planner")
    flight = {"title": "x", "route": "CMB → AKL", "trip_type": "round_trip",
              "price_per_traveler": 1800, "currency": "USD"}
    prompt = svc._build_prompt(
        "Auckland", "Adventurous", 9000, 4, "USD", travelers=2,
        departure_city="Colombo", departure_country="Sri Lanka", legs=NZ_LEGS[:1],
        geo=_nz(), confirmed_flight=flight, route_plan=route,
    )
    assert '"Transfer: Auckland airport → Auckland"' not in prompt


def test_an_estimate_keeps_the_open_jaw_the_trip_was_planned_with(monkeypatch):
    """SerpApi down: the live search gave up the open jaw for a round trip via
    Auckland, the round trip found nothing too, and the estimate still flew
    home from Auckland — a 7.5-hour drive from Wellington on the last day."""
    class _Down:
        def __init__(self, key, **kw):
            pass

        async def search_flights(self, **kw):
            return {}

        async def search_flights_return(self, **kw):
            return {}

    asked = []

    async def _estimate(prompt, api_key, **kw):
        asked.append(prompt)
        return json.dumps({"strategies": [{
            "title": "x", "estimated_price_range": "USD 1500 - 1900",
            "route": "CMB → AKL", "return_route": "AKL → CMB",
            "airlines": ["Qantas"], "stops": 1, "total_duration": "20h",
        }]}), []

    monkeypatch.setattr(svc, "SerpApiService", _Down)
    monkeypatch.setattr(svc, "_call_gemini", _estimate)
    route = RoutePlan(legs=NZ_LEGS, arrival=dict(AKL), departure=dict(WLG),
                      arrival_code="AKL", departure_code="WLG", source="planner")
    result = asyncio.run(svc.generate_flight_strategies(
        departure_city="Colombo", departure_country="Sri Lanka", destination="New Zealand",
        days=7, budget=9000, currency="USD", travelers=2,
        flight_start_date="2026-10-11", flight_end_date="2026-10-17",
        api_key="k", serpapi_key="s", destination_geo=_nz(), route_plan=route,
    ))
    assert result["trip_type"] == "open_jaw"
    assert result["strategies"][0]["return_route"] == "WLG → CMB"
    assert result["departure_airport"]["iata"] == "WLG"
    assert route.departure["iata"] == "WLG" and route.departure_code == "WLG"
    assert '"return_route" MUST be "WLG → CMB"' in asked[-1]


def test_an_estimate_for_andorra_may_land_next_door(monkeypatch):
    class _Down:
        def __init__(self, key, **kw):
            pass

        async def search_flights(self, **kw):
            return {}

        async def search_flights_return(self, **kw):
            return {}

    asked = []

    async def _estimate(prompt, api_key, **kw):
        asked.append(prompt)
        return json.dumps({"strategies": []}), []

    monkeypatch.setattr(svc, "SerpApiService", _Down)
    monkeypatch.setattr(svc, "_call_gemini", _estimate)
    _flights(departure_city="Dubai")
    assert "Never route to an airport in a different country" not in asked[-1]
