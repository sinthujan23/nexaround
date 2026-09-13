"""Shared test fixtures.

The SerpApi cache is off for every test: the suites call `SerpApiService`
with the same parameters over and over and assert on the HTTP call each one
makes. With the cache on, the second identical search would be served from
the in-process fallback map and never reach the patched client.
"""
import pytest

from app.services import serpapi_service


@pytest.fixture(autouse=True)
def _serpapi_cache_off(monkeypatch):
    monkeypatch.setattr(serpapi_service, "_CACHE_ENABLED", False)
    yield
