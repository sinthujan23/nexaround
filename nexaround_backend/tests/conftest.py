"""Shared test fixtures.

The SerpApi cache and quota guard are off for every test. The suites call
`SerpApiService` with the same parameters over and over and assert on the HTTP
call each one makes: with the cache on, the second identical search would be
served from the in-process fallback map and never reach the patched client,
and a 429 in one test would silence every SerpApi call in the tests after it.
"""
import pytest

from app.services import serpapi_service, telemetry


@pytest.fixture(autouse=True)
def _serpapi_cache_off(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", False)
    monkeypatch.setattr(serpapi_service, "_QUOTA_GUARD_ENABLED", False)
    monkeypatch.setattr(serpapi_service, "_quota_blocked_until", 0.0)
    yield


@pytest.fixture(autouse=True)
def _no_telemetry(monkeypatch):
    """Keep test runs out of the cost dashboard.

    The suite runs in a container that shares Redis with the live stack, so
    every `telemetry.track` block in the code under test was queueing a row
    that the worker duly flushed into `api_events` — fake calls, priced with
    real rates, in the numbers the admin panel reports as spend.
    """
    async def _drop(row):
        return None

    monkeypatch.setattr(telemetry, "_emit", _drop)
    yield


@pytest.fixture(autouse=True)
def _providers_off(monkeypatch):
    """Every travel-data provider reads as switched off unless a test says not.

    Without this, the first plan a test generates would ask the database for
    the admin panel's switches — there is no database in the test container.
    """
    import time

    from app.services.providers import config

    monkeypatch.setattr(config, "_config", {})
    monkeypatch.setattr(config, "_config_at", time.time())
    yield


@pytest.fixture(autouse=True)
def _leg_lookup_off(monkeypatch):
    """Route legs keep the planner's coordinates unless a test says not.

    `_leg_geo` reads the Redis the live stack shares and calls Places; every
    route-planner test would otherwise do both. Tests of the lookup itself
    restore the real function (see tests/test_hotels_without_rates.py).
    """
    from app.services import odyssey_ai_service

    async def _unknown(*args, **kwargs):
        return None

    monkeypatch.setattr(odyssey_ai_service, "_leg_geo", _unknown)
    yield
