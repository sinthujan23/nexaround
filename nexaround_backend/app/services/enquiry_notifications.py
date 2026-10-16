"""Telling the other side what happened to an experience request.

* The traveller hears when their request is received (email), and when the
  provider confirms or cancels it (push and email).
* The vendor hears when the traveller cancels (email, alongside the portal's
  live alert and activity line).

Each function runs after the response as a background task, in its own
session, and never raises: a failed email or push must not undo a booking.
"""
import logging
import uuid
from datetime import date
from typing import Optional

from app.core.database import async_session
from app.models.experience import ExperienceEnquiry, ExperienceVendor
from app.models.user import User
from app.services import email_service, legal_service
from app.services import enquiry_lifecycle as lifecycle
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

TERMS_URL = "https://nexaround.com/experience-terms"
# The app routes a tap on this push to My requests.
PUSH_TYPE = "experience_request"


def day(value: Optional[date]) -> str:
    """"Tue 20 Oct 2026"."""
    return f"{value:%a} {value.day} {value:%b %Y}" if value else ""


def _guests(party_size: Optional[int]) -> str:
    if not party_size:
        return ""
    return f"{party_size} {'guest' if party_size == 1 else 'guests'}"


def _free_cancellation_note(enquiry: ExperienceEnquiry) -> str:
    last = enquiry.free_cancellation_last_day
    if last is None:
        return ""
    return (
        f"Free cancellation until the end of {day(last)}. After that, or if you "
        "do not attend, you may have to pay the booking price."
    )


async def _push(db, user_id, title: str, body: str, enquiry_id) -> None:
    """To every device the traveller is signed in on, pruning dead tokens."""
    from app.services import fcm_service

    user = await db.get(User, user_id)
    if not user:
        return
    prefs = user.preferences or {}
    tokens = list(prefs.get("fcm_tokens") or [])
    legacy = prefs.get("fcm_token")
    if legacy and legacy not in tokens:
        tokens.append(legacy)
    if not tokens:
        return
    invalid = await fcm_service.send_to_tokens(
        db, tokens, title=title, body=body,
        data={"type": PUSH_TYPE, "enquiry_id": str(enquiry_id)},
    )
    if invalid:
        new_prefs = {**prefs, "fcm_tokens": [t for t in tokens if t not in invalid]}
        new_prefs.pop("fcm_token", None)
        user.preferences = new_prefs
        await db.commit()


