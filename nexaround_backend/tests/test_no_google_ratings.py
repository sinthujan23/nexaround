"""TL, 2026-11-18: no more rating or review requests to Google. A place's
rating is the one we saved for it (attractions), our travellers' ratings are
added, and a place we hold nothing for has no stars. No database or network."""
import asyncio
import inspect

import httpx
import pytest

from app.schemas.place import PlaceResponse
from app.services import google_places_client, place_reviews, venue_facts_service


def test_no_google_request_asks_for_ratings_or_reviews():
    source = inspect.getsource(google_places_client)
    for field in ("places.rating", "places.userRatingCount", "places.reviews"):
        assert field not in source, field
    mask = google_places_client._DETAILS_FIELD_MASK_NEW.split(",")
    assert not {"rating", "userRatingCount", "reviews"} & set(mask)
    assert "regularOpeningHours" in mask           # hours are still asked for
    assert "rating" not in venue_facts_service._FIELD_MASK


def test_a_missing_rating_is_zero_not_a_made_up_four():
    place = {"id": "ChIJx", "displayName": {"text": "Somewhere"},
             "location": {"latitude": 1.0, "longitude": 2.0}, "types": []}
    out = google_places_client.to_place_dict(place, 1.0, 2.0, "Attractions", None)
    assert out["rating"] == 0.0 and out["review_count"] == 0


@pytest.fixture
def saved(monkeypatch):
    async def stored(ids):
        table = {"ChIJsaved": (4.6, 1200), "6f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f": (4.1, 80)}
        return {i: table[i] for i in ids if i in table}

    async def none_published():
        return False

    async def no_photos(places):
        return None

    from app.services import place_photos
    monkeypatch.setattr(place_reviews, "stored_ratings", stored)
    monkeypatch.setattr(place_reviews, "_any_published", none_published)
    monkeypatch.setattr(place_photos, "attach", no_photos)
    monkeypatch.setattr(place_photos, "attach_responses", no_photos)


def test_lists_use_the_rating_we_saved(saved):
    places = [
        {"id": "ChIJsaved", "rating": 0.0, "review_count": 0},
        {"id": "6f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f", "rating": 0.0, "review_count": 0},
        {"id": "ChIJnew", "rating": 0.0, "review_count": 0},
        {"id": "ChIJrated", "rating": 4.2, "review_count": 30},
    ]
    asyncio.run(place_reviews.attach(places))
    assert (places[0]["rating"], places[0]["review_count"], places[0]["rating_source"]) == (4.6, 1200, "google")
    assert places[1]["rating"] == 4.1 and places[1]["rating_source"] == "google"
    assert places[2]["rating"] == 0.0 and places[2]["rating_source"] is None
    assert places[3]["rating"] == 4.2


def test_flat_lists_too(saved):
    from datetime import datetime, timezone
    p = PlaceResponse(id="ChIJsaved", name="X", latitude=1, longitude=2,
                      created_at=datetime.now(timezone.utc))
    asyncio.run(place_reviews.attach_responses([p]))
    assert (p.rating, p.review_count, p.rating_source) == (4.6, 1200, "google")


def test_odyssey_venue_rating_comes_from_our_saved_rating(monkeypatch):
    async def stored(ids):
        return {"ChIJenzo": (4.7, 9000)} if "ChIJenzo" in ids else {}

    async def no_cache(key):
        return None

    async def keep(key, value, ttl=None):
        return None

    from app.services import place_cache_service
    monkeypatch.setattr(place_reviews, "stored_ratings", stored)
    monkeypatch.setattr(place_cache_service, "get_raw", no_cache)
    monkeypatch.setattr(place_cache_service, "set_raw", keep)
    asked = {}

    def handler(request):
        asked["mask"] = request.headers.get("X-Goog-FieldMask")
        return httpx.Response(200, json={"places": [{
            "id": "ChIJenzo", "displayName": {"text": "Da Enzo al 29"},
            "location": {"latitude": 41.888, "longitude": 12.476},
            # Even if Google sent one, its rating is not used.
            "rating": 3.1, "userRatingCount": 5,
        }]})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    found = asyncio.run(venue_facts_service.lookup(
        client, "Da Enzo al 29", "Rome", latitude=41.89, longitude=12.48, api_key="k"))
    assert "rating" not in asked["mask"]
    assert found["rating"] == 4.7 and found["review_count"] == 9000
