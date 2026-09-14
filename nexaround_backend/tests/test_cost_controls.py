"""The controls that keep one Odyssey's API bill down.

Measured from `api_events` before these landed: ~74% of Gemini spend was the
one grounded itinerary call (output tokens cost 8x input), 9% of generations
paid for that call twice because a single regex hit on a restaurant name
forced a regeneration, and 45% of a month's SerpApi calls were 429s made after
the account had already run out of searches. Nothing here touches the network.
"""
import asyncio
import json

import pytest

from app.services import odyssey_ai_service as svc
from app.services import serpapi_service
from app.services.geo_resolver import DestinationContext, GeoBudget, PlaceCheck


def _ctx(code="IN", country="India", name="Kochi", lat=9.93, lng=76.26):
    return DestinationContext(
        query=name, name=name, country=country, country_code=code,
        latitude=lat, longitude=lng, source="places",
    )


# ── The itinerary prompt asks for less ──────────────────────────────────────

def _prompt(**kw):
    args = dict(
        destination="India", mood="Adventurous", budget=100000, days=7,
        currency="INR", travelers=2, geo=_ctx(name="India"),
    )
    args.update(kw)
    return svc._build_prompt(**args)


def test_prompt_asks_for_minified_json():
    """Indentation in a 12k-token answer is billed like any other token."""
    prompt = _prompt()
    assert "MINIFIED JSON on a single line" in prompt
    assert "no indentation" in prompt


def test_prompt_caps_the_wordiest_fields():
    prompt = _prompt()
    assert '"price_basis": "Under 15 words' in prompt
    assert "up to 2 real top-rated dining suggestions" in prompt
    assert "OMIT this key when not confirmed" in prompt          # hours
    assert "no markdown" in prompt


def test_prompt_still_asks_for_every_field_the_app_reads():
    """Shorter text, same schema — the app drops nothing."""
    prompt = _prompt()
    for key in (
        "price_source", "price_basis", "price_confidence", "hours", "restaurants",
        "budget_breakdown", "practical_info", "booking_partners", "day_plans",
    ):
        assert f'"{key}"' in prompt


# ── The cheap model chain ───────────────────────────────────────────────────

class _Resp:
    status_code = 200
    text = ""

    def __init__(self, payload):
        self._payload = payload

    def json(self):
        return self._payload

    def raise_for_status(self):
        return None


def _fake_http(monkeypatch, payload=None, urls=None):
    urls = urls if urls is not None else []
    body = payload or {"candidates": [{"content": {"parts": [{"text": '{"ok": true}'}]}}]}

    class _Client:
        def __init__(self, *a, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, url, json=None, headers=None):
            urls.append(url)
            return _Resp(body)

    monkeypatch.setattr(svc.httpx, "AsyncClient", _Client)
    return urls


def test_the_lite_chain_calls_flash_lite_first(monkeypatch):
    urls = _fake_http(monkeypatch)
    text, _ = asyncio.run(svc._call_gemini("hi", "k", models=svc._LITE_MODELS))
    assert text == '{"ok": true}'
    assert "gemini-2.5-flash-lite" in urls[0]


def test_the_default_chain_is_unchanged(monkeypatch):
    urls = _fake_http(monkeypatch)
    asyncio.run(svc._call_gemini("hi", "k"))
    assert urls[0].split("/models/")[1].startswith("gemini-2.5-flash:")


def test_the_lite_chain_falls_back_to_flash():
    """Flash-Lite first, full Flash behind it — never a dead end."""
    assert svc._LITE_MODELS[0] == "gemini-2.5-flash-lite"
    assert "gemini-2.5-flash" in svc._LITE_MODELS[1:]


@pytest.mark.parametrize("model, grounded, expected", [
    ("gemini-2.5-flash", False, "gemini_flash_generate"),
    ("gemini-2.5-flash", True, "gemini_flash_grounded"),
    ("gemini-2.5-flash-lite", False, "gemini_flash_lite_generate"),
    ("gemini-2.5-pro", False, "gemini_pro_generate"),
])
def test_telemetry_sku_names_the_model_actually_used(model, grounded, expected):
    """A pro fallback billed at Flash's rate is a silent cost overrun."""
    family = "flash_lite" if "lite" in model else ("pro" if "pro" in model else "flash")
    assert f"gemini_{family}_{'grounded' if grounded else 'generate'}" == expected


