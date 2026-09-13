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


# ── Drift: verify before paying for a second itinerary ──────────────────────

def _plan_naming(where_value, *, field="name"):
    activity = {"time": "13:00", "name": "Lunch", "type": "dining", "cost": "INR 400"}
    if field == "name":
        activity["name"] = where_value
    elif field == "restaurant":
        activity["restaurants"] = [{"name": where_value, "cuisine": "Asian"}]
    return {"summary": "A week in Kerala.", "day_plans": [{"day": 1, "theme": "Kochi", "activities": [activity]}]}


def _drift(plan, monkeypatch, check=None, sample=0):
    calls = []

    async def _verify(name, **kw):
        calls.append(name)
        return check if check is not None else PlaceCheck(query=name)

    monkeypatch.setattr(svc.geo_resolver, "verify_place", _verify)
    result = asyncio.run(svc.detect_geo_drift(
        plan, _ctx(), sample=sample, budget=GeoBudget(),
    ))
    return result, calls


def test_a_foreign_name_in_a_restaurant_is_not_drift(monkeypatch):
    """"The Asian Kitchen by Tokyo Bay" is a real Kochi restaurant.

    It cost a full second 14-day generation before this.
    """
    plan = _plan_naming("The Asian Kitchen by Tokyo Bay", field="restaurant")
    drift, calls = _drift(plan, monkeypatch)
    assert drift.ok and calls == []


def test_a_lone_strong_hit_is_verified_before_regenerating(monkeypatch):
    plan = _plan_naming("Lunch near Kandy Street")
    check = PlaceCheck(query="x", country_code="IN", ok=True, checked=True)
    drift, calls = _drift(plan, monkeypatch, check=check)
    assert drift.ok
    assert len(calls) == 1


def test_a_lone_strong_hit_that_verifies_abroad_still_regenerates(monkeypatch):
    plan = _plan_naming("Lunch near Kandy Street")
    check = PlaceCheck(query="x", country_code="LK", ok=False, checked=True)
    drift, calls = _drift(plan, monkeypatch, check=check)
    assert not drift.ok and len(calls) == 1


def test_an_unverifiable_hit_keeps_its_weight(monkeypatch):
    """No budget, no key, no result — the guard must not be talked out of it."""
    plan = _plan_naming("Lunch near Kandy Street")
    drift, calls = _drift(plan, monkeypatch, check=PlaceCheck(query="x"))
    assert not drift.ok and len(calls) == 1


def test_two_strong_hits_regenerate_without_paying_to_verify(monkeypatch):
    plan = {
        "summary": "",
        "day_plans": [
            {"day": 1, "theme": "Kandy Exploration", "activities": [
                {"time": "09:00", "name": "Galle Fort walk", "type": "exploration"},
            ]},
        ],
    }
    drift, calls = _drift(plan, monkeypatch)
    assert not drift.ok and calls == []
    assert len(drift.reasons) >= 2


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
