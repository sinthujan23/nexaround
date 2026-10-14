"""A story pinned to its poster's GPS instead of the place it names.

The candidates below are what Google returned for the real stories on
2026-10-14 (Text Search biased to the coordinates each story was sent with).
"""
import asyncio

from app.services import story_location
from app.services.story_location import pick_correction

KINNIYA = (8.50245, 81.18122)  # where "Galle Face Green" and "Marble Beach" were posted from


def place(name, lat, lng, country_code, viewport=None):
    return {"name": name, "latitude": lat, "longitude": lng,
            "viewport": viewport, "country_code": country_code}


GALLE_FACE = place("Galle Face Green", 6.9237882, 79.8449324, "LK")
MARBLE_BEACH = place("Marble Beach - මාබල් බීච්", 8.5107574, 81.2114820, "LK")
DEVILS_BRIDGE = place("The Devil's Bridge", 51.536309, 14.6404792, "DE")
SUNSET_POINT_ABROAD = place("Sunset Point", 18.33, -64.97, "VI")


def test_famous_place_far_from_the_poster_moves_to_the_place():
    fix = pick_correction("Galle Face Green", "Sri Lanka", *KINNIYA, [GALLE_FACE])
    assert fix is GALLE_FACE


def test_a_few_km_off_still_moves():
    fix = pick_correction("Marble Beach", "Sri Lanka", *KINNIYA, [MARBLE_BEACH])
    assert fix is MARBLE_BEACH


def test_story_already_at_the_place_is_kept():
    nilaveli = place("Nilaveli Beach", 8.70031, 81.19205, "LK")
    assert pick_correction("Nilaveli Beach", "Sri Lanka", 8.7003, 81.1921, [nilaveli]) is None


def test_inside_a_large_place_is_kept():
    # A province: the pin is its centre, the story is anywhere inside it.
    yunnan = place("Yunnan", 24.47, 101.34, "CN", viewport=(21.14, 97.53, 29.23, 106.20))
    assert pick_correction("Yunnan", "China", 25.0453, 102.7097, [yunnan]) is None


def test_same_name_in_another_country_is_never_used():
    # A hidden "Sunset Point" in Ella must not fly to the Caribbean.
    assert pick_correction("Sunset Point", "Sri Lanka", 6.8667, 81.0466,
                           [SUNSET_POINT_ABROAD]) is None


def test_different_name_is_kept():
    # Typo'd and Google answers with another name: not sure enough to move it.
    assert pick_correction("Rackotzbrücke, Saxony", "Germany", 50.04459, 10.22185,
                           [DEVILS_BRIDGE]) is None


def test_no_country_is_kept():
    assert pick_correction("Galle Face Green", None, *KINNIYA, [GALLE_FACE]) is None


def test_short_name_inside_a_longer_one_is_not_trusted():
    galle_fort = place("Galle Fort", 6.0275, 80.2170, "LK")
    assert pick_correction("Fort", "Sri Lanka", *KINNIYA, [galle_fort]) is None


def test_short_name_that_is_the_whole_name_moves():
    ella = place("Ella", 6.8667, 81.0466, "LK", viewport=(6.85, 81.03, 6.88, 81.06))
    assert pick_correction("ella", "Sri Lanka", *KINNIYA, [ella]) is ella


def test_any_nearby_candidate_keeps_the_story():
    # Google also knows a same-name spot right here: the poster may well mean it.
    local = place("Galle Face Green", 8.5030, 81.1815, "LK")
    assert pick_correction("Galle Face Green", "Sri Lanka", *KINNIYA,
                           [GALLE_FACE, local]) is None


def test_corrected_location_returns_the_place(monkeypatch):
    async def fake(name, *, bias_lat, bias_lng):
        return [GALLE_FACE]
    monkeypatch.setattr(story_location.google_places_client, "find_place_candidates", fake)
    got = asyncio.run(story_location.corrected_location("Galle Face Green", "Sri Lanka", *KINNIYA))
    assert got == (GALLE_FACE["latitude"], GALLE_FACE["longitude"])


def test_lookup_failure_keeps_the_coordinates(monkeypatch):
    async def boom(name, *, bias_lat, bias_lng):
        raise RuntimeError("google down")
    monkeypatch.setattr(story_location.google_places_client, "find_place_candidates", boom)
    assert asyncio.run(story_location.corrected_location("Galle Face Green", "Sri Lanka", *KINNIYA)) is None


def test_no_coordinates_skips_the_lookup(monkeypatch):
    async def never(*a, **k):
        raise AssertionError("should not be called")
    monkeypatch.setattr(story_location.google_places_client, "find_place_candidates", never)
    assert asyncio.run(story_location.corrected_location("Trincomalee", "Sri Lanka", None, None)) is None
