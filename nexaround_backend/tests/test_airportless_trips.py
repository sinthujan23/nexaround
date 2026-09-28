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
