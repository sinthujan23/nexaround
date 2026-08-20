"""Guards the Flutter client's copy of the rules against the server's.

The band table and the section rules exist twice — once in Python, once in Dart
— because the server decides what to fetch and the client decides what to show.
Nothing in either language can see the other, so the two drift, and drift here
is silent: the app simply disagrees with the backend about what a place is.

That is not hypothetical. `park` was removed from Nature on the server and left
in the client, so Around You correctly hid Ezhilarangu Stadium while the
Discovery tab went on listing it under Nature.

These tests read the Dart source as text and compare it to the Python tables.
Crude, but it turns a silent divergence into a failing build.
"""
import re
from pathlib import Path

import pytest

from app.services import place_bands as pb

def _find_app_core() -> Path | None:
    """Locate the Flutter app's `lib/core`.

    Checked in order so this runs from a repo checkout, from CI, and from inside
    the API container, where the app is not on the same relative path.
    """
    import os

    override = os.environ.get("NEXAROUND_APP_DIR")
    candidates = [Path(override) / "lib" / "core"] if override else []
    here = Path(__file__).resolve()
    candidates += [
        parent / "nexaround_app" / "lib" / "core" for parent in here.parents
    ]
    return next((c for c in candidates if (c / "constants" / "place_bands.dart").exists()), None)


APP = _find_app_core()
BANDS_DART = (APP / "constants" / "place_bands.dart") if APP else Path("missing")
SECTIONS_DART = (APP / "utils" / "place_sections.dart") if APP else Path("missing")

pytestmark = pytest.mark.skipif(
    not BANDS_DART.exists(),
    reason="Flutter app not present in this checkout",
)


def _dart(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _string_list(source: str, name: str) -> set[str]:
    """Pull `static const <name> = [ 'a', 'b' ];` out of Dart as a set."""
    match = re.search(rf"{name}\s*=\s*\[(.*?)\];", source, re.S)
    assert match, f"could not find `{name}` in the Dart source"
    return set(re.findall(r"'([^']+)'", match.group(1)))


def _int_list(source: str, name: str) -> list[int]:
    match = re.search(rf"{name}\s*=\s*\[(.*?)\];", source, re.S)
    assert match, f"could not find `{name}` in the Dart source"
    return [int(n) for n in re.findall(r"\d+", match.group(1))]


# ── Band table ──────────────────────────────────────────────────────────────

def test_band_quotas_match():
    assert _int_list(_dart(BANDS_DART), "bandQuotas") == list(pb.BAND_QUOTAS)


def test_total_per_category_matches():
    source = _dart(BANDS_DART)
    total = int(re.search(r"totalPerCategory\s*=\s*(\d+)", source).group(1))
    assert total == pb.TOTAL_PER_CATEGORY


def test_the_same_six_sections_exist_on_both_sides():
    listed = _string_list(_dart(BANDS_DART), "sections")
    assert listed == set(pb.CATEGORY_BANDS)


def test_every_band_boundary_matches():
    """A boundary that disagrees sorts places into different bands on each
    side, which reads as a mis-ordered list rather than as a bug."""
    source = _dart(BANDS_DART)
    for category, bands in pb.CATEGORY_BANDS.items():
        block = re.search(
            rf"'{re.escape(category)}':\s*\[(.*?)\],\s*\n", source, re.S
        )
        assert block, f"{category} missing from place_bands.dart"
        pairs = re.findall(r"PlaceBand\(([\d.]+),\s*([\d.]+)\)", block.group(1))
        dart_m = [(round(float(a) * 1000), round(float(b) * 1000)) for a, b in pairs]
        # The Dart table is in kilometres and rounds 1667m to 1.667km.
        expected = [(lo, hi) for lo, hi in bands]
        assert len(dart_m) == len(expected), f"{category}: band count differs"
        for (dlo, dhi), (plo, phi) in zip(dart_m, expected):
            assert abs(dlo - plo) <= 1, f"{category}: band start {dlo} vs {plo}"
            assert abs(dhi - phi) <= 1, f"{category}: band end {dhi} vs {phi}"


# ── Section rules ───────────────────────────────────────────────────────────

def test_nature_tags_match_the_server():
    """The regression that prompted this file: `park` lived on in the client
    after the server dropped it, so the two disagreed about Nature."""
    assert _string_list(_dart(SECTIONS_DART), "_natureTags") == \
        pb.allowed_tags_for("Nature")


def test_client_nature_rules_reject_generic_parks():
    """Narrowing the tag list alone is not enough — the client also matches on
    name and category, and both were letting generic parks back in."""
    source = _dart(SECTIONS_DART)
    assert "park" not in _string_list(source, "_natureWords")
    assert "cat.contains('park')" not in source, \
        "the category test still admits any place filed under a 'park' category"


def test_quality_score_uses_the_same_constants():
    """Different shrinkage constants rank the same places differently, so a
    card and its tab would disagree about which place leads."""
    source = _dart(BANDS_DART)
    weight = float(re.search(r"priorWeight\s*=\s*([\d.]+)", source).group(1))
    mean = float(re.search(r"priorMean\s*=\s*([\d.]+)", source).group(1))
    # Mirrors the constants in place_bands.quality_score.
    assert (weight, mean) == (30.0, 4.0)
    # And agrees numerically on a real case.
    v, r = 1795, 4.4
    dart_value = (v * r + weight * mean) / (v + weight)
    assert dart_value == pytest.approx(pb.quality_score(r, v))
