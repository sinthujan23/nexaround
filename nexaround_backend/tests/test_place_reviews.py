"""Travellers' own place reviews: the rules that decide stars and order.

Pure rules plus monkeypatched lookups only: the suite runs against the
production database, so nothing here writes a review.
"""
import asyncio
from datetime import datetime, timezone

import pytest

from app.schemas.place import PlaceResponse
from app.services import banded_places_service, place_bands, place_reviews


# ── combined_score ──────────────────────────────────────────────────────────

def test_no_ratings_of_ours_keeps_the_old_order():
    # Google rating: exactly quality_score.
    assert place_bands.combined_score(4.6, 800) == place_bands.quality_score(4.6, 800)
    # Free place: popularity on the 0..4 scale.
    assert place_bands.combined_score(0, 0, popularity=60) == pytest.approx(2.4)
    assert place_bands.combined_score(0, 0) == 0.0


def test_our_ratings_count_like_extra_google_reviews():
    mixed = place_bands.combined_score(4.0, 10, our_rating=5.0, our_count=10)
    assert mixed == pytest.approx(place_bands.quality_score(4.5, 20))


def test_one_enthusiastic_review_cannot_leapfrog_a_free_area():
    famous = place_bands.combined_score(0, 0, popularity=90)          # 3.6
    one_five_star = place_bands.combined_score(
        0, 0, our_rating=5.0, our_count=1, popularity=20)             # mostly 0.8
    assert one_five_star < famous
    # Many good ratings of ours do lift it.
    many = place_bands.combined_score(0, 0, our_rating=4.8, our_count=40, popularity=20)
    assert many > famous


def test_popularity_is_only_a_small_bonus_on_a_rated_place():
    base = place_bands.combined_score(4.5, 200)
    assert place_bands.combined_score(4.5, 200, popularity=100) == pytest.approx(base + 0.2)


def test_ranking_uses_the_combined_score():
    a = {"id": "a", "rating": 0, "review_count": 0, "popularity": 40, "distance_m": 10}
    b = {"id": "b", "rating": 0, "review_count": 0, "popularity": 40, "distance_m": 10,
         "our_rating": 4.9, "our_review_count": 30}
    assert sorted([a, b], key=banded_places_service._rank_for_selection)[0]["id"] == "b"


# ── rating_source ───────────────────────────────────────────────────────────

def test_google_stars_need_reviews_behind_them():
    assert place_reviews.rating_source(4.4, 120, 0) == "google"
    # The 4.0 our Google mapping fills in when Google has no rating.
    assert place_reviews.rating_source(4.0, 0, 0) is None


def test_our_stars_from_three_ratings():
    assert place_reviews.OUR_STARS_MIN == 3
    assert place_reviews.rating_source(0, 0, 2) is None
    assert place_reviews.rating_source(0, 0, 3) == "nexaround"
    # Google's stars win when the place has them.
    assert place_reviews.rating_source(4.2, 50, 9) == "google"


# ── ids ─────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("pid, ok", [
    ("ChIJN1t_tDeuEmsRUsoyG83frY4", True),
    ("op_08f2a3b4c5d6e7f8", True),
    ("ga_51a8c3e1f0b2", True),
    ("6f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f", True),
    ("x", False),
    ("bad id with spaces", False),
    ("../../etc", False),
])
def test_valid_place_id(pid, ok):
    assert place_reviews.valid_place_id(pid) is ok


# ── attach ──────────────────────────────────────────────────────────────────

@pytest.fixture(autouse=True)
def _no_photo_pass(monkeypatch):
    """attach also runs the photo pass (place_photos), which reads settings and
    Redis; these tests are about ratings only."""
    from app.services import place_photos

    async def nothing(places):
        return None

    monkeypatch.setattr(place_photos, "attach", nothing)
    monkeypatch.setattr(place_photos, "attach_responses", nothing)


def _no_reviews(monkeypatch):
    async def none():
        return False

    async def must_not_run(ids):
        raise AssertionError("no lookups while nobody has reviewed")

    monkeypatch.setattr(place_reviews, "_any_published", none)
    monkeypatch.setattr(place_reviews, "summaries", must_not_run)


def test_attach_without_reviews_needs_no_database(monkeypatch):
    _no_reviews(monkeypatch)
    places = [
        {"id": "ChIJx", "rating": 4.3, "review_count": 90},
        {"id": "op_1", "rating": 0.0, "review_count": 0, "popularity": 50},
    ]
    asyncio.run(place_reviews.attach(places))
    assert [p["rating_source"] for p in places] == ["google", None]
    assert all(p["our_review_count"] == 0 and p["our_rating"] is None for p in places)


def test_attach_fills_our_ratings(monkeypatch):
    async def yes():
        return True

    async def sums(ids):
        return {"op_1": (4.5, 4), "ChIJx": (3.0, 1)}

    monkeypatch.setattr(place_reviews, "_any_published", yes)
    monkeypatch.setattr(place_reviews, "summaries", sums)
    places = [
        {"id": "ChIJx", "rating": 4.3, "review_count": 90},
        {"id": "op_1", "rating": 0.0, "review_count": 0},
    ]
    asyncio.run(place_reviews.attach(places))
    assert places[0]["rating_source"] == "google" and places[0]["our_review_count"] == 1
    assert places[1] == {**places[1], "our_rating": 4.5, "our_review_count": 4,
                         "rating_source": "nexaround"}


def test_attach_responses_sets_model_fields(monkeypatch):
    _no_reviews(monkeypatch)
    p = PlaceResponse(id="op_1", name="Cafe", latitude=1.0, longitude=2.0,
                      created_at=datetime.now(timezone.utc))
    asyncio.run(place_reviews.attach_responses([p]))
    assert p.our_review_count == 0 and p.rating_source is None
