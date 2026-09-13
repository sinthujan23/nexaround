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
