"""The controls that keep one Odyssey's API bill down.

Measured from `api_events` before these landed: ~74% of Gemini spend was the
one grounded itinerary call (output tokens cost 8x input), 9% of generations
paid for that call twice because a single regex hit on a restaurant name
forced a regeneration, and 45% of a month's SerpApi calls were 429s made after
the account had already run out of searches. Nothing here touches the network.
"""
import asyncio
import json
import re

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
    """Two of three days beats no plan at all — keep it, and say so.

    `_require_days` is called twice in `generate_odyssey`: once with the day
    count, which rejects a short plan so it takes the ungrounded retry, and
    once without after that retry, which only rejects an empty one. A plan
    that is still short then survives, carrying a notice.
    """
    plan = {"day_plans": [{"day": 1, "theme": "A", "activities": [{"name": "x"}]},
                          {"day": 2, "theme": "B", "activities": [{"name": "y"}]}]}

    # First pass: short is a reason to retry.
    with pytest.raises(ValueError, match="2 of 3 days"):
        svc._require_days(plan, "{...}", 3)

    # After the retry: kept, because two days beats none.
    svc._require_days(plan, "{...}")
    assert svc._plan_day_count(plan) == 2

    notice = svc._short_plan_notice(plan, 3)
    assert "2 of 3 days" in notice and "Retry" in notice


def test_a_complete_plan_carries_no_notice():
    plan = {"day_plans": [{"day": d, "theme": "T", "activities": [{"name": "x"}]}
                          for d in (1, 2, 3)]}
    svc._require_days(plan, "{...}", 3)
    assert svc._short_plan_notice(plan, 3) == ""
    # More days than asked is not a shortfall either.
    assert svc._short_plan_notice(plan, 2) == ""


def test_an_empty_plan_is_refused_by_both_passes():
    for expected in (0, 3):
        with pytest.raises(ValueError, match="no day_plans"):
            svc._require_days({"day_plans": []}, "{...}", expected)


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

    async def _geo(code, geo, budget=None, city=""):
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


# ── What the app prints under a price ───────────────────────────────────────
#
# `odyssey_plan_view` renders `price_source` and `price_basis` whenever they
# are non-empty, so whatever the model writes there reaches the traveller
# verbatim. A live Vietnam plan came back with eleven free stops carrying
# "price_source": "N/A", and a free market visit sourced to "Vietnam Airlines".

from app.services.odyssey_ai_service import _is_free, _sourced


@pytest.mark.parametrize("written", [
    "N/A", "n/a", "N/A.", "na", "None", "none.", "-", "--", "Unknown",
    "TBD", "not applicable", "no source",
])
def test_a_models_way_of_writing_nothing_is_not_a_source(written):
    assert _sourced(written) == ""


@pytest.mark.parametrize("written", [
    "Google Hotels", "Vietnam Airlines", "Official site", "Lonely Planet",
])
def test_a_real_source_survives(written):
    assert _sourced(written) == written


@pytest.mark.parametrize("cost", ["Free", "free", "Free (chairs/umbrellas extra)", "", None])
def test_a_stop_that_names_no_money_is_free(cost):
    assert _is_free(cost) is True


@pytest.mark.parametrize("cost", ["USD 25", "₹1,200", "Free entry, USD 5 for the tower", "12.50 EUR"])
def test_a_stop_that_names_money_is_not_free(cost):
    assert _is_free(cost) is False


# ── One unit for every price on the card ────────────────────────────────────
#
# Measured across nine live plans: of 447 priced stops, 69% said nothing about
# whether the figure was for one traveller or the party, 23% buried it in the
# small print and 8% put it on the card. A couple reading "INR 1,800" for the
# Bahia Palace was really looking at INR 3,600; a family of four at four times
# the number on screen. The model now returns one adult share as a number and
# the arithmetic happens in `_party_cost`.

from app.services.odyssey_ai_service import _party_cost