def test_the_expensive_calls_stay_on_the_full_chain():
    """The itinerary, the route and a user-triggered swap are not downgraded."""
    source = open(svc.__file__).read()
    for marker in ("use_grounding=True", "response_schema=_ROUTE_SCHEMA"):
        idx = source.index(marker)
        window = source[max(0, idx - 400):idx + 200]
        assert "models=_LITE_MODELS" not in window


# Drift gating was tested here — a lone foreign-looking name was verified
# through Places before it was allowed to trigger a second full itinerary, and
# restaurant names were demoted so "The Asian Kitchen by Tokyo Bay" could not
# relocate a trip. The whole drift check left the pipeline on 2026-09-14, so
# these went with it; the itinerary's geography now rests on the prompt alone
# (see the per-day coordinate tests at the end of this file).


# ── SerpApi: stop calling an empty account ──────────────────────────────────

class _Recorder:
    def __init__(self, status=200, payload=None):
        self.status = status
        self.payload = payload or {"best_flights": [{"x": 1}]}
        self.calls = []

    def install(self, monkeypatch):
        outer = self

        class _R:
            status_code = outer.status
            text = "out of searches"

            def json(self):
                return outer.payload

        class _Client:
            def __init__(self, *a, **kw):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

            async def get(self, url, params=None):
                outer.calls.append(params)
                return _R()

        monkeypatch.setattr(serpapi_service.httpx, "AsyncClient", _Client)
        return self


