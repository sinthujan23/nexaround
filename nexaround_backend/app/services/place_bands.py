"""Distance bands for the Around You / Discovery sections.

Each category's range is split into three contiguous bands, and the UI takes a
quota from each — ten per section. Bands are *weighted*, not equal thirds: for
the 0–50 km categories an equal split would put everything within 16.7 km into
one band, which collapses the distinction users actually care about (walkable
vs. a drive vs. a day trip).

Six categories share this table. POI/Nature and Hospital/Medical are two
*exclusive pairs*: each pair is fed from one shared pool of database rows and
split by Google type, not by the category a row happens to be filed under. That
is not a stylistic choice — 3002 of the rows carrying a `hospital` type are
filed under 'Medical' and only 1068 under 'Hospital', and 1471 parks and beaches
are filed under 'Attractions'. Splitting on the stored category name would open
both new sections nearly empty and leave the old two unchanged.

This table is mirrored in the Flutter client at
`lib/core/constants/place_bands.dart`. Keep the two in sync — the server uses
it to decide what to fetch, the client uses it to decide what to show.
"""
import re
from typing import Optional


# Places taken from each band, nearest band first. Weighted rather than even
# because ten does not divide by three, and because the band a user can walk to
# is the one they actually read.
BAND_QUOTAS: tuple[int, ...] = (4, 3, 3)
BANDS_PER_CATEGORY = len(BAND_QUOTAS)
TOTAL_PER_CATEGORY = sum(BAND_QUOTAS)


def quota_for_band(index: int) -> int:
    """How many places band `index` contributes to its section."""
    if 0 <= index < len(BAND_QUOTAS):
        return BAND_QUOTAS[index]
    return BAND_QUOTAS[-1]


# (min_m, max_m) per band, contiguous, in metres.
CATEGORY_BANDS: dict[str, list[tuple[int, int]]] = {
    "Food & Drink": [(0, 1667), (1667, 3333), (3333, 5000)],
    "POI":          [(0, 10000), (10000, 25000), (25000, 50000)],
    "Nature":       [(0, 10000), (10000, 25000), (25000, 50000)],
    "Shopping":     [(0, 5000), (5000, 10000), (10000, 15000)],
    "Medical":      [(0, 10000), (10000, 25000), (25000, 50000)],
    "Hospital":     [(0, 10000), (10000, 25000), (25000, 50000)],
}

# Category names as they may appear in the `categories` table. These are
# *candidate pools*, not answers: rows were filed under several vocabularies over
# the years, so each half of an exclusive pair claims the whole shared pool and
# `is_relevant` decides which places actually belong to it.
CATEGORY_DB_ALIASES: dict[str, list[str]] = {
    "Food & Drink": ["Food & Drink", "Food"],
    "POI": ["POI", "Point of Interest", "Attractions", "Experiences",
            "Nature", "Beach"],
    "Nature": ["Nature", "Beach", "Attractions", "POI", "Point of Interest",
               "Experiences"],
    "Shopping": ["Shopping"],
    "Medical": ["Medical", "Hospital"],
    "Hospital": ["Hospital", "Medical"],
}