def test_the_card_shows_what_the_party_pays():
    assert _party_cost({"cost_per_person": "18"}, "EUR", 4) == ("EUR 72", 18.0)
    assert _party_cost({"cost_per_person": "1800"}, "INR", 2) == ("INR 3,600", 1800.0)


def test_a_solo_traveller_pays_one_share():
    assert _party_cost({"cost_per_person": "25"}, "USD", 1) == ("USD 25", 25.0)


def test_an_explicit_zero_is_free_not_missing():
    for written in ("0", "0.00", "EUR 0"):
        assert _party_cost({"cost_per_person": written}, "EUR", 3) == ("Free", 0.0)


def test_nothing_to_price_stays_empty():
    assert _party_cost({}, "EUR", 2) == ("", None)
    assert _party_cost({"cost": ""}, "EUR", 2) == ("", None)


def test_a_legacy_per_person_string_is_multiplied_out():
    """Older plans wrote the unit into the text instead of a field."""
    assert _party_cost({"cost": "EUR 18 / person"}, "EUR", 4) == ("EUR 72", 18.0)
    assert _party_cost(
        {"cost": "INR 1,800", "price_basis": "Standard ticket per person."}, "INR", 2
    ) == ("INR 3,600", 1800.0)


def test_a_legacy_party_string_is_not_multiplied_again():
    """"INR 3,200 ... for two adults" is already the couple's total."""
    shown, per = _party_cost(
        {"cost": "INR 3,200", "price_basis": "Estimated adult entry for two adults."}, "INR", 2
    )
    assert shown == "INR 3,200" and per == 1600.0


def test_an_unmarked_legacy_figure_is_never_inflated():
    """Guessing high would tell a traveller they cannot afford a trip they can."""
    shown, per = _party_cost({"cost": "INR 1,500", "price_basis": "Estimated entry fee."}, "INR", 2)
    assert shown == "INR 1,500" and per == 750.0


def test_free_survives_every_spelling():
    for written in ("Free", "free", "Free (chairs extra)"):
        assert _party_cost({"cost": written}, "INR", 2) == ("Free", 0.0)


def test_the_prompt_asks_for_one_adult_share_as_a_number():
    from app.services.odyssey_ai_service import _build_prompt
    prompt = _build_prompt(
        "Italy", "Relaxed", 12000, 14, "EUR", travelers=4,
        legs=[{"city": "Rome", "start_day": 1, "end_day": 14, "nights": 13,
               "latitude": 41.9, "longitude": 12.5}],
    )
    assert "cost_per_person" in prompt
    assert "ONE adult" in prompt
    assert "4 traveller(s)" in prompt
    # The free-text field the old plans disagreed about is gone.
    assert '"cost": "EUR amount' not in prompt


# ── The estimated-fare path keeps the same promises ─────────────────────────
#
# When SerpApi returns nothing the cards are Gemini estimates. That path never
# went through `_strategy_payload`, so it kept the model's own names — a live
# Italy plan came back headed "Cheapest Budget Flights", "Best Value Split
# Tickets" and "Fastest Direct Option" after the titles had been removed
# everywhere else.

from app.services.odyssey_ai_service import (
    _minutes_from_duration,
    _structure_ai_flight_strategies,
)


@pytest.mark.parametrize("written,minutes", [
    ("14h 30m", 870), ("14h", 840), ("870m", 870), ("1h 5m", 65),
    ("", 0), (None, 0), ("about 20 hours", 1200),
])
def test_a_duration_string_becomes_minutes(written, minutes):
    assert _minutes_from_duration(written) == minutes


def _estimated():
    data = {"strategies": [
        {"title": "Cheapest Budget Flights", "estimated_price_range": "EUR 240 - 300",
         "route": "CMB → FCO", "return_route": "FCO → CMB", "airlines": ["Gulf Air"],
         "stops": 1, "total_duration": "18h 20m", "return_duration": "17h 10m",
         "estimated_savings": "Save ~30%", "tip": "Book early for the best fare."},
        {"title": "Fastest Direct Option", "estimated_price_range": "EUR 425 - 500",
         "route": "CMB → FCO", "return_route": "FCO → CMB", "airlines": ["Qatar Airways"],
         "stops": 1, "total_duration": "13h 50m", "return_duration": "14h 5m",
         "estimated_savings": "Fastest route", "tip": "Worth the premium."},
    ]}
    return _structure_ai_flight_strategies(
        data, currency="EUR", travelers=4,
        outbound_date="2026-11-02", return_date="2026-11-15",
    )["strategies"]


