"""Cover-photo selection. No network: which of a place's photos becomes the
cover, and how the cache is keyed."""
from app.services.cover_photo_service import _key, _pick_photo


def test_pick_prefers_largest_landscape():
    refs = [
        {"name": "p0", "width": 768, "height": 1024},   # portrait
        {"name": "p1", "width": 1600, "height": 900},   # landscape
        {"name": "p2", "width": 4032, "height": 1816},  # larger landscape
        {"name": "p3", "width": 720, "height": 538},
    ]
    assert _pick_photo(refs) == 2


def test_pick_falls_back_to_first_when_all_portrait():
    refs = [
        {"name": "p0", "width": 768, "height": 1024},
        {"name": "p1", "width": 900, "height": 1600},
    ]
    assert _pick_photo(refs) == 0


def test_cache_key_is_case_and_whitespace_insensitive():
    assert _key("  New York ") == _key("new york")
    assert _key("Paris") != _key("Paris, France")
