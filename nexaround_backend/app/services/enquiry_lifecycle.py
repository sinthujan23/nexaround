"""The life of an experience request, and the 72-hour cancellation rule.

    new ─▶ contacted ─▶ confirmed ─▶ closed
     │         │            │
     └─────────┴────────────┴─▶ customer_cancelled | provider_cancelled

A request becomes a booking only when the provider marks it confirmed, with a
date. Until then the traveller can always cancel for free; after it, the
Experience Booking Terms make a cancellation inside 72 hours "late". Neither
cancellation can be undone by the vendor: they are the record.

Requests carry a date but no start time, and no time zone. So the free period
is counted from the start of the booked day (the earliest an experience on it
can start): it ends at the end of the day three days before. The app shows
that day in the traveller's own calendar; `is_late_cancellation` is
deliberately lenient (the day ends at its latest anywhere on earth), so the
server never calls a cancellation late that the app showed as free.
"""

from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

NEW = "new"
CONTACTED = "contacted"
CONFIRMED = "confirmed"
CLOSED = "closed"
CUSTOMER_CANCELLED = "customer_cancelled"
PROVIDER_CANCELLED = "provider_cancelled"

ALL_STATUSES = (NEW, CONTACTED, CONFIRMED, CLOSED, CUSTOMER_CANCELLED, PROVIDER_CANCELLED)
# A vendor cannot say the traveller cancelled: only the traveller's own
# cancellation, with its timestamp, may record that.
VENDOR_STATUSES = (NEW, CONTACTED, CONFIRMED, CLOSED, PROVIDER_CANCELLED)
CANCELLED = (CUSTOMER_CANCELLED, PROVIDER_CANCELLED)
CUSTOMER_CAN_CANCEL = (NEW, CONTACTED, CONFIRMED)

FREE_CANCELLATION_HOURS = 72

# How each side reads a status. The partner portal and the admin panel keep
# their own copies of the vendor wording (format.js).
VENDOR_LABELS = {
    NEW: "New",
    CONTACTED: "Contacted",
    CONFIRMED: "Confirmed",
    CLOSED: "Closed",
    CUSTOMER_CANCELLED: "Cancelled by traveller",
    PROVIDER_CANCELLED: "Cancelled by provider",
    "spam": "Spam",
}