def test_an_estimated_card_states_stops_and_time_not_a_verdict():
    for s in _estimated():
        assert re.match(r"^(Non-stop|\d+ stops?) · \d+h \d+m$", s["title"]), s["title"]
        assert s["estimated_savings"] == ""
        assert s["tip"] == ""


def test_an_estimated_card_carries_its_journey_time():
    cheap, fast = sorted(_estimated(), key=lambda s: s["price_per_traveler"])
    assert cheap["total_duration_minutes"] == 18 * 60 + 20 + 17 * 60 + 10
    assert fast["total_duration_minutes"] == 13 * 60 + 50 + 14 * 60 + 5
    # The header must agree with the number beside it, as on the live path.
    for s in (cheap, fast):
        mins = s["total_duration_minutes"]
        assert s["title"].endswith(f"{mins // 60}h {mins % 60}m")


def test_estimated_cards_are_still_marked_as_estimates():
    for s in _estimated():
        assert s["is_live_price"] is False
        assert s["price_source"] == "ai_estimate"


# ── A search we cut off ourselves ───────────────────────────────────────────
#
# Across 149 live flight searches the average was 2.1 s and the slowest was
# exactly 10.0 s — our own ceiling, not SerpApi's. Cutting one off spends the
# search credit anyway and drops the whole trip onto estimated fares, which is
# how an Italy plan came back headed "Cheapest Budget Flights" while the
# account still had 105 searches left. The exception was logged as an empty
# string, because that is what `str(httpx.ReadTimeout())` is.

def test_a_search_is_given_longer_than_the_slowest_one_observed():
    from app.services import serpapi_service as s
    assert s._HTTP_TIMEOUT_S > 10.0, "the old ceiling is what was cutting searches off"


def test_both_searches_use_the_same_ceiling():
    import inspect
    from app.services import serpapi_service as s
    src = inspect.getsource(s)
    assert "httpx.AsyncClient(timeout=10.0)" not in src, "a hard-coded 10s client is left"
    assert src.count("httpx.AsyncClient(timeout=_HTTP_TIMEOUT_S)") == 2


def test_a_silent_exception_still_names_itself(monkeypatch, caplog):
    """httpx timeouts stringify to "", so the log said nothing at all."""
    import logging, httpx
    from app.services import serpapi_service as s

    class _Boom:
        def __init__(self, *a, **kw): pass
        async def __aenter__(self): raise httpx.ReadTimeout("")
        async def __aexit__(self, *a): return False

    monkeypatch.setattr(s.httpx, "AsyncClient", _Boom)
    with caplog.at_level(logging.ERROR):
        out = asyncio.run(s.SerpApiService("k").search_flights(
            departure_city="CMB", destination="FCO", outbound_date="2026-11-02",
        ))
    assert out == {}
    assert "ReadTimeout" in caplog.text, caplog.text


# ── "There is no such flight" vs "we could not look it up" ──────────────────
#
# No airline flies Pisa to Colombo, so no price exists at any figure. A
# timeout says nothing about the world. Both used to return {} and both ended
# up showing an invented fare, so a traveller could not tell a route that does
# not exist from one we simply failed to reach.

from app.services.serpapi_service import no_results as serp_no_results, _NO_RESULTS_RE
from app.services.odyssey_ai_service import _no_flights_found


@pytest.mark.parametrize("message", [
    "Google Flights hasn't returned any results for this query.",
    "Google Flights has not returned any results for this query.",
    "Google Hotels haven't returned any results for this query.",
])
def test_the_providers_way_of_saying_none_is_recognised(message):
    assert _NO_RESULTS_RE.search(message)