# Google Nearby Search returns at most 20 results per request and ranks them by
# prominence across the WHOLE includedTypes list. POI carries ~20 types, so in a
# temple-dense area all 20 slots come back as temples and museums never surface.
# Splitting a category into sub-groups and issuing one request per sub-group
# makes each request compete only within its own theme.
#
# Only categories that genuinely crowd themselves out get sub-groups — each one
# costs an extra billed request per band. Medical and Hospital have none: with
# hospitals split off, neither type list is broad enough to starve itself.
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
        ("worship", [
            "hindu_temple", "buddhist_temple", "church", "mosque", "synagogue",
        ]),
        ("leisure", [
            "zoo", "aquarium", "amusement_park", "water_park", "planetarium",
            "performing_arts_theater", "observation_deck", "amusement_center",
        ]),
    ],
    "Nature": [
        # `park`, `garden`, `picnic_ground` and `marina` are deliberately absent.
        # allowed_tags_for() unions these sub-group types into the relevance
        # gate, so listing the generic types here would re-admit every kids'
        # park and jogging track that narrowing CATEGORY_TYPES_MAP just removed.
        # Genuine reserves still qualify through national_park/state_park.
        ("green", [
            "national_park", "state_park", "botanical_garden",
            "hiking_area", "wildlife_park", "wildlife_refuge",
        ]),
        ("water", ["beach", "lake", "river"]),
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


# ── Exclusive pairs ─────────────────────────────────────────────────────────
# Types that make a place Nature rather than POI. Kept in one set here rather
# than read back out of CATEGORY_SUBGROUPS: the sub-groups exist to shape Google
# requests, and the two lists are free to diverge.
_NATURE_TYPES = {
    "park", "national_park", "state_park", "beach", "hiking_area",
    "botanical_garden", "garden", "wildlife_park", "wildlife_refuge",
    "lake", "river", "marina", "picnic_ground", "natural_feature", "campground",
}

# Heritage strong enough to keep a place in POI even when it also carries a
# nature type. A museum inside a botanical garden is somewhere you go to see the
# museum; a park that Google also tagged `tourist_attraction` is still a park.
_HERITAGE_OVERRIDES = {
    "museum", "art_gallery", "historical_landmark", "historical_place",
    "cultural_landmark", "monument", "castle", "sculpture", "cultural_center",
    "hindu_temple", "buddhist_temple", "church", "mosque", "synagogue",
}

_HOSPITAL_TYPES = {"hospital"}

# Google types plenty of real hospitals as nothing more specific than
# `medical_clinic`, so the name has to be able to admit one on its own.
_HOSPITAL_NAME_WORDS = ("hospital", "nursing home", "infirmary")

# ...and the reverse is just as common: Google types small dispensaries, chemists
# and one-room clinics as `hospital` too. When the name says what the place
# actually is, it outranks the type — otherwise every pharmacy and clinic in the
# country lands in Hospital and the Medical section has nothing left to show.
_CLINIC_NAME_WORDS = (
    "pharmacy", "pharmacies", "chemist", "drug store", "drugstore",
    "clinic", "dispensary", "dental", "dentist", "laborator",
    "medical centre", "medical center", "surgery", "ayurved",
)


def _sibling_owns(category: str, tag_set: set[str], lowered_name: str) -> bool:
    """Whether the other half of an exclusive pair is this place's real home.

    Each pair is fed from one shared pool, so a place that satisfies both halves
    has to be pushed to exactly one of them or it appears twice across the six
    sections. Only the losing side of each rule needs an entry here: Nature wins
    the nature types, POI wins them back on heritage, and Hospital always wins
    over Medical.
    """
    if category == "POI":
        return bool(tag_set & _NATURE_TYPES) and not (tag_set & _HERITAGE_OVERRIDES)
    if category == "Nature":
        return bool(tag_set & _HERITAGE_OVERRIDES)
    if category == "Medical":
        # A name that says pharmacy, clinic or dispensary settles it: Medical
        # keeps the place regardless of the `hospital` type Google hung on it.
        if _reads_as_clinic(lowered_name):
            return False
        return bool(tag_set & _HOSPITAL_TYPES) or any(
            w in lowered_name for w in _HOSPITAL_NAME_WORDS
        )
    if category == "Hospital":
        # The same rule seen from the other side, so the pair stays exclusive.
        return _reads_as_clinic(lowered_name)
    return False


def _reads_as_clinic(lowered_name: str) -> bool:
    """Name describes everyday care rather than a hospital.

    'Colombo General Hospital Pharmacy' names both; the hospital wins, because
    the department belongs to the institution people are looking for.
    """
    if not lowered_name:
        return False
    if any(w in lowered_name for w in _HOSPITAL_NAME_WORDS):
        return False
    return any(w in lowered_name for w in _CLINIC_NAME_WORDS)


# Legacy tags on rows seeded through the old Places API, mapped to the canonical
# category they should count towards. Without these, years of existing rows look
# untyped to the relevance gate below and get filtered out of their own section.
_LEGACY_TAG_CATEGORIES: dict[str, set[str]] = {
    "Food & Drink": {"food", "meal_takeaway", "meal_delivery"},
    "POI": {"place_of_worship", "point_of_interest_landmark", "premise"},
    "Nature": {"natural_feature", "campground"},
    "Shopping": {"grocery_or_supermarket", "home_goods_store", "furniture_store",
                 "hardware_store", "liquor_store", "pet_store", "bicycle_store"},
    # 'health' is deliberately absent: Google hangs it on gyms, yoga studios and
    # sports clubs as readily as on clinics, and admitting it put yoga
    # institutes in the Medical section ahead of actual hospitals.
    "Medical": {"medical_center", "drugstore", "doctor", "dentist"},
    "Hospital": {"medical_center"},
}

# Everything a health section must never show. Shared by Medical and Hospital —
# the two split by what they admit, not by what they reject.
_NON_HEALTH_TAGS = {
    "school", "university", "bank", "atm", "finance", "accounting",
    "restaurant", "bar", "cafe", "bakery", "food", "night_club",
    "shopping_mall", "clothing_store", "electronics_store",
    "grocery_or_supermarket", "supermarket", "lodging", "hotel",
    "real_estate_agency", "transit_station", "bus_station", "train_station",
    "tourist_attraction", "spa", "massage",
    # Fitness venues describe themselves as health services. They are not
    # where someone opening Medical or Hospital needs to go.
    "gym", "fitness_center", "yoga_studio", "sports_school",
    "sports_complex", "sports_activity_location", "sports_club",
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
    # Beach resorts and safari lodges carry `beach` and `wildlife_park` next to
    # `lodging`, and would otherwise fill the section with places to sleep.
    "Nature": {
        "spa", "beauty_salon", "hair_care", "massage", "casino", "night_club",
        "lodging", "hotel", "resort_hotel", "guest_house", "motel", "hostel",
        "bed_and_breakfast", "restaurant", "bar", "cafe",
        "travel_agency", "real_estate_agency", "insurance_agency",
        "bank", "atm", "finance", "school", "university",
        "hospital", "doctor", "dentist", "pharmacy", "medical_clinic",
        "car_repair", "car_dealer", "gas_station", "cemetery", "funeral_home",
        "gym", "fitness_center", "sports_complex", "shopping_mall", "store",
        # Urban recreation. Google files playgrounds, jogging tracks and cycling
        # parks under the same generic `park` as a national park, which is how
        # Lotus Tower Kids Park and Mahara Jogging Track reached this section.
        "city_park", "cycling_park", "dog_park", "playground", "skateboard_park",
        "athletic_field", "stadium", "ice_skating_rink", "sports_activity_location",
        "amusement_park", "water_park", "amusement_center",
    },
    "Shopping": {
        "school", "university", "hospital", "doctor", "dentist", "spa",
        "pharmacy", "drugstore", "medical_clinic",
        "body_art_service", "beauty_salon", "hair_care", "hair_salon",
        "bank", "atm", "finance", "lodging", "restaurant", "bar", "night_club",
        "real_estate_agency", "travel_agency", "car_repair", "car_dealer",
        # Cafés and dessert shops carry `store` and `food_store`, which the
        # Shopping type list would otherwise accept — they belong to
        # Food & Drink, and were displacing actual shops.
        "cafe", "coffee_shop", "ice_cream_shop", "dessert_shop", "bakery",
        "confectionery", "food", "food_store", "meal_takeaway", "meal_delivery",
    },
    "Medical": _NON_HEALTH_TAGS,
    "Hospital": _NON_HEALTH_TAGS,
    "Food & Drink": {
        "lodging", "hotel", "hospital", "doctor", "pharmacy", "school",
        "university", "bank", "atm", "gas_station", "car_repair",
        "shopping_mall", "department_store", "supermarket",
    },
}

# Generic Google tags that say nothing about what a place is. A row carrying
# only these is untyped in practice and must not satisfy the relevance gate.
_GENERIC_TAGS = {"point_of_interest", "establishment", "premise", "geocode"}

# What counts as a mall for Shopping's priority pass. Kept narrow on purpose:
# a supermarket or a hardware shop is a shop, not the destination the section
# is meant to lead with.
_MALL_TYPES = {"shopping_mall", "department_store"}

# Last resort for places Google itself types wrongly — a guest house tagged
# `hospital` passes every tag check there is, and only its name gives it away.
# A veto applies unless the name also carries a word from the same category, so
# "Hotel Road Pharmacy" survives while "Green path hotel" does not.
_HEALTH_NAME_VETO = (
    ("hotel", "restaurant", "guest house", "villa", "resort", "cafe", "bar"),
    ("hospital", "clinic", "pharmacy", "medical", "dental", "dentist",
     "surgery", "dispensary", "laborator", "doctor", "ayurved", "health centre",
     "health center", "drug", "nursing home"),
)

_NAME_VETOES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    # category: (disqualifying words, words that overrule the disqualification)
    "Medical": _HEALTH_NAME_VETO,
    "Hospital": _HEALTH_NAME_VETO,
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
    lowered = (name or "").lower()

    if tag_set & _EXCLUDED_TAGS.get(category, set()):
        return False

    veto = _NAME_VETOES.get(category)
    if veto and lowered:
        disqualifying, overrides = veto
        if any(w in lowered for w in disqualifying) and not any(
            w in lowered for w in overrides
        ):
            return False

    if _sibling_owns(category, tag_set, lowered):
        return False

    # A place named for what it is outranks a place Google typed vaguely: plenty
    # of real hospitals carry nothing narrower than `medical_clinic`.
    if category == "Hospital" and any(w in lowered for w in _HOSPITAL_NAME_WORDS):
        return True
    # Same courtesy for everyday care: a dispensary Google typed only `hospital`
    # carries no tag the Medical list accepts, and would otherwise fall through
    # both health sections and disappear entirely.
    if category == "Medical" and _reads_as_clinic(lowered):
        return True

    allowed = allowed_tags_for(category)
    if not allowed:
        return True
    # Generic tags alone are not membership — 'establishment' describes a job
    # board as readily as a museum.
    return bool((tag_set - _GENERIC_TAGS) & allowed)


def sql_prefilter(category: Optional[str]) -> tuple[list[str], list[str]]:
    """Cheap database-side pre-filter for a category: (tags, name patterns).

    Exists because the band queries pull from a pool shared across categories —
    Nature's rows sit among POI's, Medical's among Hospital's — and the row limit
    used to be applied *before* relevance was judged. In a temple-dense area the
    forty nearest rows were all temples, so Nature survived the filter with one
    place while 133 real ones sat further down the list, never looked at.

    Filtering here makes the limit count only plausible rows. This is a
    deliberately loose net: it must never drop something `is_relevant` would have
    kept, because nothing downstream can put a row back. Hence the extra tags,
    and the name patterns for the two health sections, which admit places on
    their name alone when Google typed them vaguely.

    Returns empty lists for unknown categories, meaning "do not filter".
    """
    if not category:
        return [], []

    tags = set(allowed_tags_for(category))
    if not tags:
        return [], []

    names: list[str] = []
    if category == "Medical":
        # is_relevant admits a clinic on its name even when the only type Google
        # gave it is `hospital`, so both have to survive the pre-filter.
        tags |= {"hospital", "health", "medical_center"}
        names = [f"%{w}%" for w in _CLINIC_NAME_WORDS]
    elif category == "Hospital":
        tags |= {"medical_clinic", "health", "medical_center"}
        names = [f"%{w}%" for w in _HOSPITAL_NAME_WORDS]

    return sorted(tags), names


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


# A place with genuinely this many reviews is prominent regardless of how its
# average rating shook out — accumulating that much engagement takes real
# footfall. Without an absolute floor, "most-reviewed in a sparse area" would
# grant priority to a place with three reviews, which proves nothing.
_PRIORITY_MIN_REVIEWS = 200
_PRIORITY_TOP_N = 2


def priority_ids_for_band(category: Optional[str], band_places: list[dict]) -> set[str]:
    """Ids to guarantee a slot in their band ahead of pure quality_score order.

    Two independent routes in, either sufficient on its own:
      - Name: a place whose name marks it as a primary institution (reuses
        _HOSPITAL_NAME_WORDS — Hospital only for now, the one section with an
        established name-vocabulary for this).
      - Review volume: among the band's most-reviewed places by raw count,
        provided that count clears an absolute floor.

    Both exist because quality_score's Bayesian shrinkage rewards *being
    highly rated*, not *being significant* — a high-traffic institution with
    thousands of reviews but a middling average (people complain about wait
    times at a busy public hospital) can score below a small clinic with fifty
    near-perfect reviews, even though the review count alone is strong
    evidence of which one people actually go to.
    """
    ids: set[str] = set()

    if category == "Hospital":
        for p in band_places:
            pid = str(p.get("id") or "")
            name = (p.get("name") or "").lower()
            if pid and any(w in name for w in _HOSPITAL_NAME_WORDS):
                ids.add(pid)

    # A mall is the thing people mean by "shopping" in a city, and it is one
    # place standing in for the hundred shops inside it — several of which are
    # in this table separately and compete with it for the same slots. Google
    # tags it `shopping_mall` and nothing else useful, so it carries no signal
    # this section would otherwise rank on.
    if category == "Shopping":
        for p in band_places:
            pid = str(p.get("id") or "")
            tags = {str(t).lower() for t in (p.get("tags") or [])}
            if pid and tags & _MALL_TYPES:
                ids.add(pid)

    ranked_by_reviews = sorted(
        band_places, key=lambda p: p.get("review_count") or 0, reverse=True
    )
    for p in ranked_by_reviews[:_PRIORITY_TOP_N]:
        if (p.get("review_count") or 0) >= _PRIORITY_MIN_REVIEWS:
            pid = str(p.get("id") or "")
            if pid:
                ids.add(pid)

    return ids


def matches_excluded_keyword(name: Optional[str], keywords: list[str]) -> bool:
    """Whether an admin-managed keyword hits this place's name, whole-word only.

    Whole-word so a short keyword like "pond" hides "Pond View" without also
    catching "Pondicherry Cafe". `keywords` comes from `excluded_keyword_service`
    and only ever affects the Around You cards — see
    `banded_places_service.get_nearby_banded`.
    """
    if not name or not keywords:
        return False
    return any(
        re.search(rf"\b{re.escape(kw)}\b", name, re.IGNORECASE)
        for kw in keywords if kw
    )


def _fmt_km(metres: float) -> str:
    km = metres / 1000.0
    return f"{km:.0f}" if abs(km - round(km)) < 0.05 else f"{km:.1f}"


def band_label(min_m: int, max_m: int) -> str:
    return f"{_fmt_km(min_m)}–{_fmt_km(max_m)} km"