@pytest.fixture
def guard_on(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_QUOTA_GUARD_ENABLED", True)
    monkeypatch.setattr(serpapi_service, "_quota_blocked_until", 0.0)
    store = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value

    monkeypatch.setattr(serpapi_service.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(serpapi_service.place_cache_service, "set_raw", _set)
    return store


def test_a_429_stops_every_later_search(guard_on, monkeypatch):
    rec = _Recorder(status=429).install(monkeypatch)
    serp = serpapi_service.SerpApiService("k")
    assert asyncio.run(serp.search_flights(departure_city="CMB", destination="COK")) == {}
    assert asyncio.run(serp.search_hotels(destination="Kochi")) == {}
    assert asyncio.run(serp.search_flights(departure_city="CMB", destination="MAA")) == {}
    assert len(rec.calls) == 1                       # only the call that learned it
    assert serpapi_service._QUOTA_GUARD_KEY in guard_on


def test_the_guard_is_shared_through_redis(guard_on, monkeypatch):
    """One worker hitting the limit stops the others too."""
    rec = _Recorder().install(monkeypatch)
    guard_on[serpapi_service._QUOTA_GUARD_KEY] = "1"
    assert asyncio.run(serpapi_service.SerpApiService("k").search_hotels(destination="Kochi")) == {}
    assert rec.calls == []


def test_the_guard_expires_and_calls_resume(guard_on, monkeypatch):
    rec = _Recorder().install(monkeypatch)
    monkeypatch.setattr(serpapi_service, "_quota_blocked_until", 0.0)
    result = asyncio.run(serpapi_service.SerpApiService("k").search_flights(
        departure_city="CMB", destination="COK",
    ))
    assert result and len(rec.calls) == 1


def test_a_guarded_account_still_serves_cached_results(guard_on, monkeypatch):
    """The quota is gone; what we already paid for is not."""
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    rec = _Recorder().install(monkeypatch)
    serp = serpapi_service.SerpApiService("k")
    first = asyncio.run(serp.search_flights(departure_city="CMB", destination="COK"))
    guard_on[serpapi_service._QUOTA_GUARD_KEY] = "1"
    monkeypatch.setattr(serpapi_service, "_quota_blocked_until", 0.0)
    again = asyncio.run(serp.search_flights(departure_city="CMB", destination="COK"))
    assert again == first and len(rec.calls) == 1


def test_an_empty_hotel_town_is_not_re_bought(guard_on, monkeypatch):
    """A town with no classed hotel has none on the retry either."""
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    rec = _Recorder(payload={"search_metadata": {}}).install(monkeypatch)
    serp = serpapi_service.SerpApiService("k")
    for _ in range(3):
        result = asyncio.run(serp.search_hotels(destination="Kinniya"))
        assert not (result.get("properties") or [])
    assert len(rec.calls) == 1


def test_an_empty_flight_search_is_still_retried(guard_on, monkeypatch):
    """Unlike hotels, an empty flight answer is often transient."""
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    rec = _Recorder(payload={"search_metadata": {}}).install(monkeypatch)
    serp = serpapi_service.SerpApiService("k")
    for _ in range(2):
        asyncio.run(serp.search_flights(departure_city="CMB", destination="COK"))
    assert len(rec.calls) == 2


# ── A response with no days must not waste the retry ────────────────────────

def test_a_plan_with_days_passes_the_gate():
    plan = {"title": "x", "day_plans": [{"day": 1, "theme": "Arrival", "activities": [{"name": "a"}]}]}
    svc._require_days(plan, "{...}")          # does not raise
    assert svc._plan_day_count(plan) == 1


@pytest.mark.parametrize("plan", [
    {"title": "x"},                                   # key missing entirely
    {"title": "x", "day_plans": []},                  # present but empty
    {"title": "x", "day_plans": [{}, {}]},            # days with no content
    {"title": "x", "day_plans": "not a list"},
])
def test_a_plan_without_days_is_rejected(plan):
    """It used to travel 500 lines further and die past the one retry."""
    assert svc._plan_day_count(plan) == 0
    with pytest.raises(ValueError, match="no day_plans"):
        svc._require_days(plan, '{"title": "x"}')


def test_a_dayless_grounded_response_falls_back_to_ungrounded(monkeypatch):
    """The real 3-day Canada failure: parsed fine, no days, no second chance."""
    calls = []

    async def _fake(prompt, api_key, **kw):
        calls.append(kw.get("use_grounding", False))
        if kw.get("use_grounding"):
            return '{"title": "Canada", "days": 3, "day_plans": []}', []
        return ('{"title": "Canada", "days": 3, "day_plans": ['
                '{"day": 1, "theme": "Arrival", "activities": [{"name": "Walk", "cost": "Free"}]}]}'), []

    monkeypatch.setattr(svc, "_call_gemini", _fake)

    async def _run():
        text, chunks = await svc._call_gemini("p", "k", use_grounding=True)
        plan = svc._parse_json(text)
        try:
            svc._require_days(plan, text)
        except ValueError:
            text, chunks = await svc._call_gemini("p", "k", use_grounding=False)
            plan = svc._parse_json(text)
        return plan

    plan = asyncio.run(_run())
    assert calls == [True, False]                    # grounded, then the rescue
    assert svc._plan_day_count(plan) == 1


def test_a_short_plan_is_kept_not_thrown_away():
    """Two of three days beats no plan at all — warn, don't fail."""
    plan = {"day_plans": [{"day": 1, "theme": "A", "activities": [{"name": "x"}]},
                          {"day": 2, "theme": "B", "activities": [{"name": "y"}]}]}
    svc._require_days(plan, "{...}")
    svc._warn_if_plan_is_short(plan, 3)
    assert svc._plan_day_count(plan) == 2


# ── Which Saint Petersburg? ─────────────────────────────────────────────────
#
# Client report, 14-day Russia trip: Moscow's hotels were right, two other
# cities returned hotels in the United States. The query was the bare city
# name and `gl` was pinned to "us", so Google localised "hotels in Saint
# Petersburg" for an American searcher and answered with Florida.

SPB_RU = (59.9311, 30.3609)
SPB_US = {"gps_coordinates": {"latitude": 27.7851, "longitude": -82.6465}, "name": "Gulfport Bungalow"}
SPB_HOTEL = {"gps_coordinates": {"latitude": 59.9462, "longitude": 30.3481}, "name": "Radisson Sonya"}
NO_GPS = {"name": "Nevsky Guesthouse"}


def _capture_hotel_params(monkeypatch, payload=None):
    """Run search_hotels against a fake transport, returning the params sent."""
    seen = {}

    class _R:
        status_code = 200
        text = ""
        def json(self):
            return payload if payload is not None else {"properties": [SPB_HOTEL]}

    class _Client:
        def __init__(self, *a, **kw):
            pass
        async def __aenter__(self):
            return self
        async def __aexit__(self, *a):
            return False
        async def get(self, url, params=None):
            seen.update(params or {})
            return _R()

    monkeypatch.setattr(serpapi_service.httpx, "AsyncClient", _Client)
    return seen


def test_the_country_is_named_in_the_query(monkeypatch):
    seen = _capture_hotel_params(monkeypatch)
    asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
    ))
    assert seen["q"] == "hotels in Saint Petersburg, Russia"