@pytest.mark.parametrize("message", [
    "Your account has run out of searches.",
    "Invalid API key.",
    "Unsupported `XXX` for currency",
])
def test_our_own_failures_are_not_mistaken_for_an_empty_route(message):
    assert not _NO_RESULTS_RE.search(message)


def test_a_failure_is_not_an_empty_route():
    assert serp_no_results({}) is False
    assert serp_no_results(None) is False
    assert serp_no_results({"best_flights": []}) is False


def test_an_empty_route_is_marked_as_one():
    assert serp_no_results({"_serpapi_status": "no_results"}) is True


def test_the_empty_section_carries_a_reason_and_no_price():
    section = _no_flights_found(
        origin_code="CMB", dest_code="PSA", outbound_date="2026-11-02",
        return_date="2026-11-15", arrival_city="Pisa",
    )
    assert section["strategies"] == []
    assert section["flights_available"] is False
    assert section["unavailable_reason"] == "none_found"
    assert "Pisa" in section["unavailable_message"]
    assert "2026-11-02" in section["unavailable_message"]
    # Nothing in it may read as a fare.
    assert not any(
        k in section for k in ("price_per_traveler", "price_total", "estimated_price_range")
    )


def test_an_estimated_section_is_not_marked_unavailable():
    """A timeout must still offer fares — flights probably do exist."""
    data = {"strategies": [{
        "title": "x", "estimated_price_range": "EUR 240 - 300", "route": "CMB → FCO",
        "airlines": ["Gulf Air"], "stops": 1, "total_duration": "18h 20m",
    }]}
    out = _structure_ai_flight_strategies(
        data, currency="EUR", travelers=2, outbound_date="2026-11-02", return_date="",
    )
    assert out.get("flights_available") is not False
    assert out["strategies"][0]["is_live_price"] is False


# ── Opening hours are hours, or they are nothing ────────────────────────────
#
# The prompt already says "leave hours as an empty string — never guess", and
# the model wrote "Open until late" 20 times, "Variable" twice and "Weekends
# only" once across three 14-day plans. The app draws the field verbatim under
# a clock icon, so filler reads to the traveller as a fact about the venue.

@pytest.mark.parametrize("hours", [
    "9:00 AM – 6:00 PM",
    "Open until 9:00 PM today",
    "24 hours",
    "10:00-17:00, closed Mondays",
])
def test_real_opening_hours_survive(hours):
    assert svc.usable_hours(hours) == hours


@pytest.mark.parametrize("hours", [
    "Open until late", "Variable", "Weekends only", "Seasonal", "Check locally",
])
def test_filler_opening_hours_are_dropped(hours):
    assert svc.usable_hours(hours) == "", f"{hours!r} reached the app as opening hours"


def test_missing_or_junk_hours_are_empty_not_an_error():
    for raw in (None, "", "   ", [], {}, 0):
        assert svc.usable_hours(raw) == ""


# ── What the day plan is actually allowed to spend ──────────────────────────
#
# The prompt used to hand the model the whole trip budget and a percentage
# split, then the backend rebuilt that split from the real fares and room
# rates. On a live Colombo->Turkey plan the flights took 48% of the budget, the
# waterfall left 74,362 for activities, and the day plan already written listed
# 103,800 of them.

def _fs(*fares):
    return {"strategies": [
        {"tier": t, "price_per_traveler": float(p), "is_live_price": True, "stops": 1}
        for t, p in fares
    ]}


def _hs(nightly, leg_index=0, nights=5, hotel_class=4):
    return {"strategies": [{
        "leg_index": leg_index, "city": "X", "nights": nights,
        "price_per_night": f"INR {nightly}", "hotel_class": hotel_class,
    }]}


def test_the_ceiling_is_what_is_left_after_flights_and_rooms():
    legs = [{"city": "X", "nights": 5}]
    room = svc.food_and_activities_room(
        budget=750_000,
        flight_strategies=_fs(("minimum", 104_315), ("recommended", 119_497)),
        hotel_strategies=_hs(5_000),
        city_legs=legs,
        travelers=3,
    )
    # 119,497 x 3 = 358,491 flights; 5,000 x 5 x 3 = 75,000 rooms.
    assert room == 750_000 - 358_491 - 75_000


