"""The provider fetch engine: fast when it can be, silent when it cannot.

Every travel-data provider (GetTransfer, Airalo, WeGoTrip, Aviasales) goes
through `providers.base.fetch`. These tests pin the promises the Odyssey relies
on: a cached answer costs no call, a slow or failing provider never holds a
plan up or makes it fail, and identical requests share one call.

The cache is an in-memory dict here. The test container shares Redis with the
live stack, so nothing in this file may reach the real one.
"""
import asyncio
import json
import time

import httpx
import pytest

from app.services import place_cache_service
from app.services.providers import base, config


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def cache(monkeypatch):
    store: dict[str, str] = {}

    async def _get(key):
        return store.get(key)

    async def _set(key, value, ttl=0):
        store[key] = value

    monkeypatch.setattr(place_cache_service, "get_raw", _get)
    monkeypatch.setattr(place_cache_service, "set_raw", _set)
    monkeypatch.setattr(base, "_open_until", {})
    monkeypatch.setattr(base, "_failures", {})
    return store


class Upstream:
    """A fake provider: answers with `reply(request)` and counts the calls."""

    def __init__(self, reply):
        self.reply = reply
        self.calls = 0

    async def handle(self, request):
        self.calls += 1
        out = self.reply(request)
        if asyncio.iscoroutine(out):
            out = await out
        return out


@pytest.fixture
def upstream(monkeypatch):
    def _install(reply):
        fake = Upstream(reply)
        monkeypatch.setattr(
            base, "_new_client",
            lambda: httpx.AsyncClient(transport=httpx.MockTransport(fake.handle)),
        )
        return fake
    return _install


def _fetch(**overrides):
    kwargs = dict(
        url="https://provider.test/prices",
        cache_params={"route": "CDG-PAR"},
        fresh_ttl=3600,
        timeout_s=1.0,
    )
    kwargs.update(overrides)
    return base.fetch("testprov", "prices", **kwargs)


def _age(cache, seconds):
    """Pretend every cached answer was written `seconds` ago."""
    for key, raw in list(cache.items()):
        env = json.loads(raw)
        if isinstance(env, dict) and "at" in env:
            env["at"] = time.time() - seconds
            cache[key] = json.dumps(env)


# ── Cache ────────────────────────────────────────────────────────────────────

def test_a_fresh_answer_is_served_without_calling_out(cache, upstream):
    fake = upstream(lambda r: httpx.Response(200, json={"price": 71}))

    async def run():
        return await _fetch(), await _fetch()

    first, second = asyncio.run(run())
    assert (first.data, first.source) == ({"price": 71}, "upstream")
    assert (second.data, second.source) == ({"price": 71}, "redis")
    assert fake.calls == 1


def test_nothing_here_is_remembered_for_its_own_time(cache, upstream):
    fake = upstream(lambda r: httpx.Response(422, json={"error": "no route"}))

    async def run():
        return await _fetch(empty_ttl=600), await _fetch(empty_ttl=600)

    first, second = asyncio.run(run())
    assert first.empty and not first.ok
    assert second.source == "negative"
    assert fake.calls == 1, "a route the provider cannot serve must not be asked again"


def test_an_empty_list_counts_as_nothing_here(cache, upstream):
    fake = upstream(lambda r: httpx.Response(200, json={"results": []}))

    async def run():
        kw = dict(empty_ttl=600, is_empty=lambda d: not d["results"])
        return await _fetch(**kw), await _fetch(**kw)

    first, second = asyncio.run(run())
    assert first.empty and second.source == "negative"
    assert fake.calls == 1


def test_only_what_transform_returns_is_kept(cache, upstream):
    upstream(lambda r: httpx.Response(200, json={"prices": {"economy": 71}, "noise": "x" * 5000}))
    got = asyncio.run(_fetch(transform=lambda body: body["prices"]))
    assert got.data == {"economy": 71}
    assert "noise" not in next(iter(cache.values()))


def test_the_cache_key_ignores_parameter_order():
    a = base.cache_key("p", "op", {"iata": "CDG", "date": "2026-11-10", "party": "1-3"})
    b = base.cache_key("p", "op", {"party": "1-3", "date": "2026-11-10", "iata": "CDG"})
    assert a == b


# ── Stale-while-revalidate ───────────────────────────────────────────────────

