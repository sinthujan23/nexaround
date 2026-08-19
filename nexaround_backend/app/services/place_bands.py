"""Distance bands for the Around You / Discovery sections.

Each category's range is split into three contiguous bands, and the UI shows
five places from each — fifteen per section. Bands are *weighted*, not equal
thirds: for the 0–50 km categories an equal split would put everything within
16.7 km into one band, which collapses the distinction users actually care
about (walkable vs. a drive vs. a day trip).

This table is mirrored in the Flutter client at
`lib/core/constants/place_bands.dart`. Keep the two in sync — the server uses
it to decide what to fetch, the client uses it to decide what to show.
"""
from typing import Optional


PLACES_PER_BAND = 5
BANDS_PER_CATEGORY = 3
TOTAL_PER_CATEGORY = PLACES_PER_BAND * BANDS_PER_CATEGORY

# (min_m, max_m) per band, contiguous, in metres.
CATEGORY_BANDS: dict[str, list[tuple[int, int]]] = {
    "Food & Drink": [(0, 1667), (1667, 3333), (3333, 5000)],
    "POI":          [(0, 10000), (10000, 25000), (25000, 50000)],
    "Shopping":     [(0, 5000), (5000, 10000), (10000, 15000)],
    "Medical":      [(0, 10000), (10000, 25000), (25000, 50000)],
}

# Category names as they may appear in the `categories` table. Places seeded
# under an older vocabulary ('Attractions', 'Nature') still belong to POI, so
# the band queries have to match all of them or half the DB goes unseen.
CATEGORY_DB_ALIASES: dict[str, list[str]] = {
    "Food & Drink": ["Food & Drink", "Food"],
    "POI": ["POI", "Attractions", "Nature", "Experiences"],
    "Shopping": ["Shopping"],
    "Medical": ["Medical", "Hospital"],
}

# Google Nearby Search returns at most 20 results per request and ranks them by
# prominence across the WHOLE includedTypes list. POI carries ~30 types, so in a
# temple-dense area all 20 slots come back as temples and museums never surface.
# Splitting POI into sub-groups and issuing one request per sub-group makes each
# request compete only within its own theme.
#
# Only types verified as accepted by Places API (New) — see the audit note in
# google_places_client.CATEGORY_TYPES_MAP.
CATEGORY_SUBGROUPS: dict[str, list[tuple[str, list[str]]]] = {
    "POI": [
        ("heritage", [
            "tourist_attraction", "museum", "art_gallery", "historical_landmark",
            "historical_place", "cultural_landmark", "monument", "castle",
            "sculpture", "cultural_center", "visitor_center",
        ]),
        ("nature", [
            "park", "national_park", "state_park", "beach", "hiking_area",
            "botanical_garden", "garden", "wildlife_park", "wildlife_refuge",
            "lake", "river", "marina", "picnic_ground", "plaza",
        ]),
        ("worship", [
            "hindu_temple", "buddhist_temple", "church", "mosque", "synagogue",
        ]),
        ("leisure", [
            "zoo", "aquarium", "amusement_park", "water_park", "planetarium",
            "performing_arts_theater", "observation_deck", "amusement_center",
        ]),
    ],
}


def bands_for(category: Optional[str]) -> list[tuple[int, int]]:
    """Band table for a canonical category, or POI's as a sane default."""
    if category and category in CATEGORY_BANDS:
        return CATEGORY_BANDS[category]
    return CATEGORY_BANDS["POI"]


def max_radius_for(category: Optional[str]) -> int:
    return bands_for(category)[-1][1]


def db_aliases_for(category: Optional[str]) -> list[str]:
    if category and category in CATEGORY_DB_ALIASES:
        return CATEGORY_DB_ALIASES[category]
    return [category] if category else []


def subgroups_for(category: Optional[str]) -> list[tuple[str, Optional[list[str]]]]:
    """Type sub-groups to fan a band's requests across.

    Categories without an entry get a single unnamed group whose types are None,
    meaning "use the category's full CATEGORY_TYPES_MAP list as-is".
    """
    if category and category in CATEGORY_SUBGROUPS:
        return [(name, types) for name, types in CATEGORY_SUBGROUPS[category]]
    return [("all", None)]


# Legacy tags on rows seeded through the old Places API, mapped to the canonical
# category they should count towards. Without these, years of existing rows look
# untyped to the relevance gate below and get filtered out of their own section.
_LEGACY_TAG_CATEGORIES: dict[str, set[str]] = {
    "Food & Drink": {"food", "meal_takeaway", "meal_delivery"},
    "POI": {
        "natural_feature", "place_of_worship", "point_of_interest_landmark",
        "premise", "campground",
    },
    "Shopping": {"grocery_or_supermarket", "home_goods_store", "furniture_store",
                 "hardware_store", "liquor_store", "pet_store", "bicycle_store"},
    # 'health' is deliberately absent: Google hangs it on gyms, yoga studios and
    # sports clubs as readily as on clinics, and admitting it put yoga
    # institutes in the Medical section ahead of actual hospitals.
    "Medical": {"medical_center", "drugstore", "doctor", "dentist"},
}