def test_the_ceiling_uses_the_fare_the_budget_uses():
    """The middle card, the same one `_tier_flight_cost` prices from."""
    legs = [{"city": "X", "nights": 1}]
    with_rec = svc.food_and_activities_room(
        budget=500_000, flight_strategies=_fs(("minimum", 10_000), ("recommended", 20_000)),
        hotel_strategies={}, city_legs=legs, travelers=2,
    )
    assert with_rec == 500_000 - 40_000          # the recommended fare, not the cheapest
    # A thin route with no middle card falls back to the cheapest, as the
    # budget does.
    thin = svc.food_and_activities_room(
        budget=500_000, flight_strategies=_fs(("minimum", 10_000), ("comfortable", 30_000)),
        hotel_strategies={}, city_legs=legs, travelers=2,
    )
    assert thin == 500_000 - 20_000


def test_a_budget_the_trip_already_breaks_still_leaves_a_real_ceiling():
    """Subtracting from the entered budget gives nothing; the waterfall does not.

    A 14-day Peru plan for five came to LKR 6.8m against a 6m budget. Clamping
    the remainder at zero sent the prompt back to a percentage of the budget
    while the waterfall went on carving its split out of the lifted total - the
    two disagreed by more than double, and the day plan came in at 2.3x the
    food line it was shown under.
    """
    legs = [{"city": "X", "nights": 5}]
    flight, stay = 120_000 * 4, 9_000 * 5 * 4
    room = svc.food_and_activities_room(
        budget=50_000, flight_strategies=_fs(("recommended", 120_000)),
        hotel_strategies=_hs(9_000), city_legs=legs, travelers=4,
    )
    # The headline is floored at the tier's own cost plus 5%, and that 5% is
    # what food and activities actually get.
    assert room == round((flight + stay) * 1.05, 2) - flight - stay
    assert room > 0


def test_the_ceiling_matches_what_the_waterfall_will_allocate():
    """The figure in the prompt and the figure on the card are one number.

    Peru's real numbers: the waterfall allocated 590,283 across food and
    activities, and the prompt has to name that, not a percentage of a budget
    the trip already broke.
    """
    legs = [{"city": "X", "nights": 13}]
    room = svc.food_and_activities_room(
        budget=6_000_000, flight_strategies=_fs(("recommended", 956_505)),
        hotel_strategies=_hs(27_279, nights=13), city_legs=legs, travelers=5,
        on_ground=250_000,
    )
    assert room == 590_283.0


def test_nothing_priced_leaves_the_whole_budget():
    assert svc.food_and_activities_room(
        budget=100_000, flight_strategies=None, hotel_strategies=None,
        city_legs=[], travelers=2,
    ) == 100_000


def test_the_prompt_states_the_figure_rather_than_a_percentage():
    p = svc._build_prompt(
        destination="Turkey", mood="Adventurous", budget=750_000, days=14,
        currency="INR", travelers=3, spend_room=185_904,
    )
    assert "185904 INR for food and activities" in p
    assert "MUST stay inside 185904 INR" in p
    assert "cost_per_person x 3 inside 185904 INR" in p
    assert "Food & Dining (~10-15%)" not in p, "the guess must not sit beside the figure"


def test_the_prompt_keeps_the_rule_of_thumb_when_nothing_was_priced():
    """The estimate paths reach here with no live prices; a fabricated ceiling
    would be worse than the percentages it replaced."""
    p = svc._build_prompt(
        destination="Turkey", mood="Adventurous", budget=750_000, days=14,
        currency="INR", travelers=3,
    )
    assert "Food & Dining (~10-15%)" in p
    assert "Flights and rooms for this trip come to" not in p


