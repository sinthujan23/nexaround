"""Rules for ratings and reviews on experience packages.

Plain functions over plain values, like `experience_format`: no database, so the
rules most likely to break quietly (who may review, how an average is rounded,
what a hidden review leaves behind) can be tested without one.
"""
from datetime import date
from typing import Iterable, Optional

from app.services import enquiry_lifecycle

MIN_RATING = 1
MAX_RATING = 5
MAX_COMMENT_LENGTH = 1000
MAX_REPLY_LENGTH = 1000

PUBLISHED = "published"
HIDDEN = "hidden"
STATUSES = (PUBLISHED, HIDDEN)

# Statuses a review may be written under: the provider confirmed the booking
# and it was not cancelled afterwards (`closed` is how a finished trip ends up,
# but only counts if it was confirmed first; see `eligibility_error`).
REVIEWABLE_STATUSES = (enquiry_lifecycle.CONFIRMED, enquiry_lifecycle.CLOSED)


def eligibility_error(
    status: str, confirmed_date: Optional[date], today: date
) -> Optional[str]:
    """Why a traveller may not review this request yet, or None when they may.

    The rule that keeps ratings real: the provider confirmed the booking for a
    day, the day has come, and the booking was not cancelled by either side.
    """
    if status in enquiry_lifecycle.CANCELLED:
        return "A cancelled booking cannot be reviewed."
    if status not in REVIEWABLE_STATUSES or confirmed_date is None:
        return "You can review an experience once the provider has confirmed your booking and the day has passed."
    if confirmed_date > today:
        return "You can review this experience after your booked day."
    return None


def clean_comment(comment: Optional[str]) -> Optional[str]:
    """A cleared box arrives as "" and should store nothing."""
    text = (comment or "").strip()
    return text or None


def clean_reply(reply: Optional[str]) -> Optional[str]:
    return clean_comment(reply)


def reviewer_display_name(contact_name: Optional[str]) -> str:
    """"Anna Kowalski" -> "Anna K.". A review is public: first name and the
    initial of the last, never the full name or any contact detail."""
    parts = (contact_name or "").split()
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
