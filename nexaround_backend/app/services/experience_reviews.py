"""Rules for ratings and reviews on experience packages.

Plain functions over plain values, like `experience_format`: no database, so the
rules most likely to break quietly (how an average is rounded, what a reviewer's
name looks like, what a hidden review leaves behind) can be tested without one.
"""
from typing import Iterable, Optional

MIN_RATING = 1
MAX_RATING = 5
MAX_COMMENT_LENGTH = 1000
MAX_REPLY_LENGTH = 1000

PUBLISHED = "published"
HIDDEN = "hidden"
STATUSES = (PUBLISHED, HIDDEN)


def clean_comment(comment: Optional[str]) -> Optional[str]:
    """A cleared box arrives as "" and should store nothing."""
    text = (comment or "").strip()
    return text or None


def clean_reply(reply: Optional[str]) -> Optional[str]:
    return clean_comment(reply)


def reviewer_display_name(name: Optional[str]) -> str:
    """"Anna Kowalski" -> "Anna K.". A review is public: first name and the
    initial of the last, never the full name or any contact detail."""
    parts = (name or "").split()
    if not parts:
        return "Traveller"
    first = parts[0][:30]
    if len(parts) == 1:
        return first
    return f"{first} {parts[-1][0].upper()}."


def summarize(ratings: Iterable[int]) -> dict:
    """Average (one decimal), count and a 1-5 breakdown. `average` is None with
    no ratings, so a package nobody has rated shows no stars rather than 0."""
    breakdown = {star: 0 for star in range(MIN_RATING, MAX_RATING + 1)}
    total = 0
    count = 0
    for rating in ratings:
        if rating in breakdown:
            breakdown[rating] += 1
            total += rating
            count += 1
    return {
        "average": round_average(total, count),
        "count": count,
        "breakdown": breakdown,
    }


def round_average(total: float, count: int) -> Optional[float]:
    """One decimal, halves rounding up (4.25 -> 4.3), which Python's round()
    does not do on its own."""
    if not count:
        return None
    return int(total / count * 10 + 0.5 + 1e-9) / 10