# ── Activity types the app actually knows ───────────────────────────────────
#
# An unrecognised type lands in the client's `other` bucket, which renders no
# button and no [Paid] badge — so a word the model invented quietly costs the
# traveller the price chip. "activity" appeared twice in one 14-day Turkey plan.

@pytest.mark.parametrize("raw", [
    "transport", "attraction", "dining", "exploration", "accommodation", "other",
])
def test_the_six_real_types_pass_through(raw):
    assert svc.normalise_activity_type(raw) == raw


@pytest.mark.parametrize("raw,want", [
    ("activity", "attraction"), ("sightseeing", "attraction"),
    ("experience", "attraction"), ("workshop", "attraction"),
    ("transit", "transport"), ("flight", "transport"),
    ("restaurant", "dining"), ("lunch", "dining"),
    ("walk", "exploration"), ("leisure", "exploration"),
    ("hotel", "accommodation"), ("check-in", "accommodation"),
    ("ATTRACTION", "attraction"), ("  Dining  ", "dining"),
])
def test_synonyms_land_on_a_type_the_app_knows(raw, want):
    assert svc.normalise_activity_type(raw) == want


def test_a_word_nobody_recognises_is_other_not_itself():
    assert svc.normalise_activity_type("quantum picnic") == "other"


def test_no_type_stays_no_type():
    for raw in (None, "", "   "):
        assert svc.normalise_activity_type(raw) == ""


# ── Which column the money sits in ──────────────────────────────────────────
#
# The waterfall split food and activities 60/40 whatever the itinerary held.
# Real plans divide it anywhere from 28/72 to 73/27, so the fixed ratio put one
# line over and the other far under on the same trip: a 14-day Peru plan for
# five listed 377,750 of activities against a 325,433 line while its food line
# sat at 0.67x — the two together came to 0.87x of what they were allowed.

def _plan(*costed):
    """day_plans holding (type, cost_per_person) pairs on one day."""
    return {"day_plans": [{"day": 1, "theme": "t", "activities": [
        {"name": f"stop {i}", "type": t, "cost_per_person": c}
        for i, (t, c) in enumerate(costed)
    ]}]}


def test_the_split_follows_the_itinerary():
    # 300 dining, 700 sightseeing -> 30% food.
    share = svc.food_share_of_plan(_plan(("dining", 300), ("attraction", 700)))
    assert abs(share - 0.30) < 0.001


def test_flights_and_hotels_are_not_counted_in_either_column():
    """They have their own budget lines; counting them here moves the wrong money."""
    with_travel = _plan(
        ("dining", 300), ("attraction", 700),
        ("transport", 50_000), ("accommodation", 20_000),
    )
    assert abs(svc.food_share_of_plan(with_travel) - 0.30) < 0.001


def test_neither_line_is_ever_allowed_to_collapse():
    """People eat whether or not the itinerary lists a restaurant."""
    no_food = _plan(("attraction", 1000), ("exploration", 500))
    no_activities = _plan(("dining", 1000))
    assert svc.food_share_of_plan(no_food) == 0.25
    assert svc.food_share_of_plan(no_activities) == 0.75


def test_a_plan_with_no_prices_keeps_the_old_rule_of_thumb():
    assert svc.food_share_of_plan(_plan(("dining", 0), ("attraction", 0))) == 0.60
    assert svc.food_share_of_plan({"day_plans": []}) == 0.60
    assert svc.food_share_of_plan({}) == 0.60
    assert svc.food_share_of_plan({"day_plans": "nonsense"}) == 0.60


def test_an_unknown_type_counts_as_an_activity_not_as_food():
    """`normalise_activity_type` sends anything unrecognised to `other`."""
    share = svc.food_share_of_plan(_plan(("dining", 500), ("quantum picnic", 500)))
    assert abs(share - 0.50) < 0.001


def test_the_real_peru_split_is_what_was_measured():
    """46/54, against the 60/40 that put its activities line 16% over."""
    share = svc.food_share_of_plan(_plan(("dining", 327_500), ("attraction", 377_750)))
    assert abs(share - 0.464) < 0.005