async def request_received(enquiry_id: uuid.UUID) -> None:
    """Email the traveller a copy of their request and the terms they accepted."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if not enquiry or not enquiry.contact_email:
                return
            terms = await legal_service.get_current(db, legal_service.CUSTOMER)
            notes = list(terms.highlights or [])
            if enquiry.terms_version:
                notes.append(
                    f"You accepted the {terms.title} (version {enquiry.terms_version}) "
                    "when you sent this request."
                )
            provider = enquiry.vendor_name_snapshot or "The provider"
            await email_service.send_experience_update_email(
                enquiry.contact_email,
                subject=f"Request sent: {enquiry.package_title_snapshot or 'your experience'}",
                heading="We've sent your request",
                intro=f"{provider} will contact you to confirm it. Your booking is "
                      "confirmed only when they do.",
                rows=(
                    ("Experience", enquiry.package_title_snapshot),
                    ("Provider", enquiry.vendor_name_snapshot),
                    ("Preferred date", day(enquiry.preferred_date) or "Flexible"),
                    ("Guests", _guests(enquiry.party_size)),
                    ("Pickup", enquiry.pickup_location),
                ),
                notes=tuple(notes),
                link_label=f"Read the {terms.title}",
                link_url=TERMS_URL,
            )
    except Exception:
        logger.exception("request-received email failed for enquiry %s", enquiry_id)


async def booking_update(enquiry_id: uuid.UUID, event: str) -> None:
    """Push and email the traveller when the provider confirms or cancels."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if not enquiry:
                return
            vendor = (
                await db.get(ExperienceVendor, enquiry.vendor_id)
                if enquiry.vendor_id else None
            )
            provider = enquiry.vendor_name_snapshot or "The provider"
            experience = enquiry.package_title_snapshot or "your experience"

            if event == lifecycle.CONFIRMED:
                push = ("Booking confirmed",
                        f"{provider} confirmed {experience} for {day(enquiry.confirmed_date)}.")
                subject = f"Booking confirmed: {experience}"
                heading = "Your booking is confirmed"
                intro = f"{provider} confirmed your booking."
                rows = (
                    ("Experience", enquiry.package_title_snapshot),
                    ("Date", day(enquiry.confirmed_date)),
                    ("Guests", _guests(enquiry.party_size)),
                    ("Pickup", enquiry.pickup_location),
                    ("Provider phone", vendor.contact_phone if vendor else None),
                    ("Provider WhatsApp", vendor.contact_whatsapp if vendor else None),
                )
                notes = (
                    _free_cancellation_note(enquiry),
                    "To cancel, open My requests in the Nexaround app.",
                )
            elif event == lifecycle.PROVIDER_CANCELLED:
                what = "booking" if enquiry.confirmed_date else "request"
                push = (f"{what.capitalize()} cancelled",
                        f"{provider} cancelled {experience}.")
                subject = f"Cancelled by the provider: {experience}"
                heading = f"{provider} cancelled your {what}"
                intro = ("We're sorry. The provider is responsible for arranging any "
                         "refund or rescheduling.")
                rows = (
                    ("Experience", enquiry.package_title_snapshot),
                    ("Date", day(enquiry.confirmed_date or enquiry.preferred_date)),
                    ("Reason", enquiry.cancellation_reason),
                )
                notes = ("You can find other experiences in the Nexaround app.",)
            else:
                return

            if enquiry.user_id:
                await _push(db, enquiry.user_id, push[0], push[1], enquiry.id)
            if enquiry.contact_email:
                await email_service.send_experience_update_email(
                    enquiry.contact_email,
                    subject=subject, heading=heading, intro=intro,
                    rows=rows, notes=notes,
                    link_label="Read the Experience Booking Terms", link_url=TERMS_URL,
                )
    except Exception:
        logger.exception("booking update (%s) failed for enquiry %s", event, enquiry_id)


async def customer_cancelled(enquiry_id: uuid.UUID) -> None:
    """Email the vendor, and the platform inbox, that the traveller cancelled."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if not enquiry:
                return
            vendor = (
                await db.get(ExperienceVendor, enquiry.vendor_id)
                if enquiry.vendor_id else None
            )
            recipients: list[str] = []
            if vendor and vendor.contact_email:
                recipients.append(vendor.contact_email)
            platform = await SettingsService(db).get_setting("contact_email")
            if platform and platform not in recipients:
                recipients.append(platform)

            experience = enquiry.package_title_snapshot or "an experience"
            booked = enquiry.confirmed_date or enquiry.preferred_date
            cancelled = enquiry.cancelled_at
            notes = (
                (
                    "This is a late cancellation: less than 72 hours before the booked "
                    "day. Under the Experience Booking Terms the traveller may have to "
                    "pay the booking price.",
                )
                if enquiry.late_cancellation else ()
            )
            for address in recipients:
                await email_service.send_experience_update_email(
                    address,
                    subject=f"Cancelled by the traveller: {experience}",
                    heading=f"{enquiry.contact_name} cancelled",
                    intro="The traveller cancelled their "
                          f"{'booking' if enquiry.confirmed_date else 'request'} "
                          "in the Nexaround app.",
                    rows=(
                        ("Experience", enquiry.package_title_snapshot),
                        ("Traveller", enquiry.contact_name),
                        ("Phone", enquiry.contact_phone),
                        ("Date", day(booked)),
                        ("Guests", _guests(enquiry.party_size)),
                        ("Cancelled", f"{cancelled:%d %b %Y, %H:%M} UTC" if cancelled else ""),
                        ("Reason", enquiry.cancellation_reason),
                    ),
                    notes=notes,
                )
    except Exception:
        logger.exception("customer-cancelled email failed for enquiry %s", enquiry_id)
