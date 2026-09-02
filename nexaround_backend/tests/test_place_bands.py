"""Rules that decide what each Around You / Discovery section shows.

These are cheap invariants over pure functions — no database, no network. They
exist because the rules are subtle, spread across two languages, and every one
of them was written in response to a real bug. Left untested they drift back.
"""
import pytest

from app.services import place_bands as pb
from app.services.google_places_client import CATEGORY_TYPES_MAP


SECTIONS = list(pb.CATEGORY_BANDS)


# ── Band structure ──────────────────────────────────────────────────────────

def test_quotas_sum_to_the_advertised_total():
    assert sum(pb.BAND_QUOTAS) == pb.TOTAL_PER_CATEGORY


@pytest.mark.parametrize("category", SECTIONS)
def test_bands_are_contiguous_and_start_at_zero(category):
    """A gap between bands is a distance no place can ever be shown at."""
    bands = pb.bands_for(category)
    assert len(bands) == pb.BANDS_PER_CATEGORY
    assert bands[0][0] == 0
    for (_, prev_max), (next_min, _) in zip(bands, bands[1:]):
        assert prev_max == next_min, f"{category} has a gap at {prev_max}m"
    for lo, hi in bands:
        assert lo < hi


# ── The invariant the SQL pre-filter rests on ───────────────────────────────

@pytest.mark.parametrize("category", SECTIONS)
def test_sql_prefilter_never_drops_what_is_relevant_would_keep(category):
    """The database pre-filter must be a superset of the Python gate.

    The band query narrows rows in SQL before applying `limit`, then judges them
    again in Python. If SQL is ever *tighter* than `is_relevant`, places vanish
    with nothing downstream able to put them back — and it fails silently.
    """
    tags, _ = pb.sql_prefilter(category)
    prefilter = set(tags)
    assert prefilter, f"{category} must have a pre-filter"

    for tag in pb.allowed_tags_for(category):
        if pb.is_relevant(category, [tag], "Some Place"):
            assert tag in prefilter, (
                f"{category}: '{tag}' passes is_relevant but SQL would drop it"
            )


def test_health_sections_prefilter_admits_name_only_matches():
    """Both health sections admit places on their name when Google typed them
    vaguely, so the pre-filter has to carry name patterns too."""
    for category in ("Medical", "Hospital"):
        _, names = pb.sql_prefilter(category)
        assert names, f"{category} relies on name matching and must pre-filter on it"
        assert all(p.startswith("%") and p.endswith("%") for p in names)


# ── Nature means nature ─────────────────────────────────────────────────────

@pytest.mark.parametrize("name,tags", [
    ("Ezhilarangu Stadium", ["park", "point_of_interest"]),
    ("Lotus Tower Kids Park", ["park"]),
    ("Mahara Jogging Track", ["park"]),
    ("Bellanwila Park", ["cycling_park", "park", "sports_activity_location"]),
])
def test_urban_recreation_is_not_nature(name, tags):
    """Google files playgrounds and jogging tracks under the same generic
    `park` as a national park. Admitting it filled the section with them."""
    assert pb.is_relevant("Nature", tags, name) is False


@pytest.mark.parametrize("name,tags", [
    ("Kinniya Beach", ["beach", "natural_feature"]),
    ("Horowpathana National Park", ["national_park", "park"]),
    ("Thalangama Lake", ["lake", "natural_feature"]),
    ("Pigeon Island", ["national_park"]),
])
def test_real_nature_is_nature(name, tags):
    assert pb.is_relevant("Nature", tags, name) is True


# ── The two exclusive pairs ─────────────────────────────────────────────────

@pytest.mark.parametrize("pair", [("POI", "Nature"), ("Medical", "Hospital")])
@pytest.mark.parametrize("name,tags", [
    ("Kinniya Beach", ["beach", "natural_feature"]),
    ("Dutch Fort", ["historical_landmark", "tourist_attraction"]),
    ("Colombo General Hospital", ["hospital", "health"]),
    ("Shani Pharmacy", ["pharmacy", "store", "health"]),
    ("Ken Medi House Homeopathic Clinic", ["medical_center", "hospital"]),
])
def test_a_place_never_belongs_to_both_halves_of_a_pair(pair, name, tags):
    """Each pair is fed from one shared pool. A place satisfying both would be
    shown twice as the user scrolls across the cards."""
    left, right = pair
    assert not (
        pb.is_relevant(left, tags, name) and pb.is_relevant(right, tags, name)
    ), f"'{name}' lands in both {left} and {right}"


@pytest.mark.parametrize("name", [
    "Dr. A. S. Kokulendra Dispensary & Surgery",
    "Ken Medi House Homeopathic Clinic",
    "Warapalana Medical Center",
    "Shani Pharmacy",
])
def test_clinics_go_to_medical_even_when_google_types_them_hospital(name):
    """Google types a great many small Sri Lankan clinics as `hospital`. The
    name is the better evidence, or Medical is left with nothing to show."""
    tags = ["hospital", "health"]
    assert pb.is_relevant("Medical", tags, name) is True
    assert pb.is_relevant("Hospital", tags, name) is False


@pytest.mark.parametrize("name", ["Apeksha Hospital", "Ratnam Hospital"])
def test_actual_hospitals_go_to_hospital(name):
    tags = ["hospital", "health"]
    assert pb.is_relevant("Hospital", tags, name) is True
    assert pb.is_relevant("Medical", tags, name) is False


def test_gyms_and_yoga_are_not_medical():
    """Google hangs `health` on fitness venues as readily as on clinics."""
    tags = ["yoga_studio", "fitness_center", "gym", "health"]
    assert pb.is_relevant("Medical", tags, "Samadhi Yoga Sewana") is False
    assert pb.is_relevant("Hospital", tags, "Samadhi Yoga Sewana") is False


