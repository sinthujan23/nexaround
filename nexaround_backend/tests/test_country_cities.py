"""The country -> cities list, and the guarantee that nothing invented reaches it.

Every rule here was derived from a real answer the live Google API gave on
2026-09-16, not from the documentation - the documentation would have led to
Text Search, which accepts Miami, Florida on a Japan trip.
"""
import asyncio
import json

import pytest

from app.api.v1.proxy import _primary_types, _google_maps_cache_key
from app.services import country_cities_service as CC


# ── the proxy's cities-only filter ──────────────────────────────────────────

@pytest.mark.parametrize("raw,expect", [
    ("(cities)", ["(cities)"]),
    ("(regions)", ["(regions)"]),
    ("locality,(cities)", ["locality", "(cities)"]),
    ("(cities)|locality", ["(cities)", "locality"]),
    ("(CITIES)", ["(cities)"]),
    ("  (cities)  ", ["(cities)"]),
    ("(cities),(cities)", ["(cities)"]),
    ("restaurant", []),
    ("'; DROP TABLE--", []),
    ("", []), (None, []),
])
def test_only_known_place_kinds_survive(raw, expect):
    """An unknown value must be dropped, never forwarded.

    `includedPrimaryTypes` refuses the whole request when it does not
    recognise a value, so passing one through would cost the caller every
    suggestion rather than just the filter.
    """
    assert _primary_types(raw) == expect


def test_at_most_five_kinds():
    many = ",".join(["(cities)", "locality", "sublocality", "postal_town",
                     "neighborhood", "administrative_area_level_1"])
    assert len(_primary_types(many)) == 5


def test_a_cities_only_search_does_not_share_a_cache_entry():
    """Same text, different question - they must not serve each other."""
    base = {"input": "san", "components": "country:jp"}
    plain = _google_maps_cache_key("place/autocomplete/json", base)
    cities = _google_maps_cache_key("place/autocomplete/json", {**base, "types": "(cities)"})
    assert plain != cities
    assert cities.endswith("|(cities)")
    # and an unknown kind must not look like a filtered search either
    junk = _google_maps_cache_key("place/autocomplete/json", {**base, "types": "restaurant"})
    assert junk == plain


def test_an_unfiltered_key_keeps_its_historic_shape():
    """Entries already in Redis must stay valid.

    Adding a segment to every key would have missed every cached autocomplete
    answer at once and re-bought them all from Google.
    """
    assert _google_maps_cache_key(
        "place/autocomplete/json", {"input": "paris"}) == "ac:paris|global|anywhere"


def test_country_is_still_part_of_the_key():
    jp = _google_maps_cache_key("place/autocomplete/json", {"input": "san", "components": "country:jp", "types": "(cities)"})
    it = _google_maps_cache_key("place/autocomplete/json", {"input": "san", "components": "country:it", "types": "(cities)"})
    assert jp != it


# ── the verifier ────────────────────────────────────────────────────────────

def test_a_name_google_knows_differently_is_kept():
    """Gemini's "Machu Picchu Pueblo (Aguas Calientes)" is Google's "Aguas
    Calientes" - the same place, and Google's name is the one to show."""
    assert CC._names_agree("Machu Picchu Pueblo (Aguas Calientes)", "Aguas Calientes, Peru")


def test_a_fuzzy_match_inside_the_restriction_is_rejected():
    """Autocomplete still answers *something* within its country restriction:
    "Miami" restricted to Japan came back as Minamioguni."""
    assert not CC._names_agree("Miami", "Minamioguni, Kumamoto, Japan")


@pytest.mark.parametrize("a,b", [
    ("Tokyo", "Tokyo, Japan"),
    ("Nuwara Eliya", "Nuwara Eliya, Sri Lanka"),
    ("Kanazawa", "Kanazawa, Ishikawa, Japan"),
])
def test_ordinary_names_agree(a, b):
    assert CC._names_agree(a, b)


@pytest.mark.parametrize("a,b", [("Miami", ""), ("", "Tokyo"), ("", "")])
def test_nothing_agrees_with_nothing(a, b):
    assert not CC._names_agree(a, b)


# ── the list itself ─────────────────────────────────────────────────────────

class _Resp:
    def __init__(self, payload, status=200):
        self._p, self.status_code = payload, status
    def json(self):
        return self._p


def _suggestion(label, place_id="places/abc123"):
    return {"suggestions": [{"placePrediction": {
        "text": {"text": label}, "placeId": place_id}}]}


def _details(name, lat, lng, cc):
    return {"id": "abc123", "displayName": {"text": name},
            "location": {"latitude": lat, "longitude": lng},
            "addressComponents": [{"shortText": cc, "types": ["country", "political"]}]}


class _Client:
    """Stands in for httpx: one scripted answer per city name."""
    def __init__(self, script):
        self.script, self.calls = script, []
    async def __aenter__(self): return self
    async def __aexit__(self, *a): return False
    async def post(self, url, **kw):
        name = kw["json"]["input"]
        self.calls.append(("ac", name, tuple(kw["json"].get("includedRegionCodes") or ()),
                           tuple(kw["json"].get("includedPrimaryTypes") or ())))
        return _Resp(self.script.get(name, {}).get("ac", {"suggestions": []}))
    async def get(self, url, **kw):
        pid = url.rsplit("/", 1)[-1]
        for name, entry in self.script.items():
            if entry.get("pid") == pid:
                return _Resp(entry["details"])
        return _Resp({}, 404)


