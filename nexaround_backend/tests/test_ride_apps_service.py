"""Ride-app chips for the Odyssey itinerary.

The lookup never blocks the itinerary, so every way it can go wrong must end in an empty
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


# ── Store links: each app becomes a button (client, 2026-09-27) ─────────────

PICKME_RESULTS = [
    {"trackName": "PickMe - Driver", "bundleId": "com.pickme.driverpartner",
     "trackViewUrl": "https://apps.apple.com/lk/app/pickme-driver/id1520523477?uo=4"},
    {"trackName": "PickMe Sri Lanka", "bundleId": "com.pickme.passenger",
     "trackViewUrl": "https://apps.apple.com/lk/app/pickme-sri-lanka/id1000163961?uo=4",
     "artworkUrl100": "https://is1.mzstatic.com/pickme.png"},
]
UBER_RESULTS = [
    {"trackName": "Uber Eats: Food Delivery", "bundleId": "com.ubercab.UberEats",
     "trackViewUrl": "https://apps.apple.com/lk/app/uber-eats/id1058959277"},
    {"trackName": "Uber: Rides, eats, and more", "bundleId": "com.ubercab.UberClient",
     "trackViewUrl": "https://apps.apple.com/lk/app/uber/id368677368"},
]


def test_the_rider_app_is_picked_not_the_driver_or_delivery_app():
    assert svc._pick_itunes(PICKME_RESULTS, "PickMe")["bundleId"] == "com.pickme.passenger"
    assert svc._pick_itunes(UBER_RESULTS, "Uber")["bundleId"] == "com.ubercab.UberClient"
    assert svc._pick_itunes(UBER_RESULTS, "Careem") is None
    assert svc._brand("Uber: Rides, eats, and more") == "Uber"
    assert svc._brand("Bolt - Taxi") == "Bolt"


class _Resp:
    def __init__(self, status=200, data=None, text=""):
        self.status_code, self._data, self.text = status, data, text

    def json(self):
        return self._data


def _stores(monkeypatch, itunes: dict, play_titles: dict):
    calls = []

    async def fake_get(client, url, params, op):
        calls.append((op, dict(params)))
        if op == "itunes_search":
            return _Resp(data={"results": itunes.get(params["term"], [])})
        title = play_titles.get(params["id"])
        return _Resp(200, text=f"<html><title>{title}</title>") if title else _Resp(404)

    monkeypatch.setattr(svc, "_get", fake_get)
    return calls


def test_links_are_verified_and_fall_back_to_a_search(cache, monkeypatch):
    calls = _stores(
        monkeypatch,
        itunes={"PickMe": PICKME_RESULTS, "Uber": UBER_RESULTS},
        play_titles={
            "com.pickme.passenger": "PickMe (Sri Lanka) - Apps on Google Play",
            "com.ubercab": "Uber - Request a ride - Apps on Google Play",
        },
    )
    links = asyncio.run(svc.ride_app_links("lk", ["PickMe", "Uber", "Kangaroo Cabs"]))
    pickme, uber, kangaroo = links
    assert pickme["ios_url"] == "https://apps.apple.com/lk/app/pickme-sri-lanka/id1000163961"
    assert pickme["android_url"] == "https://play.google.com/store/apps/details?id=com.pickme.passenger"
    assert pickme["icon_url"] == "https://is1.mzstatic.com/pickme.png"
    # Uber's Play id is not its iPhone bundle id; the known package is checked.
    assert uber["android_url"] == "https://play.google.com/store/apps/details?id=com.ubercab"
    # Nothing verified: no guessed page, a Play search instead; no iPhone link.
    assert kangaroo["ios_url"] == ""
    assert kangaroo["android_url"] == "https://play.google.com/store/search?q=Kangaroo+Cabs&c=apps"
    # Cached per country: a second call asks no store.
    before = len(calls)
    assert asyncio.run(svc.ride_app_links("LK", ["PickMe", "Uber", "Kangaroo Cabs"])) == links
    assert len(calls) == before


def test_a_play_page_for_another_app_is_not_trusted(cache, monkeypatch):
    # The iPhone bundle id exists on Play but belongs to something else.
    _stores(
        monkeypatch,
        itunes={"PickMe": PICKME_RESULTS},
        play_titles={"com.pickme.passenger": "Some Other App - Apps on Google Play"},
    )
    (pickme,) = asyncio.run(svc.ride_app_links("LK", ["PickMe"]))
    assert pickme["android_url"] == "https://play.google.com/store/search?q=PickMe&c=apps"


def test_no_country_or_no_apps_asks_nothing(cache, monkeypatch):
    calls = _stores(monkeypatch, itunes={}, play_titles={})
    assert asyncio.run(svc.ride_app_links("XX", ["Uber"])) == []
    assert asyncio.run(svc.ride_app_links("LK", [])) == []
    assert calls == []
