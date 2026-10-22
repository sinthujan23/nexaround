"""TravelBytes: the travel stories the team posts as the TravelByte account.

They lead the feed under every filter - the ones about the traveller's own
country (or the country they picked) first, nearest first, then the rest
newest first - and the admin form is checked before anything is written.
No database: the ordering is a pure function and the form is a schema plus
`_apply`.
"""
import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.v1.travel_stories import (
    OFFICIAL_IN_OLD_FEED,
    OFFICIAL_IN_STACK,
    _distance_m,
    _is_about,
    _order_nearby,
    _order_official,
)
from app.api.v1.travel_stories_admin import _apply
from app.schemas.travel_story import OfficialStoryIn, TravelStoryResponse
from app.services import user_country
from app.services.official_stories import place_label

TRINCOMALEE = (8.5874, 81.2152)
BEIJING = (39.904, 116.407)
NOW = datetime(2026, 10, 19, tzinfo=timezone.utc)

FURONG = (28.7506, 109.9482)
VIETNAM = (14.0583, 108.2772)


def story(name, lat, lng, days_old, official=False, country=None):
    return SimpleNamespace(
        name=name, latitude=lat, longitude=lng, is_official=official,
        country=country, created_at=NOW - timedelta(days=days_old),
    )


def feed(stories, first_country=None, here=TRINCOMALEE, stack=True):
    """The feed's order: TravelBytes first, then travellers' stories near-you style."""
    pairs = [(s, _distance_m(s, *here)) for s in stories]
    limit = OFFICIAL_IN_STACK if stack else OFFICIAL_IN_OLD_FEED
    official = _order_official([p for p in pairs if p[0].is_official], first_country, limit)
    others = _order_nearby([p for p in pairs if not p[0].is_official])
    return [s.name for s, _ in official + others]


def furong(days_old=3):
    return story("furong", *FURONG, days_old, official=True, country="China")


def vietnam(days_old=0):
    return story("vietnam", *VIETNAM, days_old, official=True, country="Vietnam")


def test_travelbytes_lead_the_row_even_far_away():
    stories = [
        story("nilaveli", 8.700, 81.192, 1),
        furong(),
        story("colombo", 6.927, 79.861, 0),
    ]
    assert feed(stories) == ["furong", "nilaveli", "colombo"]


def test_a_picked_country_keeps_only_its_own_travelbytes():
    # The feed's country filter (get_travel_stories) drops the rest.
    assert _is_about(vietnam(), "Vietnam")
    assert _is_about(story("dubai", None, None, 0, official=True, country="UAE"),
                     "United Arab Emirates")
    assert not _is_about(vietnam(), "Afghanistan")
    assert not _is_about(furong(), "India")
    assert _is_about(story("x", None, None, 0, official=True, country="Atlantis"), "atlantis")


def test_the_travelbyte_about_your_country_comes_first():
    # Standing in China: Furong first although Vietnam is newer.
    assert feed([vietnam(0), furong(3)], first_country="CN", here=BEIJING) == ["furong", "vietnam"]
    # Standing in Vietnam: the other way round.
    assert feed([furong(0), vietnam(3)], first_country="VN") == ["vietnam", "furong"]


def test_in_your_country_the_nearest_comes_first():
    great_wall = story("great_wall", 40.432, 116.570, 9, official=True, country="China")
    shanghai = story("shanghai", 31.230, 121.474, 0, official=True, country="China")
    assert feed([shanghai, great_wall, vietnam()], first_country="CN", here=BEIJING) == [
        "great_wall", "shanghai", "vietnam",
    ]


def test_elsewhere_newest_first():
    # In Sri Lanka there is no TravelByte about Sri Lanka: newest to oldest.
    assert feed([furong(3), vietnam(0)], first_country="LK") == ["vietnam", "furong"]
    # No location at all: the same.
    assert feed([furong(3), vietnam(0)], first_country=None) == ["vietnam", "furong"]


def test_older_app_builds_get_one_travelbyte():
    many = [story(f"tb{i}", None, None, i, official=True, country="Japan") for i in range(15)]
    assert OFFICIAL_IN_OLD_FEED == 1
    assert feed(many, stack=False) == ["tb0"]
    assert feed(many, stack=True) == [f"tb{i}" for i in range(OFFICIAL_IN_STACK)]


def test_the_exclusive_page_gets_every_travelbyte_in_card_order():
    many = [story(f"tb{i}", None, None, i, official=True, country="Japan") for i in range(15)]
    pairs = [(s, None) for s in many] + [(furong(20), None)]
    names = [s.name for s, _ in _order_official(pairs, "CN", None)]
    assert names == ["furong"] + [f"tb{i}" for i in range(15)]


def test_without_travelbytes_the_row_is_the_near_you_order():
    pairs = [(story(n, None, None, d), None) for n, d in (("a", 0), ("b", 5), ("c", 1))]
    assert _order_official([], "LK", OFFICIAL_IN_STACK) == []
    assert [s.name for s, _ in _order_nearby(pairs)] == ["a", "c", "b"]


def test_country_cache_cell_is_a_few_km():
    assert user_country.cache_key(39.904, 116.407) == user_country.cache_key(39.910, 116.400)
    assert user_country.cache_key(39.904, 116.407) != user_country.cache_key(39.904, 116.507)


def test_country_lookup_without_a_key_answers_none(monkeypatch):
    async def no_redis():
        return None

    class NoKeySettings:
        def __init__(self, db):
            pass

        async def get_setting(self, key, default=""):
            return ""

    monkeypatch.setattr(user_country, "get_redis_client", no_redis)
    monkeypatch.setattr(user_country, "SettingsService", NoKeySettings)
    assert asyncio.run(user_country.country_at(None, 39.9, 116.4)) is None


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


def test_the_feed_broadcast_is_silent(monkeypatch):
    """A TravelByte change reaches every app as a data-only topic message:
    nothing shows on the phone, the app reloads its Travel Stories row."""
    from firebase_admin import messaging
    from app.services import fcm_service, official_stories

    sent = []

    async def an_app(db):
        return object()

    monkeypatch.setattr(fcm_service, "_resolve_app", an_app)
    monkeypatch.setattr(messaging, "send", lambda message: sent.append(message) or "id")

    class Session:
        async def __aenter__(self):
            return None

        async def __aexit__(self, *exc):
            return False

    monkeypatch.setattr(official_stories, "async_session", Session)
    asyncio.run(official_stories.announce_feed_changed())

    assert len(sent) == 1
    message = sent[0]
    assert message.topic == "travel_stories"
    assert message.data == {"type": "stories_updated"}
    assert message.notification is None
    assert message.android.priority == "normal"
    assert message.apns.headers == {"apns-push-type": "background", "apns-priority": "5"}
    assert message.apns.payload.aps.content_available is True
    assert message.apns.payload.aps.alert is None and message.apns.payload.aps.sound is None