@pytest.fixture
def patched(monkeypatch):
    def apply(proposed, script):
        async def fake_propose(country, key): return proposed
        monkeypatch.setattr(CC, "_propose", fake_propose)
        client = _Client(script)
        monkeypatch.setattr(CC.httpx, "AsyncClient", lambda *a, **k: client)
        async def no_get(key): return None
        async def no_set(key, value, ttl=0): return None
        monkeypatch.setattr(CC.place_cache_service, "get_raw", no_get)
        monkeypatch.setattr(CC.place_cache_service, "set_raw", no_set)
        return client
    return apply


async def _run(**kw):
    return await CC.main_cities("Japan", "JP", gemini_key="g", maps_key="m", **kw)


def test_an_invented_city_never_reaches_the_traveller(patched):
    """The whole point: Gemini may say anything, Google decides."""
    patched(
        ["Tokyo", "Wakanda", "Kyoto"],
        {
            "Tokyo": {"ac": _suggestion("Tokyo, Japan", "places/tok"), "pid": "tok",
                      "details": _details("Tokyo", 35.6764, 139.65, "JP")},
            "Wakanda": {"ac": {"suggestions": []}},     # Google will not confirm it
            "Kyoto": {"ac": _suggestion("Kyoto, Japan", "places/kyo"), "pid": "kyo",
                      "details": _details("Kyoto", 35.0116, 135.7681, "JP")},
        },
    )
    cities = asyncio.run(_run())
    assert [c["name"] for c in cities] == ["Tokyo", "Kyoto"]
    assert all(c["latitude"] and c["longitude"] for c in cities)
    assert all(c["country_code"] == "JP" for c in cities)


def test_every_lookup_is_restricted_to_the_country_and_to_cities(patched):
    client = patched(["Tokyo"], {"Tokyo": {
        "ac": _suggestion("Tokyo, Japan", "places/tok"), "pid": "tok",
        "details": _details("Tokyo", 35.6764, 139.65, "JP")}})
    asyncio.run(_run())
    assert client.calls == [("ac", "Tokyo", ("JP",), ("(cities)",))]


def test_a_place_google_puts_in_another_country_is_dropped(patched):
    """Belt and braces behind the restriction: the country must be *stated*."""
    patched(["Miami"], {"Miami": {
        "ac": _suggestion("Miami, FL, USA", "places/mia"), "pid": "mia",
        "details": _details("Miami", 25.76, -80.19, "US")}})
    assert asyncio.run(_run()) == []


def test_a_fuzzy_substitute_is_dropped(patched):
    patched(["Miami"], {"Miami": {
        "ac": _suggestion("Minamioguni, Kumamoto, Japan", "places/min"), "pid": "min",
        "details": _details("Minamioguni", 33.1, 131.1, "JP")}})
    assert asyncio.run(_run()) == []


def test_googles_own_name_is_the_one_shown(patched):
    patched(["Machu Picchu Pueblo (Aguas Calientes)"], {
        "Machu Picchu Pueblo (Aguas Calientes)": {
            "ac": _suggestion("Aguas Calientes, Peru", "places/ag"), "pid": "ag",
            "details": _details("Aguas Calientes", -13.155, -72.5257, "JP")}})
    cities = asyncio.run(_run())
    assert [c["name"] for c in cities] == ["Aguas Calientes"]


def test_the_same_place_twice_is_listed_once(patched):
    same = {"ac": _suggestion("Tokyo, Japan", "places/tok"), "pid": "tok",
            "details": _details("Tokyo", 35.6764, 139.65, "JP")}
    patched(["Tokyo", "Tokyo City"], {"Tokyo": same, "Tokyo City": same})
    assert len(asyncio.run(_run())) == 1


def test_a_model_that_says_nothing_is_not_an_error(patched):
    patched([], {})
    assert asyncio.run(_run()) == []


@pytest.mark.parametrize("code", ["", "J", "JPN", "12", "  "])
def test_a_country_code_that_is_not_one_is_refused(code):
    assert asyncio.run(CC.main_cities("Japan", code, gemini_key="g", maps_key="m")) == []


def test_no_keys_means_no_list_rather_than_a_crash(monkeypatch):
    async def no_get(key): return None
    monkeypatch.setattr(CC.place_cache_service, "get_raw", no_get)
    assert asyncio.run(CC.main_cities("Japan", "JP", gemini_key="", maps_key="m")) == []


def test_the_cache_answers_without_calling_anything(monkeypatch):
    stored = [{"name": "Tokyo", "place_id": "tok", "latitude": 35.6,
               "longitude": 139.6, "country_code": "JP"}]
    async def hit(key):
        assert key == "country_cities:v1:JP"
        return json.dumps(stored)
    monkeypatch.setattr(CC.place_cache_service, "get_raw", hit)
    async def boom(*a, **k): raise AssertionError("should not be called")
    monkeypatch.setattr(CC, "_propose", boom)
    assert asyncio.run(CC.main_cities("Japan", "jp", gemini_key="g", maps_key="m")) == stored


def test_a_corrupt_cache_entry_is_rebuilt_not_raised(monkeypatch, patched):
    patched(["Tokyo"], {"Tokyo": {
        "ac": _suggestion("Tokyo, Japan", "places/tok"), "pid": "tok",
        "details": _details("Tokyo", 35.6764, 139.65, "JP")}})
    async def bad(key): return "{not json"
    monkeypatch.setattr(CC.place_cache_service, "get_raw", bad)
    assert [c["name"] for c in asyncio.run(_run())] == ["Tokyo"]
