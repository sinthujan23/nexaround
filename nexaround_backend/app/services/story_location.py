"""Catches a travel story pinned to where its poster stood, not the place it names.

App builds released before October 2026 saved the poster's own GPS whenever
the place was typed instead of picked from the suggestions, so a "Galle Face
Green" story posted from Trincomalee showed as 9.6 km away there instead of
229 km. Those builds are still installed and the server cannot tell their
picked places from that fallback, so a story that arrives without a
`location_source` (only newer builds send one) is checked against Google.

The story is moved only when Google knows a place by that name, in the
story's own country, and nowhere near the coordinates sent. Same-name places
abroad are never used: "Sunset Point" typed in Ella matched one 15,000 km
away. A story with no country, or a name Google does not recognise, keeps
what it was sent.
"""
import asyncio
import logging
from typing import Optional

from app.services import google_places_client
from app.services.trip_cost_floor import country_for
from app.utils.place_match import haversine_m, names_match

logger = logging.getLogger(__name__)

# Closer than this to a same-name place, the story is already where it says.
# Marble Beach was 3.5 km off, so this has to stay well under that.
NEAR_ENOUGH_M = 2_000.0
# A name this short only counts when it is the whole of both names ("Ella").
_MIN_NAME_LEN = 4
# One name inside the other ("Marble Beach" in "Marble Beach - මාබල් බීච්")
# counts only when the shorter is this long or two words: "Fort" sits inside
# "Galle Fort" and a hundred other places.
_MIN_CONTAINED_LEN = 6
_LOOKUP_TIMEOUT_S = 6.0


def _covers(candidate: dict, lat: float, lng: float) -> bool:
    """The coordinates are at this place: close to its pin or inside its area."""
    if haversine_m(lat, lng, candidate["latitude"], candidate["longitude"]) <= NEAR_ENOUGH_M:
        return True
    vp = candidate.get("viewport")
    if vp:
        low_lat, low_lng, high_lat, high_lng = vp
        if low_lat <= lat <= high_lat and low_lng <= lng <= high_lng:
            return True
    return False


def _same_name(story_name: str, place_name: str) -> bool:
    a = " ".join(story_name.lower().split())
    b = " ".join(place_name.lower().split())
    if a == b:
        return len(a) >= _MIN_NAME_LEN
    shorter = min(a, b, key=len)
    if len(shorter) < _MIN_CONTAINED_LEN and len(shorter.split()) < 2:
        return False
    return names_match(a, b)


def pick_correction(
    name: str,
    country: Optional[str],
    lat: float,
    lng: float,
    candidates: list[dict],
) -> Optional[dict]:
    """The candidate a story should move to, or None to keep its coordinates."""
    if any(_covers(c, lat, lng) for c in candidates):
        return None
    want = (country_for(country or "") or "").upper()
    if not want:
        return None
    for c in candidates:
        if c.get("country_code") == want and _same_name(name, c["name"]):
            return c
    return None


async def corrected_location(
    name: str,
    country: Optional[str],
    lat: Optional[float],
    lng: Optional[float],
) -> Optional[tuple[float, float]]:
    """Where the named place really is, when the sent coordinates are elsewhere.

    None means keep the coordinates as sent, including whenever Google is
    unreachable: a slow lookup must never block or fail a post.
    """
    if lat is None or lng is None or not (name or "").strip() or not country:
        return None
    try:
        candidates = await asyncio.wait_for(
            google_places_client.find_place_candidates(name, bias_lat=lat, bias_lng=lng),
            timeout=_LOOKUP_TIMEOUT_S,
        )
    except Exception as e:
        logger.warning("story location check failed for %r: %s", name, e)
        return None
    match = pick_correction(name, country, lat, lng, candidates)
    if not match:
        return None
    logger.info(
        "story %r moved from (%.5f, %.5f) to %r (%.5f, %.5f)",
        name, lat, lng, match["name"], match["latitude"], match["longitude"],
    )
    return match["latitude"], match["longitude"]
