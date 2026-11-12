"""Our popularity score for free-data places (no Google ratings), 0..100.

Worked out ahead of time (on download, and nightly for our users' part) and
saved with the place, so serving only sorts on a stored number.

Overture lists each place under exactly one source company, so "how many
companies list it" carries no signal and is not used.
"""
from __future__ import annotations

from typing import Optional


def popularity_score(
    *,
    confidence: Optional[float],
    website: Optional[str] = None,
    phone: Optional[str] = None,
    social: Optional[str] = None,
    brand: Optional[str] = None,
    wiki_views: int = 0,
    our_points: int = 0,
) -> int:
    c = max(0.0, min(1.0, float(confidence or 0.0)))
    score = round(c * 40)            # how sure we are it exists and is open
    if website:
        score += 15                  # an active business keeps a website
    if phone:
        score += 10
    if social:
        score += 10
    if brand:
        score += 10                  # a chain people recognise
    if wiki_views >= 10000:
        score += 15                  # famous (Wikipedia article, many readers)
    elif wiki_views >= 1000:
        score += 10
    elif wiki_views >= 100:
        score += 5
    score += max(0, min(10, int(our_points or 0)))   # our users open it
    return max(0, min(100, score))


def label_for(*, wiki_views: int = 0, our_points: int = 0, score: int = 0) -> Optional[str]:
    """The small chip free users see instead of stars, or None."""
    if wiki_views >= 1000 and score >= 60:
        return "Famous"
    if our_points >= 5:
        return "Popular with travellers"
    return None