def test_cafes_are_not_shopping():
    """Cafés carry `store` and `food_store`, which Shopping would accept."""
    tags = ["coffee_shop", "cafe", "food_store", "store"]
    assert pb.is_relevant("Shopping", tags, "Java Lounge") is False
    assert pb.is_relevant("Food & Drink", tags, "Java Lounge") is True


def test_untyped_places_are_not_relevant_anywhere():
    """'establishment' describes a job board as readily as a museum."""
    for category in SECTIONS:
        assert pb.is_relevant(
            category, ["point_of_interest", "establishment"], "Jobbook.lk"
        ) is False


# ── Ranking ─────────────────────────────────────────────────────────────────

def test_review_volume_outweighs_a_lone_five_star():
    """A 5.0 from one review used to outrank Marble Beach's 4.4 from 1795,
    which is how nameless lakes led the Nature card."""
    marble = pb.quality_score(4.4, 1795)
    one_review = pb.quality_score(5.0, 1)
    assert marble > one_review


def test_unrated_places_score_zero():
    assert pb.quality_score(0.0, 0) == 0.0
    assert pb.quality_score(None, None) == 0.0


# ── Google types ────────────────────────────────────────────────────────────

# Verified as rejected by Places API (New). Each one makes Google 400 the whole
# request, which the client then re-issues — a second billed call every time.
KNOWN_BAD_TYPES = {
    "food", "health", "nature_reserve", "place_of_worship", "resort",
    "scenic_point", "scenic_viewpoint", "waterfall",
}


@pytest.mark.parametrize("category", sorted(CATEGORY_TYPES_MAP))
def test_no_category_requests_a_rejected_google_type(category):
    offenders = KNOWN_BAD_TYPES & set(CATEGORY_TYPES_MAP[category])
    assert not offenders, (
        f"{category} would be 400'd by Google and retried (billed twice): {offenders}"
    )


@pytest.mark.parametrize("category", sorted(pb.CATEGORY_SUBGROUPS))
def test_subgroup_types_stay_within_the_category(category):
    """Sub-groups shape Google requests for a category; a type outside that
    category's own list would fetch places the section then discards."""
    allowed = pb.allowed_tags_for(category)
    for name, types in pb.CATEGORY_SUBGROUPS[category]:
        assert set(types) <= allowed, f"{category}/{name} strays outside the category"


# ── Ordering and duplicates in the assembled response ───────────────────────
# Both of these were live bugs: bands sorted by distance meant a caller taking
# the front of a band got the nearest rather than the best, and unnamed tanks
# that Google labels with the district name filled a card with "Trincomalee"
# four times over.

def _fake(name, dist_m, rating=4.0, reviews=0, place_id=None):
    """Minimal place dict that still satisfies the PlaceResponse schema."""
    return {
        "id": place_id or f"{name}-{dist_m}",
        "name": name,
        "latitude": 8.5,
        "longitude": 81.18,
        "distance_m": float(dist_m),
        "rating": rating,
        "review_count": reviews,
        "tags": ["beach"],
        "created_at": "2026-01-01T00:00:00+00:00",
    }


def _flat(result):
    """Every band's places in display order — nearest first.

    `BandedPlacesResponse.places` used to carry this, but serialising each place
    twice doubled the response on mobile and no client ever read it, so it is
    now always empty (see the field's own docstring). These tests were asserting
    against that list, which made two of them fail and one pass vacuously on
    zero rows.
    """
    places = [p for band in result.bands for p in band.places]
    return sorted(places, key=lambda p: p.distance_m or 0.0)


def _assemble(pool, per_band=None):
    from app.services import banded_places_service as svc
    return svc._assemble(
        0.0, 0.0, "Nature", pb.bands_for("Nature"), pool, 1,
        cached_flag=False, source="test", per_band=per_band,
    )


def test_bands_are_ordered_best_first_not_nearest_first():
    """Around You takes BAND_QUOTAS off the front of each band. If bands came
    back nearest-first it would get unreviewed ponds instead of Marble Beach."""
    pool = [
        _fake("Pond A", 600, 4.0, 0),
        _fake("Pond B", 700, 4.0, 0),
        _fake("Pond C", 800, 4.0, 0),
        _fake("Pond D", 900, 4.0, 0),
        _fake("Marble Beach", 3500, 4.4, 1763),
    ]
    band0 = _assemble(pool, per_band=15).bands[0].places
    assert band0[0].name == "Marble Beach", (
        "band must lead with its best place, not its nearest"
    )


def test_flat_list_is_ordered_nearest_first_for_display():
    pool = [
        _fake("Far but great", 9000, 4.8, 5000),
        _fake("Near and plain", 500, 4.0, 3),
    ]
    places = _flat(_assemble(pool, per_band=15))
    distances = [p.distance_m for p in places]
    assert distances == sorted(distances)


def test_repeated_names_are_collapsed_to_one():
    """Google labels many unnamed tanks with only the district name."""
    pool = [_fake("Trincomalee", 600 + i * 100, place_id=f"t{i}") for i in range(5)]
    pool.append(_fake("Kinniya Beach", 2040, 4.3, 158))
    names = [p.name for p in _flat(_assemble(pool))]
    assert names.count("Trincomalee") == 1
    assert "Kinniya Beach" in names


def test_case_differences_still_count_as_the_same_name():
    """'WAWE' and 'Wawe' were showing as two entries."""
    pool = [
        _fake("WAWE", 33660, place_id="w1"),
        _fake("Wawe", 35660, place_id="w2"),
        _fake("Beybiya Wewa", 36950, place_id="w3"),
    ]
    names = [p.name.lower() for p in _flat(_assemble(pool))]
    assert names.count("wawe") == 1
