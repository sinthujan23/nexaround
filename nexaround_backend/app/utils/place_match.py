"""When two place records describe the same real place.

The seeders' rule, written once for the code that needs it outside the
seeding loops (visibility filter, tombstone check, duplicate merge): closer
than 25 m, and one lowercase name contains the other.
"""
import math

SAME_PLACE_M = 25.0


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371000.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlng / 2) ** 2)
    return 2 * r * math.asin(math.sqrt(a))


def names_match(a: str, b: str) -> bool:
    a = (a or "").strip().lower()
    b = (b or "").strip().lower()
    if not a or not b:
        return False
    return a in b or b in a


def is_same_place(
    lat1: float, lng1: float, name1: str,
    lat2: float, lng2: float, name2: str,
) -> bool:
    return (
        haversine_m(lat1, lng1, lat2, lng2) < SAME_PLACE_M
        and names_match(name1, name2)
    )
