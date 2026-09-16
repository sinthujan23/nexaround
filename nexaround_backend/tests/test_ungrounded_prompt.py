"""The retry that has no search tool must not be told to search.

Roughly one Odyssey in nine loses Google Search grounding: the grounded pass
returns a plan short of the days asked for, `_require_days` rejects it, and
generation retries with `use_grounding=False`. That retry used to be sent the
*same* prompt — one that says "you have been given live Google Search access",
"search for that specific item before writing its cost", and "price_source
must name the actual source you found via search".

A model told to search with no way to search does not refuse. It writes what a
search would plausibly have returned. Measured on stored September plans: 27
priced items on ungrounded plans cite a named website — "Tripoto", "Eating
Europe", "Russiable" — as their price source. None of those pages was ever
read, because no search ran.
"""
import pytest

from app.services import odyssey_ai_service as svc
from app.services.geo_resolver import DestinationContext


GEO = DestinationContext(
    query="Italy", name="Italy", country="Italy", country_code="IT",
    latitude=41.9, longitude=12.5, source="test",
)
LEGS = [{"city": "Rome", "country": "IT", "start_day": 1, "end_day": 3,
         "nights": 2, "latitude": 41.90, "longitude": 12.50}]


def _prompt(grounded: bool) -> str:
    return svc._build_prompt(
        "Italy", "Cultural", 3000, 3, "USD", travelers=2, legs=LEGS, geo=GEO,
        nationality="Sri Lankan", has_visa=False, grounded=grounded,
    )


def test_the_ungrounded_prompt_never_mentions_the_search_tool():
    assert "google_search" not in _prompt(False)
    assert "google_search" in _prompt(True), "the grounded pass really does have it"


def test_the_ungrounded_prompt_forbids_naming_a_source_it_cannot_have_read():
    prompt = _prompt(False)
    assert "NO SEARCH ACCESS" in prompt
    assert 'must be exactly one of: "Estimate" or "Typical local rate"' in prompt
    assert "fabricated citation" in prompt


def test_the_ungrounded_prompt_asks_for_no_ratings_and_no_hours():
    prompt = _prompt(False)
    assert 'Leave "hours" as an empty string for EVERY activity' in prompt
    assert 'Omit the "rating" field from every restaurant' in prompt


def test_the_grounded_prompt_still_asks_for_hours_and_real_sources():
    """The grounded path is unchanged — it can actually do these things."""
    prompt = _prompt(True)
    assert "search for the venue's real opening hours" in prompt
    assert "must name the actual source you found via search" in prompt
    assert "NO SEARCH ACCESS" not in prompt


def test_visa_guidance_does_not_claim_a_checked_processing_time_when_ungrounded():
    prompt = _prompt(False)
    assert "confirmed with the embassy" in prompt
    assert "never state a fee or a processing time as a current fact" in prompt
    assert "found via search, not invented" not in prompt


def test_place_checking_survives_without_the_tool():
    """Both passes must still check their places — only the method differs."""
    for grounded in (True, False):
        prompt = _prompt(grounded)
        assert "CHECK EVERY PLACE BEFORE YOU WRITE IT" in prompt
    assert "be certain from your own knowledge" in _prompt(False)
    assert "confirm with the google_search tool" in _prompt(True)