def test_a_stale_answer_is_served_at_once_and_refreshed_behind(cache, upstream):
    prices = iter([71, 83])

    async def reply(request):
        await asyncio.sleep(0.2)
        return httpx.Response(200, json={"price": next(prices)})

    fake = upstream(reply)

    async def run():
        await _fetch(fresh_ttl=60, stale_ttl=86400)
        _age(cache, 120)  # past fresh, inside stale
        started = time.perf_counter()
        stale = await _fetch(fresh_ttl=60, stale_ttl=86400)
        waited = time.perf_counter() - started
        await asyncio.gather(*base._background)
        fresh = await _fetch(fresh_ttl=60, stale_ttl=86400)
        return stale, waited, fresh

    stale, waited, fresh = asyncio.run(run())
    assert (stale.data, stale.source) == ({"price": 71}, "stale")
    assert waited < 0.1, "a stale answer must not wait for the refresh"
    assert (fresh.data, fresh.source) == ({"price": 83}, "redis")
    assert fake.calls == 2


# ── Single-flight ────────────────────────────────────────────────────────────

def test_identical_requests_at_the_same_moment_share_one_call(cache, upstream):
    async def reply(request):
        await asyncio.sleep(0.05)
        return httpx.Response(200, json={"price": 71})

    fake = upstream(reply)

    async def run():
        return await asyncio.gather(*(_fetch() for _ in range(5)))

    results = asyncio.run(run())
    assert all(r.data == {"price": 71} for r in results)
    assert fake.calls == 1


# ── Time limit ───────────────────────────────────────────────────────────────

def test_a_slow_provider_gives_up_on_time(cache, upstream):
    async def reply(request):
        await asyncio.sleep(2)
        return httpx.Response(200, json={"price": 71})

    upstream(reply)
    started = time.perf_counter()
    got = asyncio.run(_fetch(timeout_s=0.1))
    assert got.error == "timeout" and not got.ok
    assert time.perf_counter() - started < 1.0


# ── Circuit breaker ──────────────────────────────────────────────────────────

def test_repeated_failures_stop_the_calls(cache, upstream):
    fake = upstream(lambda r: httpx.Response(503, text="busy"))

    async def run():
        return [await _fetch() for _ in range(base.BREAKER_FAILURES + 3)]

    results = asyncio.run(run())
    assert fake.calls == base.BREAKER_FAILURES
    assert results[-1].error == "breaker_open"


def test_a_revoked_key_is_not_asked_forever(cache, upstream):
    fake = upstream(lambda r: httpx.Response(401, json={"error": "bad token"}))

    async def run():
        return [await _fetch() for _ in range(base.BREAKER_FAILURES + 3)]

    asyncio.run(run())
    assert fake.calls == base.BREAKER_FAILURES


def test_a_429_waits_as_long_as_the_provider_asks(cache, upstream):
    fake = upstream(lambda r: httpx.Response(429, headers={"Retry-After": "120"}))

    async def run():
        return await _fetch(), await _fetch()

    first, second = asyncio.run(run())
    assert first.error == "rate_limited" and second.error == "breaker_open"
    assert fake.calls == 1
    assert 110 < base._open_until["testprov"] - time.time() <= 120


def test_the_breaker_is_shared_through_redis(cache, upstream):
    """Another process tripped it: this one must stop too."""
    fake = upstream(lambda r: httpx.Response(200, json={"price": 71}))
    cache[base._breaker_key("testprov")] = f"{time.time() + 300:.0f}"
    got = asyncio.run(_fetch())
    assert got.error == "breaker_open"
    assert fake.calls == 0


def test_an_open_breaker_still_serves_an_old_answer(cache, upstream):
    upstream(lambda r: httpx.Response(200, json={"price": 71}))

    async def run():
        await _fetch(fresh_ttl=60, stale_ttl=86400)
        _age(cache, 120)
        base._open_until["testprov"] = time.time() + 300
        return await _fetch(fresh_ttl=60, stale_ttl=86400)

    got = asyncio.run(run())
    assert (got.data, got.source) == ({"price": 71}, "stale")


def test_a_success_resets_the_failure_count(cache, upstream):
    replies = iter([503] * (base.BREAKER_FAILURES - 1) + [200] + [503] * (base.BREAKER_FAILURES - 1))
    fake = upstream(lambda r: httpx.Response(next(replies), json={"price": 71}))

    async def run():
        for n in range(2 * base.BREAKER_FAILURES - 1):
            await _fetch(cache_params={"n": n})

    asyncio.run(run())
    assert fake.calls == 2 * base.BREAKER_FAILURES - 1, "non-consecutive failures must not trip it"


# ── Connections ──────────────────────────────────────────────────────────────

def test_one_kept_open_client_per_provider_per_loop():
    async def pair():
        return base.client_for("a"), base.client_for("a"), base.client_for("b")

    a1, a2, b = asyncio.run(pair())
    assert a1 is a2, "the connection must be reused within a loop"
    assert a1 is not b
    a3, _, _ = asyncio.run(pair())
    assert a3 is not a1, "a client bound to a closed loop must not be handed out"