# Tags that disqualify a place from a category even though it also carries a
# legitimate type. A tattoo studio really is a `store`, and a spa really is
# somewhere you go — but neither is what someone opening Shopping or POI is
# looking for, and both currently crowd out the places that are.
_EXCLUDED_TAGS: dict[str, set[str]] = {
    "POI": {
        "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
        "travel_agency", "real_estate_agency", "insurance_agency", "lawyer",
        "accounting", "bank", "atm", "finance", "casino", "night_club",
        "school", "primary_school", "secondary_school", "preschool", "university",
        "hospital", "doctor", "dentist", "pharmacy", "medical_clinic",
        "lodging", "hotel", "car_repair", "car_dealer", "gas_station",
        "cemetery", "funeral_home", "storage", "moving_company",
    },
    "Shopping": {
        "school", "university", "hospital", "doctor", "dentist", "spa",
        "body_art_service", "beauty_salon", "hair_care", "hair_salon",
        "bank", "atm", "finance", "lodging", "restaurant", "bar", "night_club",
        "real_estate_agency", "travel_agency", "car_repair", "car_dealer",
        # Cafés and dessert shops carry `store` and `food_store`, which the
        # Shopping type list would otherwise accept — they belong to
        # Food & Drink, and were displacing actual shops.
        "cafe", "coffee_shop", "ice_cream_shop", "dessert_shop", "bakery",
        "confectionery", "food", "food_store", "meal_takeaway", "meal_delivery",
    },
    "Medical": {
        "school", "university", "bank", "atm", "finance", "accounting",
        "restaurant", "bar", "cafe", "bakery", "food", "night_club",
        "shopping_mall", "clothing_store", "electronics_store",
        "grocery_or_supermarket", "supermarket", "lodging", "hotel",
        "real_estate_agency", "transit_station", "bus_station", "train_station",
        "tourist_attraction", "spa", "massage",
        # Fitness venues describe themselves as health services. They are not
        # where someone opening the Medical section needs to go.
        "gym", "fitness_center", "yoga_studio", "sports_school",
        "sports_complex", "sports_activity_location", "sports_club",
    },
    "Food & Drink": {
        "lodging", "hotel", "hospital", "doctor", "pharmacy", "school",
        "university", "bank", "atm", "gas_station", "car_repair",
        "shopping_mall", "department_store", "supermarket",
    },
}

# Generic Google tags that say nothing about what a place is. A row carrying
# only these is untyped in practice and must not satisfy the relevance gate.
_GENERIC_TAGS = {"point_of_interest", "establishment", "premise", "geocode"}

# Last resort for places Google itself types wrongly — a guest house tagged
# `hospital` passes every tag check there is, and only its name gives it away.
# A veto applies unless the name also carries a word from the same category, so
# "Hotel Road Pharmacy" survives while "Green path hotel" does not.
_NAME_VETOES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    # category: (disqualifying words, words that overrule the disqualification)
    "Medical": (
        ("hotel", "restaurant", "guest house", "villa", "resort", "cafe", "bar"),
        ("hospital", "clinic", "pharmacy", "medical", "dental", "dentist",
         "surgery", "dispensary", "laborator", "doctor", "ayurved", "health centre",
         "health center", "drug"),
    ),
}


def allowed_tags_for(category: Optional[str]) -> set[str]:
    """Tags that mark a place as genuinely belonging to a category.

    Derived from the same CATEGORY_TYPES_MAP that drives the Google requests, so
    the two can't drift apart, plus the legacy tags older rows still carry.
    """
    from app.services.google_places_client import CATEGORY_TYPES_MAP

    if not category:
        return set()
    allowed = set(CATEGORY_TYPES_MAP.get(category, ()))
    for _, types in CATEGORY_SUBGROUPS.get(category, ()):
        allowed |= set(types)
    allowed |= _LEGACY_TAG_CATEGORIES.get(category, set())
    return allowed


def is_relevant(category: Optional[str], tags, name: Optional[str] = None) -> bool:
    """Whether a place belongs in a category's section.

    Categories overlap in the database — POI absorbed 'Experiences', so spas and
    casinos arrive through the alias, and rows seeded years ago were filed by a
    vocabulary that no longer applies. Rather than trust the stored category, a
    place has to prove membership by its own Google types.
    """
    if not category:
        return True
    tag_set = {str(t).lower() for t in (tags or [])}

    if tag_set & _EXCLUDED_TAGS.get(category, set()):
        return False

    veto = _NAME_VETOES.get(category)
    if veto and name:
        lowered = name.lower()
        disqualifying, overrides = veto
        if any(w in lowered for w in disqualifying) and not any(
            w in lowered for w in overrides
        ):
            return False

    allowed = allowed_tags_for(category)
    if not allowed:
        return True
    # Generic tags alone are not membership — 'establishment' describes a job
    # board as readily as a museum.
    return bool((tag_set - _GENERIC_TAGS) & allowed)


def quality_score(rating: Optional[float], review_count: Optional[int]) -> float:
    """Rating shrunk toward the mean by how little it is backed up.

    A raw rating sort ranks a 5.0 from one review above a 4.7 from eight
    thousand, which is how spas with a single review ended up leading POI. This
    is the standard Bayesian shrinkage: with few reviews the score sits near the
    prior, and only real volume moves it away.
    """
    r = float(rating or 0.0)
    v = int(review_count or 0)
    if r <= 0.0:
        return 0.0
    prior_weight = 30.0
    prior_mean = 4.0
    return (v * r + prior_weight * prior_mean) / (v + prior_weight)


def _fmt_km(metres: float) -> str:
    km = metres / 1000.0
    return f"{km:.0f}" if abs(km - round(km)) < 0.05 else f"{km:.1f}"


def band_label(min_m: int, max_m: int) -> str:
    return f"{_fmt_km(min_m)}–{_fmt_km(max_m)} km"
