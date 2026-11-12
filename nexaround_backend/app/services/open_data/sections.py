"""Which of our sections an open-data place belongs to, and download areas.

Only sections whose Overture coverage was found good (2026-11-12 check of
Da Nang / Hoi An: restaurants, hotels, shops, museums, hospitals all present;
Dragon Bridge, My Khe Beach, Marble Mountains missing and the Japanese Covered
Bridge filed as a restaurant) are served from free data. Sights stay on Google.
"""
from __future__ import annotations

import math
from typing import Optional

OPEN_SECTIONS: tuple[str, ...] = ("Food & Drink", "Shopping", "Hotels", "Medical", "Hospital")

# Overture taxonomy top levels worth downloading at all.
IMPORT_TOP_LEVELS: tuple[str, ...] = ("food_and_drink", "shopping", "lodging", "health_care")

TILE_DEG = 0.5


def section_for(hierarchy: Optional[list], basic_category: Optional[str]) -> Optional[str]:
    """Our section for an Overture place, or None to leave it out."""
    h = [str(x) for x in (hierarchy or []) if x]
    top = h[0] if h else None
    second = h[1] if len(h) > 1 else None
    basic = (basic_category or "").lower()
    if basic == "hospital" or second == "hospital":
        return "Hospital"
    # Pharmacies sit under shopping > specialty_store in Overture; to a
    # traveller they are medical.
    if basic == "pharmacy_and_drug_store" or "pharmacy" in h or "pharmacy_and_drug_store" in h:
        return "Medical"
    if top == "health_care":
        return "Medical"
    if top == "food_and_drink":
        return "Food & Drink"
    if top == "lodging":
        return None if second == "rv_park" else "Hotels"
    if top == "shopping":
        return None if second == "vehicle_dealer" else "Shopping"
    return None


def tags_for(section: str, basic_category: Optional[str]) -> list[str]:
    """Google-style type tags, so code written for Google places (the Medical
    pharmacy / clinic / other mix, icons in the app) treats these alike."""
    b = (basic_category or "").lower()
    if section == "Hospital":
        return ["hospital"]
    if section == "Medical":
        if "pharmac" in b or "drug" in b:
            return ["pharmacy"]
        if "dent" in b:
            return ["dentist"]
        if "physical" in b or "physio" in b or "chiropract" in b:
            return ["physiotherapist"]
        if "lab" in b or "diagnostic" in b:
            return ["medical_lab"]
        return ["medical_clinic"]
    if section == "Food & Drink":
        if b in ("bar", "pub") or b.endswith("_bar") or b.endswith("_pub") or (
            "alcoholic" in b and "non_alcoholic" not in b
        ):
            return ["bar"]
        if "coffee" in b or "cafe" in b or "tea" in b or "non_alcoholic" in b:
            return ["cafe"]
        if "bakery" in b:
            return ["bakery"]
        return ["restaurant"]
    if section == "Hotels":
        if "hostel" in b:
            return ["hostel"]
        if "camp" in b:
            return ["campground"]
        return ["lodging"]
    if section == "Shopping":
        if "mall" in b:
            return ["shopping_mall"]
        if "market" in b or "supermarket" in b or "grocery" in b or "food_and_beverage" in b:
            return ["supermarket"]
        if "convenience" in b:
            return ["convenience_store"]
        return ["store"]
    return []


# ── Download areas ──────────────────────────────────────────────────────────

def _floor(v: float) -> float:
    return math.floor(v / TILE_DEG) * TILE_DEG


def tile_of(lat: float, lng: float) -> str:
    return f"{_floor(lat):.1f}_{_floor(lng):.1f}"


def tile_bbox(tile: str) -> tuple[float, float, float, float]:
    """(lat_min, lng_min, lat_max, lng_max) of a tile."""
    a, b = tile.split("_")
    lat0, lng0 = float(a), float(b)
    return lat0, lng0, lat0 + TILE_DEG, lng0 + TILE_DEG


def tiles_for_circle(lat: float, lng: float, radius_m: float) -> list[str]:
    """Every tile a circle touches (a 50 km radius touches up to 9)."""
    dlat = radius_m / 111_320.0
    dlng = radius_m / (111_320.0 * max(0.1, math.cos(math.radians(lat))))
    lat0, lat1 = _floor(max(-90.0, lat - dlat)), _floor(min(89.999, lat + dlat))
    lng0, lng1 = _floor(max(-180.0, lng - dlng)), _floor(min(179.999, lng + dlng))
    out = []
    a = lat0
    while a <= lat1 + 1e-9:
        b = lng0
        while b <= lng1 + 1e-9:
            out.append(f"{a:.1f}_{b:.1f}")
            b += TILE_DEG
        a += TILE_DEG
    return out


def version_at_least(version: Optional[str], minimum: Optional[str]) -> bool:
    """'1.0.18' >= '1.0.18'. No minimum set = everyone; no version = old build."""
    if not minimum:
        return True
    if not version:
        return False

    def parts(v: str) -> list[int]:
        out = []
        for p in v.split("+")[0].split("."):
            digits = "".join(ch for ch in p if ch.isdigit())
            out.append(int(digits) if digits else 0)
        return out + [0] * (4 - len(out))

    return parts(version) >= parts(minimum)
