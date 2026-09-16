"""Star ratings and opening hours come from Google, or they do not appear.

Audited against the live Places API on 2026-09-16, over 50 ratings on stored
September plans: 24% matched Google exactly, 10% were out by half a star or
more, average error 0.19 stars. The venues were real — 69 of 70 restaurant
names resolved to the right city — so what the model invents is not the place
but the number printed beside it, which is also the one claim a traveller can
check in seconds.
"""
import asyncio
import json
from unittest.mock import AsyncMock, patch

import pytest

from app.services import odyssey_ai_service as svc
from app.services import venue_facts_service as vf


# ── Name matching ──────────────────────────────────────────────────────────

def test_a_shared_distinctive_word_is_the_same_place():
    """Google often knows a venue by a differently-ordered or fuller name."""
    assert vf._names_agree("Pizzarium Bonci", "Bonci Pizzarium")
    assert vf._names_agree("Da Enzo al 29", "Trattoria Da Enzo")
    assert vf._names_agree("Machu Picchu Pueblo (Aguas Calientes)", "Aguas Calientes")


def test_a_shared_generic_word_is_not_the_same_place():
    """The bug this was written for.

    An invented "Trattoria Del Fantasma Inventato" matched the real "Antica
    Trattoria Santo Padre" on the word "trattoria" and was handed its 4.3
    rating and its 425 reviews.
    """
    assert not vf._names_agree(
        "Trattoria Del Fantasma Inventato", "Antica Trattoria Santo Padre",
    )
    assert not vf._names_agree("The Coffee House", "Old Coffee House Bar")


def test_a_name_made_only_of_generic_words_still_matches_itself():
    """Falling back must not reject a venue genuinely called "The Kitchen"."""
    assert vf._names_agree("The Kitchen", "The Kitchen")


# ── Hours ──────────────────────────────────────────────────────────────────

def test_hours_summarise_a_week_that_mostly_agrees():
    week = {"weekdayDescriptions": [
        f"{day}: 9:00 AM – 5:00 PM" for day in
        ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
    ] + ["Sunday: Closed"]}
    assert vf._hours_line(week) == "9:00 AM - 5:00 PM"


def test_hours_are_empty_when_the_week_does_not_agree():
    """No line is better than an arbitrary day's."""
    week = {"weekdayDescriptions": [
        "Monday: 9:00 AM – 1:00 PM", "Tuesday: 10:00 AM – 6:00 PM",
        "Wednesday: 11:00 AM – 3:00 PM", "Thursday: 8:00 AM – 4:00 PM",
        "Friday: 12:00 – 9:00 PM", "Saturday: Closed", "Sunday: Closed",
    ]}
    assert vf._hours_line(week) == ""


def test_closed_days_are_not_hours():
    assert vf._hours_line({"weekdayDescriptions": ["Monday: Closed"] * 7}) == ""
    assert vf._hours_line(None) == ""


# ── The pass over a finished plan ──────────────────────────────────────────

LEGS = [{"city": "Rome", "country": "IT", "start_day": 1, "end_day": 1,
         "latitude": 41.90, "longitude": 12.50}]


def _plan():
    return [{"kind": "day", "day": 1, "activities": [
        {"name": "Colosseum", "type": "attraction", "hours": "Open until late"},
        {"name": "Dinner", "type": "dining", "restaurants": [
            {"name": "Da Enzo al 29", "rating": "4.5 ★", "cuisine": "Roman"},
            {"name": "Invented Place", "rating": "4.8 ★", "cuisine": "None"},
        ]},
    ]}]


def _lookup_returning(table):
    async def _fake(client, name, city, *, latitude, longitude, api_key):
        return table.get(name)
    return _fake


def test_googles_rating_replaces_the_models():
    plan = _plan()
    table = {
        "Colosseum": {"name": "Colosseum", "rating": 4.7, "review_count": 400000,
                      "hours": "8:30 AM - 4:30 PM", "open": True,
                      "latitude": 41.89, "longitude": 12.49},
        "Da Enzo al 29": {"name": "Trattoria Da Enzo", "rating": 4.3,
                          "review_count": 10151, "hours": "12:00 - 3:00 PM",
                          "open": True, "latitude": 41.88, "longitude": 12.47},
    }
    with patch.object(vf, "lookup", _lookup_returning(table)):
        counts = asyncio.run(svc.verify_venue_facts(plan, LEGS, "maps-key"))

    activities = plan[0]["activities"]
    assert activities[0]["hours"] == "8:30 AM - 4:30 PM", "filler hours must be replaced"
    enzo = activities[1]["restaurants"][0]
    assert enzo["rating"] == "4.3", "the model said 4.5; Google says 4.3"
    assert enzo["review_count"] == 10151
    assert enzo["rating_source"] == "Google"
    assert enzo["name"] == "Trattoria Da Enzo", "Google's own name for the place"
    assert counts["rated"] == 1


def test_a_venue_google_will_not_confirm_keeps_its_name_but_loses_its_rating():
    plan = _plan()
    with patch.object(vf, "lookup", _lookup_returning({})):
        counts = asyncio.run(svc.verify_venue_facts(plan, LEGS, "maps-key"))

    names = [r["name"] for r in plan[0]["activities"][1]["restaurants"]]
    assert "Invented Place" in names, "an unconfirmed name is a suggestion, not a lie"
    for restaurant in plan[0]["activities"][1]["restaurants"]:
        assert "rating" not in restaurant
    assert "hours" not in plan[0]["activities"][0]
    assert counts["stripped"] == 3


def test_a_permanently_closed_venue_is_dropped():
    plan = _plan()
    table = {"Da Enzo al 29": {"name": "Trattoria Da Enzo", "rating": 4.3,
                               "review_count": 10, "hours": "", "open": False,
                               "latitude": 41.88, "longitude": 12.47}}
    with patch.object(vf, "lookup", _lookup_returning(table)):
        counts = asyncio.run(svc.verify_venue_facts(plan, LEGS, "maps-key"))
    names = [r["name"] for r in plan[0]["activities"][1]["restaurants"]]
    assert "Trattoria Da Enzo" not in names
    assert counts["dropped"] == 1


def test_without_a_maps_key_nothing_is_asserted():
    """No way to check is not a licence to guess."""
    plan = _plan()
    counts = asyncio.run(svc.verify_venue_facts(plan, LEGS, ""))
    assert counts["stripped"] == 3
    assert "hours" not in plan[0]["activities"][0]
    for restaurant in plan[0]["activities"][1]["restaurants"]:
        assert "rating" not in restaurant


def test_every_model_written_rating_is_discarded_even_when_it_was_right():
    """A correct guess is still a guess; the field must come from Google."""
    plan = _plan()
    table = {"Da Enzo al 29": {"name": "Da Enzo al 29", "rating": 4.5,
                               "review_count": 10151, "hours": "", "open": True,
                               "latitude": 41.88, "longitude": 12.47}}
    with patch.object(vf, "lookup", _lookup_returning(table)):
        asyncio.run(svc.verify_venue_facts(plan, LEGS, "maps-key"))
    enzo = plan[0]["activities"][1]["restaurants"][0]
    assert enzo["rating"] == "4.5"
    assert enzo["rating_source"] == "Google", (
        "the value matching is a coincidence; its provenance is the point"
    )