def free_cancellation_last_day(booked: Optional[date]) -> Optional[date]:
    """The last day a confirmed booking can be cancelled for free, or None.

    72 hours before the start of the booked day is the start of the day three
    days earlier, so the free period runs to the end of the day before that.
    """
    if booked is None:
        return None
    return booked - timedelta(days=FREE_CANCELLATION_HOURS // 24)


def is_late_cancellation(
    status_before: str, booked: Optional[date], cancelled_at: datetime
) -> bool:
    """Whether a traveller's cancellation fell inside the 72 hours.

    Only a confirmed booking can be cancelled late. The last free day is taken
    to end at its latest anywhere (UTC-12), i.e. noon UTC the next day.
    """
    last = free_cancellation_last_day(booked)
    if status_before != CONFIRMED or last is None:
        return False
    deadline = datetime.combine(last + timedelta(days=1), time(12, 0), tzinfo=timezone.utc)
    return cancelled_at >= deadline


def customer_cancel_error(status: str) -> Optional[str]:
    """None if the traveller may cancel a request in this status."""
    if status in CANCELLED:
        return "This request has already been cancelled."
    if status not in CUSTOMER_CAN_CANCEL:
        return "This request is closed and can no longer be cancelled."
    return None


def booked_date(enquiry, sent: Optional[date] = None) -> Optional[date]:
    """The day a confirmation would be for: the date the vendor just sent, else
    the one already confirmed, else the traveller's preferred date."""
    return sent or enquiry.confirmed_date or enquiry.preferred_date


def apply_status(
    enquiry,
    new: str,
    *,
    now: datetime,
    confirmed_date: Optional[date] = None,
    reason: Optional[str] = None,
) -> Optional[str]:
    """Move `enquiry` to `new` and stamp the booking fields.

    Returns the event the other side must hear about (CONFIRMED, or one of the
    cancellations), or None. Whether the move is allowed is the caller's
    check: `vendor_status_error` or `customer_cancel_error`.
    """
    before = enquiry.status
    event = None

    if new == CONFIRMED:
        booked = booked_date(enquiry, confirmed_date)
        # A new confirmation, or the day moved: either way the traveller needs
        # to hear the date.
        if before != CONFIRMED or booked != enquiry.confirmed_date:
            event = CONFIRMED
        enquiry.confirmed_date = booked
        if before != CONFIRMED:
            enquiry.confirmed_at = now

    if new in CANCELLED and before != new:
        enquiry.cancelled_at = now
        enquiry.cancellation_reason = (reason or "").strip() or None
        enquiry.late_cancellation = (
            is_late_cancellation(before, enquiry.confirmed_date, now)
            if new == CUSTOMER_CANCELLED else None
        )
        event = new
    elif before in CANCELLED and new not in CANCELLED:
        # Only an admin can reopen a cancelled request; it is no longer one.
        enquiry.cancelled_at = None
        enquiry.cancellation_reason = None
        enquiry.late_cancellation = None

    enquiry.status = new
    return event


def vendor_status_error(
    current: str, new: str, booked: Optional[date]
) -> Optional[str]:
    """None if a vendor may move a request from `current` to `new`.

    `booked` is the date the booking would be confirmed for: the one the vendor
    sent, else the traveller's preferred date.
    """
    if new not in VENDOR_STATUSES:
        return f"Status must be one of: {', '.join(VENDOR_STATUSES)}"
    if current in CANCELLED and new != current:
        return "This request was cancelled and can no longer be changed."
    if new == CONFIRMED and booked is None:
        return "Choose the date you confirmed with the traveller."
    return None


# --- The vendor's answer ------------------------------------------------------
#
# The vendor sees a request as package, date, guests and price only, and
# answers it from the portal. Confirming and cancelling move the status as an
# admin's would (and tell everyone); offering another date leaves the request
# open for NexAround to take that date to the traveller. No other vendor is
# offered: if no other date works, the vendor cancels.

VENDOR_CONFIRMED = "confirmed"
VENDOR_OTHER_DATE = "other_date"
VENDOR_CANCELLED = "cancelled"
VENDOR_RESPONSES = (VENDOR_CONFIRMED, VENDOR_OTHER_DATE, VENDOR_CANCELLED)

# A request the vendor can still answer.
VENDOR_CAN_RESPOND = (NEW, CONTACTED)

# Why the vendor cannot do the date asked. Only this label reaches the
# traveller (as a cancellation reason); the vendor's free note goes to
# NexAround alone, since free text can carry a phone number.
DECLINE_REASONS = {
    "fully_booked": "Fully booked that day",
    "weather": "Weather or sea conditions",
    "not_running": "Not running that day",
    "other": "Other reason",
}


def vendor_response_error(
    enquiry, action: str, when: Optional[date], reason: Optional[str], today: date,
) -> Optional[str]:
    """None if the vendor may answer `enquiry` this way."""
    if action not in VENDOR_RESPONSES:
        return f"Answer must be one of: {', '.join(VENDOR_RESPONSES)}"
    if enquiry.status not in VENDOR_CAN_RESPOND:
        return "This request has already been answered."
    if action == VENDOR_CONFIRMED and booked_date(enquiry, when) is None:
        return "Choose the date you can do."
    if action == VENDOR_OTHER_DATE:
        if when is None:
            return "Choose the date you can offer instead."
        if when < today:
            return "Choose a date from today on."
        if when == enquiry.preferred_date:
            return "That is the date the traveller asked for: confirm it instead."
    if action in (VENDOR_OTHER_DATE, VENDOR_CANCELLED) and reason not in DECLINE_REASONS:
        return "Choose why you cannot do the date asked."
    return None


def vendor_respond(
    enquiry, action: str, *, now: datetime, when: Optional[date] = None,
    reason: Optional[str] = None, note: Optional[str] = None,
) -> Optional[str]:
    """Record the vendor's answer (checked by `vendor_response_error`).

    Returns the event everyone must hear about, as `apply_status` does:
    CONFIRMED, PROVIDER_CANCELLED, or None for another date offered (only
    NexAround hears of that, and arranges it with the traveller).
    """
    enquiry.vendor_response = action
    enquiry.vendor_responded_at = now
    enquiry.vendor_response_reason = reason if action != VENDOR_CONFIRMED else None
    enquiry.vendor_response_note = (note or "").strip() or None
    enquiry.vendor_offered_date = when if action == VENDOR_OTHER_DATE else None
    if action == VENDOR_OTHER_DATE:
        # A new offer for the traveller to answer.
        enquiry.offer_response = None
        enquiry.offer_responded_at = None
    if action == VENDOR_CONFIRMED:
        return apply_status(enquiry, CONFIRMED, now=now, confirmed_date=when)
    if action == VENDOR_CANCELLED:
        return apply_status(enquiry, PROVIDER_CANCELLED, now=now, reason=DECLINE_REASONS[reason])
    return None


# --- The traveller's answer to an offered date ------------------------------
#
# The vendor's other date goes to the traveller in the app. Accepting confirms
# the booking for that date; declining cancels the request (by the traveller:
# it was their choice, and no late-cancellation rule applies to a request
# that was never confirmed).

OFFER_ACCEPTED = "accepted"
OFFER_DECLINED = "declined"
DECLINED_OFFER_REASON = "Declined the other date offered"


def pending_offer(enquiry) -> Optional[date]:
    """The date the provider offered, while the traveller has yet to answer."""
    if (
        enquiry.status in VENDOR_CAN_RESPOND
        and enquiry.vendor_response == VENDOR_OTHER_DATE
        and enquiry.offer_response is None
    ):
        return enquiry.vendor_offered_date
    return None


def offer_response_error(enquiry, today: date) -> Optional[str]:
    """None if the traveller may answer the offered date now."""
    offered = pending_offer(enquiry)
    if offered is None:
        return "There is no other date waiting for your answer."
    if offered < today:
        return "That date has passed. Contact Nexaround support to find another."
    return None


def respond_to_offer(enquiry, accept: bool, *, now: datetime) -> Optional[str]:
    """Record the traveller's answer (checked by `offer_response_error`) and
    return the event everyone hears about: CONFIRMED or CUSTOMER_CANCELLED."""
    enquiry.offer_response = OFFER_ACCEPTED if accept else OFFER_DECLINED
    enquiry.offer_responded_at = now
    if accept:
        return apply_status(enquiry, CONFIRMED, now=now, confirmed_date=enquiry.vendor_offered_date)
    return apply_status(enquiry, CUSTOMER_CANCELLED, now=now, reason=DECLINED_OFFER_REASON)
