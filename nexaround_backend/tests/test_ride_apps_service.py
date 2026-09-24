"""Ride-app chips for the Odyssey itinerary.

The lookup is display only, so every way it can go wrong must end in an empty
list rather than an error, and a country must cost at most one Gemini call per
cache period however many travellers open a trip there. Pure functions and
stubs only: no network, no Redis, no database.
"""
import asyncio
from datetime import datetime, timezone

import pytest

from app.services import odyssey_ai_service, place_cache_service
from app.services import ride_apps_service as svc


@pytest.fixture
def cache(monkeypatch):
    store: dict[str, tuple[str, int]] = {}

    async def get_raw(key):
        hit = store.get(key)
        return hit[0] if hit else None

    async def set_raw(key, value, ttl=0):
        store[key] = (value, ttl)

    monkeypatch.setattr(place_cache_service, "get_raw", get_raw)
    monkeypatch.setattr(place_cache_service, "set_raw", set_raw)
    # A lock that waited in one test's event loop is bound to it.
    monkeypatch.setattr(svc, "_locks", {})
    return store


@pytest.fixture
def gemini(monkeypatch):
    calls: list[dict] = []
    answer = {"text": '{"apps": ["PickMe", "Uber"]}', "error": None}

    async def fake_call(prompt, api_key, **kwargs):
        calls.append({"prompt": prompt, **kwargs})
        await asyncio.sleep(0)  # yield, so concurrent lookups really overlap
        if answer["error"]:
            raise answer["error"]
        return answer["text"], []

    monkeypatch.setattr(odyssey_ai_service, "_call_gemini", fake_call)
    return calls, answer


def lookup(code):
    return asyncio.run(svc.ride_apps_for(code, "test-key"))


def test_code_is_normalised_and_must_be_a_real_country():
    assert svc.normalise_code("lk") == "LK"
    assert svc.normalise_code(" LK ") == "LK"
    assert svc.normalise_code("XX") is None
    assert svc.normalise_code("LKA") is None
    assert svc.normalise_code("") is None
    assert svc.normalise_code(None) is None


def test_country_table_is_complete_and_well_formed():
    assert len(svc.COUNTRY_NAMES) == 249
    bad = [
        code for code, name in svc.COUNTRY_NAMES.items()
        if len(code) != 2 or code != code.upper() or not name.strip()
    ]
    assert bad == []
    assert svc.COUNTRY_NAMES["LK"] == "Sri Lanka"
    assert svc.COUNTRY_NAMES["GB"] == "United Kingdom"


def test_prompt_names_the_country_searches_and_asks_for_json():
    prompt = svc.build_prompt("LK")
    assert "Sri Lanka" in prompt and "LK" in prompt
    assert "Search Google" in prompt
    assert str(datetime.now(timezone.utc).year) in prompt  # searches for now
    assert '{"apps": [' in prompt


def test_answer_is_kept_only_as_far_as_it_looks_like_app_names():
    raw = [" Uber ", "uber", "Pick  Me", "", 5, "https://x.example", "None",
           "A" * 31, "Bolt", "Grab", "Careem"]
    assert svc.clean_app_names(raw) == ["Uber", "Pick Me", "Bolt", "Grab"]
    assert svc.clean_app_names("Uber, PickMe") == []
    assert svc.clean_app_names(None) == []


def test_lookup_asks_gemini_once_with_search_then_serves_the_cache(cache, gemini):
    calls, _ = gemini
    assert lookup("lk") == ["PickMe", "Uber"]
    assert lookup("LK") == ["PickMe", "Uber"]
    assert len(calls) == 1
    call = calls[0]
    assert call["use_grounding"] is True
    assert call["operation"] == "odyssey_ride_apps"
    assert call["models"] == odyssey_ai_service._LITE_MODELS
    assert cache["ride_apps:v1:LK"] == ('["PickMe", "Uber"]', svc._CACHE_TTL)


def test_unknown_code_never_reaches_gemini(cache, gemini):
    calls, _ = gemini
    assert lookup("XX") == []
    assert lookup("") == []
    assert calls == [] and cache == {}


def test_a_failed_call_is_an_empty_list_retried_soon(cache, gemini):
    _, answer = gemini
    answer["error"] = RuntimeError("503 from every model")
    assert lookup("LK") == []
    assert cache["ride_apps:v1:LK"] == ("[]", svc._FAILURE_TTL)


def test_an_answer_that_is_not_json_is_an_empty_list(cache, gemini):
    _, answer = gemini
    answer["text"] = "Sorry, I can't help with that."
    assert lookup("LK") == []
    assert cache["ride_apps:v1:LK"] == ("[]", svc._FAILURE_TTL)


def test_no_apps_there_is_cached_longer_than_a_failure(cache, gemini):
    _, answer = gemini
    answer["text"] = '{"apps": []}'
    assert lookup("AF") == []
    assert cache["ride_apps:v1:AF"] == ("[]", svc._EMPTY_TTL)


def test_travellers_opening_the_same_country_at_once_share_one_call(cache, gemini):
    calls, _ = gemini

    async def both():
        return await asyncio.gather(
            svc.ride_apps_for("LK", "test-key"),
            svc.ride_apps_for("LK", "test-key"),
        )

    assert asyncio.run(both()) == [["PickMe", "Uber"], ["PickMe", "Uber"]]
    assert len(calls) == 1


def test_endpoint_is_registered_under_the_odyssey_routes():
    from app.api.v1 import itineraries

    paths = {getattr(r, "path", "") for r in itineraries.router.routes}
    assert "/itineraries/odyssey/ride-apps" in paths
