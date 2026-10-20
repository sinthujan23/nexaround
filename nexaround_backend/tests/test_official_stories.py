"""Official travel stories: the ones the team posts as nexARound.

They are pinned first in the feed whatever else orders it, and the admin form
is checked before anything is written. No database: the ordering is a pure
function and the form is a schema plus `_apply`.
"""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1.travel_stories import _distance_m, _order_nearby, _pin_official
from app.api.v1.travel_stories_admin import _apply
from app.schemas.travel_story import OfficialStoryIn, TravelStoryResponse
from app.services.official_stories import place_label

TRINCOMALEE = (8.5874, 81.2152)
NOW = datetime(2026, 10, 19, tzinfo=timezone.utc)


def story(name, lat, lng, days_old, official=False):
    return SimpleNamespace(
        name=name, latitude=lat, longitude=lng, is_official=official,
        created_at=NOW - timedelta(days=days_old),
    )


def feed(stories, here=TRINCOMALEE):
    pairs = [(s, _distance_m(s, *here)) for s in stories]
    return [s.name for s, _ in _pin_official(_order_nearby(pairs))]


def test_official_story_far_away_still_comes_first():
    stories = [
        story("nilaveli", 8.700, 81.192, 1),
        story("furong", 28.853, 109.987, 3, official=True),
        story("colombo", 6.927, 79.861, 0),
    ]
    assert feed(stories) == ["furong", "nilaveli", "colombo"]


def test_official_stories_newest_first_and_the_rest_keep_their_order():
    stories = [
        story("nilaveli", 8.700, 81.192, 1),
        story("older_official", 8.600, 81.215, 9, official=True),
        story("tokyo", 35.658, 139.702, 0),
        story("newer_official", 28.853, 109.987, 2, official=True),
        story("no_coords", None, None, 0),
    ]
    assert feed(stories) == [
        "newer_official", "older_official", "nilaveli", "tokyo", "no_coords",
    ]


def test_without_official_stories_nothing_moves():
    pairs = [(story(n, None, None, d), None) for n, d in (("a", 0), ("b", 5), ("c", 1))]
    assert [s.name for s, _ in _pin_official(pairs)] == ["a", "b", "c"]


def _form(**over):
    fields = dict(
        title="  A Magical Waterfall Village  ",
        description="Imagine walking through a centuries-old Chinese village.",
        article_md="## Wander Through an Ancient World\n\nText.",
        location_name="Furong Ancient Town",
        country="China",
        latitude=28.853,
        longitude=109.987,
        region_label="Furong Town",
        image_urls=["/static/uploads/experiences/a.jpg", "/static/uploads/experiences/b.jpg"],
    )
    fields.update(over)
    return OfficialStoryIn(**fields)


def test_first_photo_is_the_cover_and_text_is_trimmed():
    row = SimpleNamespace()
    _apply(row, _form())
    assert row.image_url == "/static/uploads/experiences/a.jpg"
    assert row.image_urls == ["/static/uploads/experiences/a.jpg", "/static/uploads/experiences/b.jpg"]
    assert row.title == "A Magical Waterfall Village"
    assert row.is_public is True


def test_label_is_country_then_town_in_capitals():
    row = SimpleNamespace()
    _apply(row, _form())
    assert row.category == "CHINA · FURONG TOWN"
    assert row.region_label == "Furong Town"


def test_label_without_a_town_is_the_country():
    row = SimpleNamespace()
    _apply(row, _form(region_label="  "))
    assert row.category == "CHINA"
    assert row.region_label is None


def test_label_fits_the_category_column():
    assert len(place_label("C" * 100, "R" * 120)) == 100


def test_an_empty_article_is_stored_as_none():
    row = SimpleNamespace()
    _apply(row, _form(article_md="   "))
    assert row.article_md is None


def test_blank_photo_list_is_refused():
    with pytest.raises(HTTPException):
        _apply(SimpleNamespace(), _form(image_urls=["  "]))


@pytest.mark.parametrize("field, value", [
    ("image_urls", []),
    ("country", ""),
    ("title", ""),
    ("latitude", 91),
    ("description", "x" * 1001),
])
def test_form_refuses(field, value):
    with pytest.raises(ValidationError):
        _form(**{field: value})


def test_the_feed_says_which_stories_are_official():
    fields = TravelStoryResponse.model_fields
    assert {"is_official", "title", "article_md"} <= set(fields)
    assert fields["is_official"].default is False
