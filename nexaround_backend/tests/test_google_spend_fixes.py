"""The four server-side Google spend fixes of 2026-11-09.

1. Identical requests arriving together buy one answer (google_dedupe).
2. A wide nearby search is one Google call, not five, and the database step
   does not re-buy an area Google was already asked about.
3. Where Should I Go Today?'s place check asks Google only for location.
4. The search-box details lookup asks only for name, address and location.

Redis is replaced with an in-memory fake: the test container shares the live
stack's Redis, and these tests write keys.
"""
import asyncio
import json

import httpx
import pytest

from app.api.v1 import proxy
from app.services import (
    discovery_ai_service,
    google_dedupe,
    google_places_client,
    place_cache_service,
    place_visibility,
    places_service,
)


class FakeRedis:
    def __init__(self):
        self.data: dict[str, str] = {}

    async def get(self, key):
        return self.data.get(key)

    async def set(self, key, value, nx=False, ex=None):
        if nx and key in self.data:
            return None
        self.data[key] = value
        return True

    async def delete(self, key):
        self.data.pop(key, None)

    async def exists(self, key):
        return int(key in self.data)


class DownRedis:
    async def _down(self, *args, **kwargs):
        raise ConnectionError("redis down")

    get = set = delete = exists = _down


@pytest.fixture
def fake_redis(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setattr(place_cache_service, "_get_client", lambda: fake)
    monkeypatch.setattr(place_cache_service, "_mem_cache", {})
    return fake


# ── 1. Buy once ─────────────────────────────────────────────────────────────

def _counting_buy(answer, delay=0.05):
    calls = {"n": 0}

    async def buy():
        calls["n"] += 1
        await asyncio.sleep(delay)
        return answer

    return buy, calls


def test_identical_requests_at_the_same_moment_buy_once(fake_redis):
    buy, calls = _counting_buy([{"id": "a"}])

    async def main():
        return await asyncio.gather(*(
            google_dedupe.shared("gdedupe:t:1", buy, operation="nearby_search")
            for _ in range(3)
        ))

    results = asyncio.run(main())
    assert calls["n"] == 1
    assert results == [[{"id": "a"}]] * 3


def test_a_repeat_moments_later_reuses_the_answer(fake_redis):
    buy, calls = _counting_buy([{"id": "a"}], delay=0)

    async def main():
        first = await google_dedupe.shared("gdedupe:t:2", buy, operation="nearby_search")
        second = await google_dedupe.shared("gdedupe:t:2", buy, operation="nearby_search")
        return first, second

    first, second = asyncio.run(main())
    assert calls["n"] == 1
    assert first == second == [{"id": "a"}]


def test_waits_for_the_other_worker_process(fake_redis):
    """The other API process holds the 'buying' note and then stores the answer."""
    key = "gdedupe:t:3"
    fake_redis.data[f"{key}:buying"] = "1"
    buy, calls = _counting_buy([{"id": "mine"}], delay=0)

    async def other_process_finishes():
        await asyncio.sleep(0.25)
        fake_redis.data[f"{key}:answer"] = json.dumps([{"id": "theirs"}])
        fake_redis.data.pop(f"{key}:buying")

    async def main():
        asyncio.get_running_loop().create_task(other_process_finishes())
        return await google_dedupe.shared(key, buy, operation="nearby_search")

    assert asyncio.run(main()) == [{"id": "theirs"}]
    assert calls["n"] == 0


def test_buys_itself_when_the_other_process_gives_up(fake_redis):
    key = "gdedupe:t:4"
    fake_redis.data[f"{key}:buying"] = "1"
    buy, calls = _counting_buy([{"id": "mine"}], delay=0)

    async def other_process_fails():
        await asyncio.sleep(0.25)
        fake_redis.data.pop(f"{key}:buying")

    async def main():
        asyncio.get_running_loop().create_task(other_process_fails())
        return await google_dedupe.shared(key, buy, operation="nearby_search")

    assert asyncio.run(main()) == [{"id": "mine"}]
    assert calls["n"] == 1
    assert f"{key}:buying" not in fake_redis.data


def test_a_failed_purchase_is_not_shared_or_remembered(fake_redis):
    calls = {"n": 0}

    async def failing_buy():
        calls["n"] += 1
        raise httpx.HTTPError("403 billing disabled")

    async def main():
        for _ in range(2):
            with pytest.raises(httpx.HTTPError):
                await google_dedupe.shared("gdedupe:t:5", failing_buy, operation="nearby_search")

    asyncio.run(main())
    assert calls["n"] == 2
    assert not any(k.endswith(":answer") for k in fake_redis.data)
    assert not any(k.endswith(":buying") for k in fake_redis.data)


def test_redis_down_means_every_request_buys_as_before(monkeypatch):
    monkeypatch.setattr(place_cache_service, "_get_client", lambda: DownRedis())
    buy, calls = _counting_buy([{"id": "a"}], delay=0)

    async def main():
        await google_dedupe.shared("gdedupe:t:6", buy, operation="nearby_search")
        await google_dedupe.shared("gdedupe:t:6", buy, operation="nearby_search")

    asyncio.run(main())
    assert calls["n"] == 2


class _NoDb:
    async def __aenter__(self):
        return None

    async def __aexit__(self, *exc):
        return False


class _KeySettings:
    def __init__(self, db):
        pass

    async def get_setting(self, name):
        return "test-key"


class _FakeHttp:
    def __init__(self, places=None):
        self.requests = []
        self.places = places or [{"id": "p1"}]

    async def post(self, url, json=None, headers=None, **kw):
        self.requests.append({"url": url, "json": json, "headers": headers})
        await asyncio.sleep(0.05)
        return httpx.Response(
            200, json={"places": self.places}, request=httpx.Request("POST", url)
        )


@pytest.fixture
def fake_google(monkeypatch):
    http = _FakeHttp()

    async def _client():
        return http

    monkeypatch.setattr(google_places_client, "async_session", lambda: _NoDb())
    monkeypatch.setattr(google_places_client, "SettingsService", _KeySettings)
    monkeypatch.setattr(google_places_client, "_get_http_client", _client)
    return http


def test_nearby_search_pair_from_the_home_screen_is_bought_once(fake_redis, fake_google):
    async def search():
        return await google_places_client.nearby_search(
            latitude=15.36871, longitude=75.15782, category="Hospital", radius=50000,
        )

    async def main():
        return await asyncio.gather(search(), search())

    a, b = asyncio.run(main())
    assert len(fake_google.requests) == 1
    assert a == b == [{"id": "p1"}]


def test_different_searches_are_still_bought_separately(fake_redis, fake_google):
    async def main():
        await asyncio.gather(
            google_places_client.nearby_search(
                latitude=15.3687, longitude=75.1578, category="Hospital", radius=50000),
            google_places_client.nearby_search(
                latitude=15.3687, longitude=75.1578, category="Medical", radius=50000),
            google_places_client.nearby_search(
                latitude=15.3687, longitude=75.1578, category="Hospital", radius=5000),
        )

    asyncio.run(main())
    assert len(fake_google.requests) == 3


# ── 2. One call for wide searches; no re-buy of an area already asked ──────

class _Result:
    def scalar_one_or_none(self):
        return None


class _Session:
    async def execute(self, *a, **kw):
        return _Result()

    async def commit(self):
        pass

    async def flush(self):
        pass

    def add(self, obj):
        pass


class _SessionCtx:
    async def __aenter__(self):
        return _Session()

    async def __aexit__(self, *exc):
        return False


class _Repo:
    def __init__(self, session):
        pass

    async def get_nearby(self, **kw):
        return []


@pytest.fixture
def db_stub(monkeypatch, fake_redis):
    """get_nearby with an empty database, and its Google call recorded."""
    calls = []

    async def nearby_search(**kw):
        calls.append(kw)
        return []

    async def no_db_places(**kw):
        return []

    async def seed_index(repo, place_dicts):
        return {}

    async def visible(places):
        return places

    monkeypatch.setattr(places_service, "async_session", lambda: _SessionCtx())
    monkeypatch.setattr(places_service, "AttractionRepository", _Repo)
    monkeypatch.setattr(places_service, "_query_nearby_three_zones", no_db_places)
    monkeypatch.setattr(places_service, "_seed_index", seed_index)
    monkeypatch.setattr(place_visibility, "filter_places", visible)
    monkeypatch.setattr(google_places_client, "nearby_search", nearby_search)
    return calls


def test_a_50km_search_is_one_google_call_at_the_centre(db_stub):
    asyncio.run(places_service.get_nearby(
        latitude=6.9271, longitude=79.8612, category="POI", radius=50000,
    ))
    assert len(db_stub) == 1
    call = db_stub[0]
    assert (call["latitude"], call["longitude"], call["radius"]) == (6.9271, 79.8612, 50000)


def test_buying_an_area_leaves_the_note_for_the_whole_cell(db_stub):
    asyncio.run(places_service.get_nearby(
        latitude=6.9271, longitude=79.8612, category="POI", radius=50000,
    ))

    async def asked(lat, lng):
        return await places_service._asked_google_recently("POI", 50000, lat, lng)

    # Same ~5.5 km cell (0.05°) for a 50 km search; not a different category.
    assert asyncio.run(asked(6.9399, 79.8701))
    assert not asyncio.run(asked(7.2906, 80.6337))
    assert not asyncio.run(
        places_service._asked_google_recently("Nature", 50000, 6.9271, 79.8612))


def test_wide_legacy_failure_still_answers_empty(monkeypatch, db_stub):
    async def new_fails(**kw):
        raise httpx.HTTPError("403")

    async def legacy_fails(**kw):
        raise httpx.HTTPError("REQUEST_DENIED")

    monkeypatch.setattr(google_places_client, "nearby_search", new_fails)
    monkeypatch.setattr(google_places_client, "nearby_search_legacy", legacy_fails)
    result = asyncio.run(places_service.get_nearby(
        latitude=6.9271, longitude=79.8612, category="POI", radius=50000,
    ))
    assert result.places == []


@pytest.fixture
def thin_town(monkeypatch, db_stub):
    """Twelve saved places, all within 20 km: enough to answer, but no place
    in the outer 30% of a 50 km search — the case that triggers a re-buy."""
    async def twelve_near_places(**kw):
        return [(object(), 1000.0 * (i + 1)) for i in range(12)]

    def to_dict(attr, dist):
        return {"id": f"p{dist}", "name": f"Place {dist}", "distance_m": dist,
                "rating": 4.2, "tags": [], "category_name": "POI"}

    spawned = []

    def spawn(coro):
        spawned.append(coro)
        coro.close()

    monkeypatch.setattr(places_service, "_query_nearby_three_zones", twelve_near_places)
    monkeypatch.setattr(places_service, "attraction_to_place_dict", to_dict)
    monkeypatch.setattr(places_service, "_format_response_places", lambda *a: [])
    monkeypatch.setattr(places_service, "spawn_background", spawn)
    return spawned


def test_thin_area_not_yet_asked_is_topped_up_once(thin_town):
    asyncio.run(places_service.get_nearby(
        latitude=6.9271, longitude=79.8612, category="POI", radius=50000,
    ))
    assert len(thin_town) == 1


def test_thin_area_already_asked_is_not_bought_again(thin_town):
    asyncio.run(places_service._note_asked_google("POI", 50000, 6.9271, 79.8612))
    asyncio.run(places_service.get_nearby(
        latitude=6.9302, longitude=79.8655, category="POI", radius=50000,
    ))
    assert thin_town == []


# ── 3. Where Should I Go Today? asks only for location ─────────────────────

def test_place_check_asks_google_only_for_location(fake_google):
    asyncio.run(google_places_client.text_search_locations(
        query="Galle Fort Galle", latitude=6.03, longitude=80.22,
    ))
    sent = fake_google.requests[0]
    assert sent["headers"]["X-Goog-FieldMask"] == "places.id,places.location"
    assert sent["url"].endswith("places:searchText")
    assert sent["json"]["locationBias"]["circle"]["radius"] == 50000.0


def test_where_should_i_go_uses_the_location_only_search(monkeypatch):
    async def locations(**kw):
        return [{"id": "x", "location": {"latitude": 6.0262, "longitude": 80.2170}}]

    async def full_search(**kw):
        raise AssertionError("the place check must not use the full text search")

    monkeypatch.setattr(google_places_client, "text_search_locations", locations)
    monkeypatch.setattr(google_places_client, "text_search", full_search)
    assert asyncio.run(discovery_ai_service.place_exists(
        "Galle Fort", "Galle, Sri Lanka", 6.0329, 80.2168,
    )) is True


# ── 4. Search-box details ask only for name, address and location ──────────

def test_details_lookup_asks_for_no_rating_or_photos():
    fields = set(proxy._DETAILS_FIELD_MASK.split(","))
    assert fields == {"id", "displayName", "formattedAddress", "location"}


def test_details_answer_keeps_the_shape_the_app_reads():
    shaped = proxy._to_legacy_details({
        "id": "ChIJ123",
        "displayName": {"text": "Kandy"},
        "formattedAddress": "Kandy, Sri Lanka",
        "location": {"latitude": 7.2906, "longitude": 80.6337},
    })["result"]
    assert shaped["name"] == "Kandy"
    assert shaped["geometry"]["location"] == {"lat": 7.2906, "lng": 80.6337}
    assert shaped["rating"] is None
    assert shaped["user_ratings_total"] is None
    assert shaped["photos"] == []