def test_the_search_is_localised_to_the_destination_not_the_usa(monkeypatch):
    seen = _capture_hotel_params(monkeypatch)
    asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
    ))
    assert seen["gl"] == "ru"


def test_coordinates_are_sent_as_a_location_bias(monkeypatch):
    seen = _capture_hotel_params(monkeypatch)
    asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
        latitude=SPB_RU[0], longitude=SPB_RU[1],
    ))
    assert seen["ll"] == "@59.9311,30.3609,12z"


def test_the_country_is_not_repeated_when_already_in_the_name(monkeypatch):
    seen = _capture_hotel_params(monkeypatch)
    asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg, Russia", country="Russia", country_code="RU",
    ))
    assert seen["q"] == "hotels in Saint Petersburg, Russia"


def test_without_a_country_the_behaviour_is_unchanged(monkeypatch):
    """Odysseys whose destination never resolved must still search."""
    seen = _capture_hotel_params(monkeypatch)
    asyncio.run(serpapi_service.SerpApiService("k").search_hotels(destination="Kochi"))
    assert seen["q"] == "hotels in Kochi" and seen["gl"] == "us" and "ll" not in seen


def test_a_hotel_on_another_continent_is_dropped(monkeypatch):
    _capture_hotel_params(monkeypatch, payload={"properties": [SPB_HOTEL, SPB_US]})
    data = asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
        latitude=SPB_RU[0], longitude=SPB_RU[1], max_km=60,
    ))
    assert [p["name"] for p in data["properties"]] == ["Radisson Sonya"]


def test_a_hotel_with_no_coordinates_is_kept(monkeypatch):
    """Drop what we can place elsewhere, never what we cannot check."""
    _capture_hotel_params(monkeypatch, payload={"properties": [SPB_HOTEL, NO_GPS]})
    data = asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
        latitude=SPB_RU[0], longitude=SPB_RU[1], max_km=60,
    ))
    assert {p["name"] for p in data["properties"]} == {"Radisson Sonya", "Nevsky Guesthouse"}


def test_bad_coordinates_do_not_empty_the_list(monkeypatch):
    """If everything would be dropped, the coordinates are the likelier error."""
    _capture_hotel_params(monkeypatch, payload={"properties": [SPB_HOTEL]})
    data = asyncio.run(serpapi_service.SerpApiService("k").search_hotels(
        destination="Saint Petersburg", country="Russia", country_code="RU",
        latitude=27.78, longitude=-82.64, max_km=60,      # Florida, wrongly
    ))
    assert [p["name"] for p in data["properties"]] == ["Radisson Sonya"]


def test_the_radius_filter_applies_to_cached_results_too(monkeypatch):
    """A result cached before this guard existed must not keep serving Florida."""
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", True)
    store = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value

    monkeypatch.setattr(serpapi_service.place_cache_service, "get_raw", _get)
    monkeypatch.setattr(serpapi_service.place_cache_service, "set_raw", _set)
    _capture_hotel_params(monkeypatch, payload={"properties": [SPB_HOTEL, SPB_US]})

    serp = serpapi_service.SerpApiService("k")
    kw = dict(destination="Saint Petersburg", country="Russia", country_code="RU",
              latitude=SPB_RU[0], longitude=SPB_RU[1], max_km=60)
    first = asyncio.run(serp.search_hotels(**kw))
    second = asyncio.run(serp.search_hotels(**kw))          # served from cache
    assert [p["name"] for p in first["properties"]] == ["Radisson Sonya"]
    assert [p["name"] for p in second["properties"]] == ["Radisson Sonya"]


