"""Wikipedia / Unsplash photo lookups: matching and licence rules, no network."""
import asyncio

import httpx
import pytest

from app.services import open_photos


@pytest.mark.parametrize("place, title, ok", [
    ("Galle Fort", "Galle Fort", True),
    ("Galle Fort", "Galle Fort (Sri Lanka)", True),
    ("Palazzo Pitti", "Palazzo Pitti", True),
    ("Café de Flore", "Cafe de Flore", True),
    ("Galle Fort, Sri Lanka", "Galle Fort", True),     # qualifier after a comma
    ("Galle Fort", "Galle Fort Hotel", False),          # found live: a hotel is not the fort
    ("Galle Fort Hotel", "Galle Fort", False),
    ("Fort Cafe", "Fort", False),
    ("Mallu's Dhaba", "Galle Fort", False),
])
def test_names_match(place, title, ok):
    assert open_photos.names_match(place, title) is ok


@pytest.mark.parametrize("licence, needs", [
    ("Public domain", False), ("CC0", False), ("PD-US", False),
    ("CC BY-SA 4.0", True), ("CC BY 2.0", True), (None, True),
])
def test_needs_credit(licence, needs):
    assert open_photos.needs_credit(licence) is needs


def test_wikipedia_picks_the_named_article_nearby(monkeypatch):
    async def area(client, lat, lng):
        return [
            {"title": "Galle Fort", "lat": 6.0270, "lng": 80.2170, "thumb": "https://w/fort.jpg", "file": "Fort.jpg"},
            {"title": "Galle Fort", "lat": 7.0, "lng": 81.0, "thumb": "https://w/far.jpg", "file": "Far.jpg"},
        ]

    async def licence(client, name):
        return "CC BY-SA 3.0", "Jane Doe"

    monkeypatch.setattr(open_photos, "_area_articles", area)
    monkeypatch.setattr(open_photos, "_licence", licence)
    got = asyncio.run(open_photos.from_wikipedia(None, {"name": "Galle Fort", "lat": 6.0268, "lng": 80.2171}))
    assert got["url"] == "https://w/fort.jpg" and got["needs_credit"] is True
    assert got["credit"] == "Photo: Jane Doe / Wikimedia Commons, CC BY-SA 3.0"


def test_wikipedia_unreachable_means_try_later(monkeypatch):
    async def area(client, lat, lng):
        return None

    monkeypatch.setattr(open_photos, "_area_articles", area)
    with pytest.raises(open_photos.TryLater):
        asyncio.run(open_photos.from_wikipedia(None, {"name": "X Y Z", "lat": 1, "lng": 2}))


def _unsplash_client(results):
    def handler(request):
        if "download" in str(request.url):
            return httpx.Response(200, json={})
        return httpx.Response(200, json={"results": results})
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def _allow(monkeypatch):
    async def yes():
        return True
    monkeypatch.setattr(open_photos, "_unsplash_allowed", yes)


SIGHT = {"name": "Galle Fort", "lat": 1, "lng": 2, "section": "Attractions", "reviews": 9000}


def test_unsplash_needs_the_name_in_the_caption(monkeypatch):
    _allow(monkeypatch)
    results = [
        {"description": "A fort by the sea", "urls": {"regular": "https://u/1"}, "user": {"name": "A"}},
        {"description": "View of Galle Fort, Sri Lanka", "urls": {"regular": "https://u/2"},
         "user": {"name": "B"}, "links": {"download_location": "https://u/download/2"}},
    ]
    got = asyncio.run(open_photos.from_unsplash(_unsplash_client(results), SIGHT, "key"))
    assert got == {"source": "unsplash", "url": "https://u/2",
                   "credit": "Photo: B on Unsplash", "needs_credit": True}


@pytest.mark.parametrize("place", [
    {**SIGHT, "section": "Food & Drink"},     # never for cafés and shops
    {**SIGHT, "reviews": 20},                 # only famous sights
    {**SIGHT, "name": "Fort"},                # too short a name to trust
])
def test_unsplash_is_not_asked(monkeypatch, place):
    _allow(monkeypatch)
    results = [{"description": "Fort Galle Fort", "urls": {"regular": "https://u/1"}, "user": {"name": "A"}}]
    assert asyncio.run(open_photos.from_unsplash(_unsplash_client(results), place, "key")) is None


def test_unsplash_skips_a_business_named_after_the_sight(monkeypatch):
    _allow(monkeypatch)
    results = [{"description": "Pool at Galle Fort Hotel", "urls": {"regular": "https://u/1"}, "user": {"name": "A"}}]
    assert asyncio.run(open_photos.from_unsplash(_unsplash_client(results), SIGHT, "key")) is None