# ── The price every provider returns ─────────────────────────────────────────

def test_a_live_quote_fills_the_fields_the_app_already_shows():
    quote = base.PriceQuote(
        amount=71, currency="usd", source="GetTransfer", freshness=base.LIVE,
        basis="Economy car for up to 3, airport → city centre",
        booking_url="https://gettransfer.com/x",
    )
    assert quote.activity_fields() == {
        "cost": "USD 71",
        "price_source": "GetTransfer",
        "price_basis": "Economy car for up to 3, airport → city centre",
        "price_confidence": "Fixed",
        "booking_url": "https://gettransfer.com/x",
    }


def test_each_freshness_maps_to_an_app_label():
    labels = {
        f: base.PriceQuote(amount=1, currency="USD", source="s", freshness=f)
        .activity_fields()["price_confidence"]
        for f in (base.LIVE, base.RECENT, base.ESTIMATE)
    }
    assert labels == {base.LIVE: "Fixed", base.RECENT: "Typical", base.ESTIMATE: "Estimated"}
    no_link = base.PriceQuote(amount=1, currency="USD", source="s", freshness=base.LIVE)
    assert "booking_url" not in no_link.activity_fields()


# ── Switches ─────────────────────────────────────────────────────────────────

@pytest.fixture
def settings(monkeypatch):
    def _set(values):
        monkeypatch.setattr(config, "_config", dict(values))
        monkeypatch.setattr(config, "_config_at", time.time())
    return _set


def test_every_provider_starts_switched_off(settings):
    settings({})
    assert all(asyncio.run(config.mode(p)) == config.OFF for p in config.PROVIDERS)


def test_a_mode_set_in_the_panel_is_read(settings):
    settings({config.mode_key("gettransfer"): "Shadow"})
    assert asyncio.run(config.mode("gettransfer")) == config.SHADOW


def test_an_unknown_mode_reads_as_off(settings):
    settings({config.mode_key("airalo"): "on"})
    assert asyncio.run(config.mode("airalo")) == config.OFF


def test_a_database_outage_keeps_the_last_good_settings(monkeypatch, settings):
    settings({config.mode_key("airalo"): "live"})
    monkeypatch.setattr(config, "_config_at", 0.0)  # due for a reload

    def _broken():
        raise RuntimeError("database down")

    import app.core.database as database
    monkeypatch.setattr(database, "async_session", _broken)
    assert asyncio.run(config.mode("airalo")) == config.LIVE


# ── Admin panel ──────────────────────────────────────────────────────────────

class _FakeSettings:
    store: dict[str, str] = {}

    def __init__(self, db):
        pass

    async def get_setting(self, key, default=""):
        return _FakeSettings.store.get(key, default)

    async def set_setting(self, key, value, description=None):
        _FakeSettings.store[key] = value


def test_the_panel_saves_keys_and_switches_and_tells_the_worker(monkeypatch):
    from app.api.v1 import admin

    _FakeSettings.store = {}
    refreshed = []

    async def _refresh():
        refreshed.append(True)

    monkeypatch.setattr(admin, "SettingsService", _FakeSettings)
    monkeypatch.setattr(admin.provider_config, "refresh", _refresh)

    body = admin.SettingsUpdateRequest(
        travelpayouts_marker=" 781739 ", provider_mode_gettransfer="shadow",
    )
    out = asyncio.run(admin.update_admin_settings(body, db=None, _=None))

    assert _FakeSettings.store["travelpayouts_marker"] == "781739"
    assert out.provider_mode_gettransfer == "shadow"
    assert out.provider_mode_airalo == "off", "an unset switch reads as off"
    assert refreshed, "the change must reach the provider config without a restart"


def test_the_panel_refuses_a_mode_that_does_not_exist():
    from pydantic import ValidationError

    from app.api.v1 import admin

    with pytest.raises(ValidationError):
        admin.SettingsUpdateRequest(provider_mode_airalo="on")


def test_saving_other_settings_does_not_reload_provider_config(monkeypatch):
    from app.api.v1 import admin

    _FakeSettings.store = {}
    refreshed = []

    async def _refresh():
        refreshed.append(True)

    monkeypatch.setattr(admin, "SettingsService", _FakeSettings)
    monkeypatch.setattr(admin.provider_config, "refresh", _refresh)
    asyncio.run(admin.update_admin_settings(
        admin.SettingsUpdateRequest(platform_name="NexARound"), db=None, _=None,
    ))
    assert not refreshed