def test_legs_carry_their_country_and_coordinates_to_the_search(monkeypatch):
    """End to end: the route planner's geography reaches Google."""
    calls = []

    class _ScriptedSerp:
        def __init__(self, key, **kw):
            pass

        async def search_hotels(self, **kw):
            calls.append(kw)
            return {"properties": [SPB_HOTEL]}

    monkeypatch.setattr(svc, "SerpApiService", _ScriptedSerp)
    legs = [{"city": "Saint Petersburg", "country": "RU", "start_day": 1, "end_day": 3,
             "nights": 2, "latitude": SPB_RU[0], "longitude": SPB_RU[1],
             "check_in_date": "2026-10-01", "check_out_date": "2026-10-03"}]
    asyncio.run(svc.generate_hotel_strategies_for_legs(
        legs=legs, days=3, budget=100000, currency="INR", travelers=2,
        hotel_check_in_date="2026-10-01", hotel_check_out_date="2026-10-03",
        api_key="", serpapi_key="k",
        geo=DestinationContext(query="Russia", name="Russia", country="Russia",
                               country_code="RU", latitude=61.5, longitude=105.3,
                               source="places"),
    ))
    assert calls, "no hotel search was made"
    first = calls[0]
    assert first["country"] == "Russia" and first["country_code"] == "RU"
    assert (first["latitude"], first["longitude"]) == SPB_RU
    assert first["max_km"] == svc._HOTEL_MAX_KM


# ── Per-day coordinates in the itinerary prompt ─────────────────────────────
#
# Client (Russia, 14 days): Moscow's hotels were right, two other cities
# returned US hotels. The hotel half is fixed by verifying what Google sends
# back; for the places Gemini writes, the decision was to strengthen the
# prompt rather than verify each name.

def _russia_prompt(legs=None, is_country=True):
    legs = legs if legs is not None else [
        {"city": "Moscow", "start_day": 1, "end_day": 4, "nights": 4,
         "latitude": 55.75, "longitude": 37.62, "arrive_by": "none"},
        {"city": "Saint Petersburg", "start_day": 5, "end_day": 7, "nights": 2,
         "latitude": 59.93, "longitude": 30.31, "arrive_by": "train",
         "from_previous_km": 700},
    ]
    geo = DestinationContext(
        query="Russia", name="Russia", country="Russia", country_code="RU",
        latitude=61.52, longitude=105.32,
        types=("country",) if is_country else (), source="places",
    )
    return svc._build_prompt(
        destination="Russia", mood="Adventurous", budget=500000, days=7,
        currency="INR", travelers=2, legs=legs, geo=geo,
    )


def test_every_city_is_anchored_to_its_own_coordinates():
    prompt = _russia_prompt()
    assert "Moscow (55.75, 37.62); Saint Petersburg (59.93, 30.31)" in prompt
    assert f"within roughly {svc._PLACE_ANCHOR_KM} km" in prompt


def test_the_anchors_are_not_only_for_whole_countries():
    """A 'Kerala' trip needs per-city anchors as much as a 'Russia' one does."""
    prompt = _russia_prompt(is_country=False)
    assert "Moscow (55.75, 37.62)" in prompt
    assert "within roughly 400 km of there" not in prompt      # the old single radius


def test_the_day_table_carries_each_city_coordinates():
    """The anchor sits on the day's own line, not in a block above it."""
    prompt = _russia_prompt()
    assert "Day 1-4: Moscow at 55.75, 37.62 (sleep in Moscow)" in prompt
    assert "Day 5-7: Saint Petersburg at 59.93, 30.31 (sleep in Saint Petersburg)" in prompt


def test_the_prompt_names_the_ambiguous_city_trap():
    prompt = _russia_prompt()
    assert "CHECK EVERY PLACE BEFORE YOU WRITE IT" in prompt
    assert "Saint Petersburg" in prompt and "United States" in prompt
    assert "not a namesake elsewhere" in prompt


def test_a_leg_without_coordinates_still_produces_a_valid_table():
    """Older Odysseys and the single-leg fallback carry no lat/lng."""
    prompt = _russia_prompt(legs=[
        {"city": "Moscow", "start_day": 1, "end_day": 4, "nights": 4},
        {"city": "Saint Petersburg", "start_day": 5, "end_day": 7, "nights": 2},
    ])
    assert "Day 1-4: Moscow (sleep in Moscow)" in prompt
    assert "The route's cities are at:" not in prompt
    assert "61.5200, 105.3200" in prompt                       # falls back to the destination


# ── The gateway on the ticket, not the one the planner guessed ──────────────
#
# Acceptance run, UK 14 days: the planner chose LHR, the code widened "london"
# to LHR,LGW,STN,LTN so Google could compare them, and the cheapest fare landed
# at Gatwick ~40,000 INR lower. Correct — except the plan still announced LHR,
# and the arrival-transfer distance was measured from Heathrow.

