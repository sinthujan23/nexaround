"""Restricting a place search to one country, without breaking the others.

The Odyssey planner's entry and exit boxes are filled only after a country has
been chosen, so a city in another country is never a valid answer there: typing
"saint petersburg" while planning Russia must not offer Florida, which is the
mistake that sent one trip's hotels to the United States.

The destination box is the opposite case and must keep searching the whole
world - the proxy carries a standing comment saying so - which is why the
restriction is opt-in and these tests check both sides of it.
"""
import asyncio
import json

import pytest

import app.api.v1.proxy as proxy


# ── Reading the country out of the legacy `components` spelling ─────────────

@pytest.mark.parametrize("components,expected", [
    ("country:lk", "LK"),
    ("country:LK", "LK"),
    ("  country:lk  ", "LK"),
    ("country:fr|country:be", "FR,BE"),
    ("country:fr|country:fr", "FR"),          # a repeat is not two countries
    ("country:us|type:locality", "US"),       # other component types ignored
])
def test_a_country_restriction_is_understood(components, expected):
    assert proxy._region_codes(components) == expected


@pytest.mark.parametrize("components", [
    None, "", "   ", "type:locality", "country:", "country:z", "country:zzz",
    "country:1a", "nonsense",
])
def test_anything_that_is_not_a_country_code_is_ignored(components):
    assert proxy._region_codes(components) == ""


def test_at_most_five_countries_reach_google():
    """Google's own ceiling; a longer list is trimmed, not rejected."""
    many = "|".join(f"country:{c}" for c in ("lk", "in", "fr", "be", "it", "es", "de"))
    assert proxy._region_codes(many) == "LK,IN,FR,BE,IT"


# ── The cache key ──────────────────────────────────────────────────────────

def _key(**params):
    return proxy._google_maps_cache_key("place/autocomplete/json", params)


def test_a_restricted_search_never_serves_an_unrestricted_ones_answer():
    """The restriction is part of the question, so it is part of the key.

    Without this, "paris" restricted to Italy and "paris" searched worldwide
    share one entry and answer each other - the same collision the location
    part of this key already exists to prevent.
    """
    assert _key(input="paris") != _key(input="paris", components="country:it")
    assert _key(input="paris", components="country:it") != _key(
        input="paris", components="country:fr")


def test_the_same_question_still_shares_one_entry():
    assert _key(input="Paris", components="country:IT") == _key(
        input="  paris  ", components="country:it")


def test_an_unrestricted_search_keys_the_way_it_always_did():
    assert _key(input="paris").endswith("|anywhere")
    assert "ac:paris|global" in _key(input="paris")


# ── What actually goes to Google ───────────────────────────────────────────

class _Resp:
    status_code = 200

    def json(self):
        return {"suggestions": []}


class _Client:
    def __init__(self):
        self.sent = []

    async def post(self, url, json=None, headers=None, timeout=None):
        self.sent.append(json)
        return _Resp()


def _upstream(params):
    client = _Client()
    asyncio.run(proxy._google_places_new(client, "place/autocomplete/json", params, "k"))
    return client.sent[-1]


def test_the_destination_box_still_searches_the_whole_world():
    """The standing comment in the proxy protects this; so does this test."""
    body = _upstream({"input": "paris", "language": "en"})
    assert "includedRegionCodes" not in body
    assert body["input"] == "paris"


def test_an_entry_search_is_held_to_its_country():
    body = _upstream({"input": "paris", "components": "country:it"})
    assert body["includedRegionCodes"] == ["IT"]


def test_a_junk_restriction_does_not_silently_narrow_the_search():
    """Better to search everywhere than to search one country nobody asked for."""
    body = _upstream({"input": "paris", "components": "country:zzz"})
    assert "includedRegionCodes" not in body


def test_a_location_bias_and_a_country_restriction_coexist():
    body = _upstream({
        "input": "kandy", "components": "country:lk",
        "location": "6.9271,79.8612", "radius": "50000",
    })
    assert body["includedRegionCodes"] == ["LK"]
    assert body["locationBias"]["circle"]["center"]["latitude"] == pytest.approx(6.9271)