def _strategy(tier, lands, home_from, trip_type="open_jaw"):
    return {
        "tier": tier, "title": f"{tier} fare", "trip_type": trip_type,
        "outbound": {"origin": "CMB", "destination": lands},
        "return": {"origin": home_from, "destination": "CMB"},
    }


def _route_with(arrival, departure):
    return svc.RoutePlan(
        legs=[{"city": "London", "start_day": 1, "end_day": 4, "nights": 4,
               "latitude": 51.51, "longitude": -0.13},
              {"city": "Edinburgh", "start_day": 5, "end_day": 7, "nights": 2,
               "latitude": 55.95, "longitude": -3.19}],
        arrival=dict(arrival), departure=dict(departure),
        arrival_code=arrival["iata"], departure_code=departure["iata"], source="planner",
    )


@pytest.fixture
def airport_geo(monkeypatch):
    coords = {
        "LGW": {"latitude": 51.15, "longitude": -0.18, "country_code": "GB", "name": "Gatwick"},
        "LHR": {"latitude": 51.47, "longitude": -0.45, "country_code": "GB", "name": "Heathrow"},
        "EDI": {"latitude": 55.95, "longitude": -3.37, "country_code": "GB", "name": "Edinburgh"},
    }

    async def _geo(code, geo, budget=None):
        return coords.get(code)

    monkeypatch.setattr(svc, "_airport_geo", _geo)
    return coords


def test_the_gateway_follows_the_booked_flight(airport_geo):
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow",
                         "latitude": 51.47, "longitude": -0.45},
                        {"iata": "EDI", "city": "Edinburgh", "name": "Edinburgh"})
    fs = {"arrival_airport": {"iata": "LHR", "city": "London", "name": "Heathrow"},
          "departure_airport": {"iata": "EDI", "city": "Edinburgh", "name": ""}}
    asyncio.run(svc._reconcile_gateways(route, fs, _strategy("recommended", "LGW", "EDI")))
    assert fs["arrival_airport"]["iata"] == "LGW"
    assert fs["arrival_airport"]["city"] == "London"        # still London
    assert route.arrival["iata"] == "LGW"


def test_the_new_gateway_carries_its_own_coordinates(airport_geo):
    """Otherwise the transfer is still measured from the airport they avoided."""
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow",
                         "latitude": 51.47, "longitude": -0.45},
                        {"iata": "EDI", "city": "Edinburgh", "name": "Edinburgh"})
    asyncio.run(svc._reconcile_gateways(route, {}, _strategy("recommended", "LGW", "EDI")))
    assert route.arrival["latitude"] == 51.15               # Gatwick, not Heathrow
    assert route.arrival["name"] == "Gatwick"


def test_an_unchanged_gateway_is_left_alone(airport_geo):
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow",
                         "latitude": 51.47, "longitude": -0.45},
                        {"iata": "EDI", "city": "Edinburgh", "name": "Edinburgh"})
    before = dict(route.arrival)
    asyncio.run(svc._reconcile_gateways(route, {}, _strategy("recommended", "LHR", "EDI")))
    assert route.arrival == before


def test_an_estimated_flight_keeps_the_planners_gateways(airport_geo):
    """The AI-estimate path has no leg objects — nothing to reconcile from."""
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow"},
                        {"iata": "EDI", "city": "Edinburgh", "name": "Edinburgh"})
    fs = {"arrival_airport": {"iata": "LHR", "city": "London", "name": "Heathrow"}}
    asyncio.run(svc._reconcile_gateways(route, fs, {"tier": "minimum", "title": "est"}))
    assert route.arrival["iata"] == "LHR" and fs["arrival_airport"]["iata"] == "LHR"


def test_no_flight_at_all_changes_nothing(airport_geo):
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow"},
                        {"iata": "EDI", "city": "Edinburgh", "name": "Edinburgh"})
    asyncio.run(svc._reconcile_gateways(route, {}, None))
    assert route.arrival["iata"] == "LHR"


def test_the_trip_type_follows_the_booked_flight(airport_geo):
    route = _route_with({"iata": "LHR", "city": "London", "name": "Heathrow"},
                        {"iata": "LHR", "city": "London", "name": "Heathrow"})
    fs = {"trip_type": "open_jaw"}
    asyncio.run(svc._reconcile_gateways(route, fs, _strategy("recommended", "LGW", "LGW", "round_trip")))
    assert fs["trip_type"] == "round_trip"
