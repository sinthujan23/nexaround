"""Telling the other side what happened to an experience request.

* The traveller hears when their request is received (email), and when it
  is confirmed or cancelled (push and email).
* The platform inbox hears when the traveller cancels (email).
* The vendor hears that a request came in, and when NexAround or the
  traveller confirms or cancels it (push to the app logins, email to every
  login, a line in the bell): the package, the date, the guests and the
  price chosen, never who asked or where to pick them up. The vendor answers
  in the portal; NexAround contacts the traveller itself.
* The platform inbox hears the vendor's answer, with the traveller's details.

Each function runs after the response as a background task, in its own
session, and never raises: a failed email or push must not undo a booking.
"""
import logging
import uuid
from datetime import date
from typing import Optional

from app.core.database import async_session
from sqlalchemy import select

from app.models.experience import ExperienceEnquiry, ExperienceVendor, VendorUser
from app.models.user import User
from app.services import email_service, legal_service, partner_activity
from app.services.experience_format import vendor_option_label
from app.services import enquiry_lifecycle as lifecycle
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

TERMS_URL = "https://nexaround.com/experience-terms"
# The app routes a tap on this push to My requests.
PUSH_TYPE = "experience_request"
# ...and a tap on this one to the request in the vendor portal.
VENDOR_PUSH_TYPE = "vendor_request"
PORTAL_URL = "https://partner.nexaround.com"


def request_ref(enquiry) -> str:
    """"#3F9A1C": how the vendor and NexAround name a request to each other."""
    return enquiry.reference


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
    await _push_data(
        db, user_id, title, body, {"type": PUSH_TYPE, "enquiry_id": str(enquiry_id)},
    )


async def _push_data(db, user_id, title: str, body: str, data: dict) -> None:
    """To every device the account is signed in on, pruning dead tokens."""
    from app.services import fcm_service

    user = await db.get(User, user_id)
    if not user or not user.is_active:
        return
    prefs = user.preferences or {}
    tokens = list(prefs.get("fcm_tokens") or [])
    legacy = prefs.get("fcm_token")
    if legacy and legacy not in tokens:
        tokens.append(legacy)
    if not tokens:
        return
    invalid = await fcm_service.send_to_tokens(db, tokens, title=title, body=body, data=data)
    if invalid:
        new_prefs = {**prefs, "fcm_tokens": [t for t in tokens if t not in invalid]}
        new_prefs.pop("fcm_token", None)
        user.preferences = new_prefs
        await db.commit()


async def _tell_vendor(db, enquiry, title: str, body: str) -> None:
    """Push to the vendor's app logins and email every login: the package,
    date, guests and price only (partner_activity reads nothing else)."""
    vendor = await db.get(ExperienceVendor, enquiry.vendor_id)
    if not vendor or not vendor.is_active:
        return
    logins = (await db.execute(
        select(VendorUser).where(
            VendorUser.vendor_id == enquiry.vendor_id,
            VendorUser.is_active.is_(True),
        )
    )).scalars().all()
    data = {
        "type": VENDOR_PUSH_TYPE, "vendor_id": str(enquiry.vendor_id),
        "enquiry_id": str(enquiry.id),
    }
    # address -> whether it signs in at the web portal (else the app).
    recipients: dict[str, bool] = {}
    for login in logins:
        if login.app_user_id:
            await _push_data(db, login.app_user_id, title, body, data)
            user = await db.get(User, login.app_user_id)
            if user and user.is_active and user.email:
                recipients.setdefault(user.email.lower(), False)
        if login.email:
            recipients[login.email.lower()] = True

    when = enquiry.confirmed_date or enquiry.preferred_date
    rows = (
        ("Request", request_ref(enquiry)),
        ("Experience", enquiry.package_title_snapshot),
        ("Date", day(when) if when else "Flexible"),
        ("Guests", _guests(enquiry.party_size)),
        # The vendor's own price, never NexAround's dollar figure.
        ("Price", vendor_option_label(enquiry.price_option)),
    )
    for address, web in sorted(recipients.items()):
        await email_service.send_experience_update_email(
            address,
            subject=f"{title} · NexAround",
            heading=title,
            intro=body,
            rows=rows,
            notes=() if web else (
                "Open the NexAround app, go to Experiences, tap Vendor portal and then Requests.",
            ),
            link_label="Open the request" if web else "",
            link_url=f"{PORTAL_URL}/requests/{enquiry.id}" if web else "",
        )


async def vendor_request_alert(enquiry_id: uuid.UUID) -> None:
    """Tell the vendor a request came in, by push and email.

    Only what partner_activity.request_text reads - package, date, guests -
    and the price chosen, so the vendor cannot reach the traveller around
    Nexaround.
    """
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if enquiry:
                await _tell_vendor(db, enquiry, *partner_activity.request_text(enquiry))
    except Exception:
        logger.exception("vendor request push failed for enquiry %s", enquiry_id)


async def vendor_update_alert(enquiry_id: uuid.UUID, event: str) -> None:
    """Tell the vendor NexAround or the traveller confirmed or cancelled a
    request: the same facts (partner_activity.update_text)."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if enquiry and event in partner_activity.UPDATE_KINDS:
                await _tell_vendor(db, enquiry, *partner_activity.update_text(enquiry, event))
    except Exception:
        logger.exception("vendor update push failed for enquiry %s", enquiry_id)


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
                intro="Nexaround will contact you to confirm it. Your booking is "
                      "confirmed only when we do.",
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
                    # Nexaround, not the provider: bookings go through the platform.
                    ("Contact", await SettingsService(db).get_setting("contact_email")),
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
    """Email the platform inbox that the traveller cancelled. Not the vendor."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            if not enquiry:
                return
            platform = await SettingsService(db).get_setting("contact_email")
            recipients = [platform] if platform else []

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


async def vendor_answered(enquiry_id: uuid.UUID) -> None:
    """Email the platform inbox the vendor's answer, with the traveller's
    details: a confirmation (the traveller has been told), a cancellation
    (likewise), or another date to take to the traveller."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            platform = await SettingsService(db).get_setting("contact_email")
            if not enquiry or not platform:
                return
            vendor = enquiry.vendor_name_snapshot or "The provider"
            experience = enquiry.package_title_snapshot or "an experience"
            answer = enquiry.vendor_response
            if answer == lifecycle.VENDOR_CONFIRMED:
                subject = f"Confirmed by the provider: {experience}"
                heading = f"{vendor} confirmed"
                intro = "The traveller has been told by push and email."
            elif answer == lifecycle.VENDOR_OTHER_DATE:
                subject = f"Another date offered: {experience}"
                heading = f"{vendor} offered {day(enquiry.vendor_offered_date)}"
                intro = ("The provider cannot do the date asked. The traveller has been asked to "
                         "accept or decline the offered date in the app; you will hear their answer.")
            else:
                subject = f"Cancelled by the provider: {experience}"
                heading = f"{vendor} cancelled"
                intro = "The provider cannot do it and had no other date. The traveller has been told."
            await email_service.send_experience_update_email(
                platform,
                subject=subject, heading=heading, intro=intro,
                rows=(
                    ("Request", request_ref(enquiry)),
                    ("Experience", enquiry.package_title_snapshot),
                    ("Asked for", day(enquiry.preferred_date) if enquiry.preferred_date else "Flexible"),
                    ("Confirmed for", day(enquiry.confirmed_date) if answer == lifecycle.VENDOR_CONFIRMED else None),
                    ("Offered instead", day(enquiry.vendor_offered_date) if enquiry.vendor_offered_date else None),
                    ("Reason", lifecycle.DECLINE_REASONS.get(enquiry.vendor_response_reason or "")),
                    ("Provider's note", enquiry.vendor_response_note),
                    ("Guests", _guests(enquiry.party_size)),
                    ("Traveller", enquiry.contact_name),
                    ("Phone", enquiry.contact_phone),
                    ("Email", enquiry.contact_email),
                ),
            )
    except Exception:
        logger.exception("vendor answer email failed for enquiry %s", enquiry_id)


async def date_offered(enquiry_id: uuid.UUID) -> None:
    """Ask the traveller (push and email) to accept or decline the date the
    provider offered instead of the one they asked for."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            offered = lifecycle.pending_offer(enquiry) if enquiry else None
            if offered is None:
                return
            provider = enquiry.vendor_name_snapshot or "The provider"
            experience = enquiry.package_title_snapshot or "your experience"
            asked = day(enquiry.preferred_date) if enquiry.preferred_date else "the date you asked for"
            if enquiry.user_id:
                await _push(
                    db, enquiry.user_id, "Another date offered",
                    f"{provider} can't do {asked} but offers {day(offered)} for {experience}. "
                    "Tap to accept or decline.",
                    enquiry.id,
                )
            if enquiry.contact_email:
                await email_service.send_experience_update_email(
                    enquiry.contact_email,
                    subject=f"Another date offered: {experience}",
                    heading=f"{provider} offers {day(offered)}",
                    intro=f"{provider} can't do {asked}. They can do {day(offered)} instead.",
                    rows=(
                        ("Experience", enquiry.package_title_snapshot),
                        ("Asked for", asked if enquiry.preferred_date else None),
                        ("Offered", day(offered)),
                        ("Reason", lifecycle.DECLINE_REASONS.get(enquiry.vendor_response_reason or "")),
                        ("Guests", _guests(enquiry.party_size)),
                    ),
                    notes=(
                        "Open My requests in the Nexaround app to accept or decline it. Accepting "
                        "confirms your booking for that date; declining cancels the request.",
                    ),
                    link_label="Read the Experience Booking Terms", link_url=TERMS_URL,
                )
    except Exception:
        logger.exception("date offered notice failed for enquiry %s", enquiry_id)


async def offer_answered(enquiry_id: uuid.UUID) -> None:
    """Email the platform inbox the traveller's answer to an offered date."""
    try:
        async with async_session() as db:
            enquiry = await db.get(ExperienceEnquiry, enquiry_id)
            platform = await SettingsService(db).get_setting("contact_email")
            if not enquiry or not platform or not enquiry.offer_response:
                return
            experience = enquiry.package_title_snapshot or "an experience"
            accepted = enquiry.offer_response == lifecycle.OFFER_ACCEPTED
            await email_service.send_experience_update_email(
                platform,
                subject=(f"Other date accepted: {experience}" if accepted
                         else f"Other date declined: {experience}"),
                heading=(f"{enquiry.contact_name} accepted {day(enquiry.vendor_offered_date)}" if accepted
                         else f"{enquiry.contact_name} declined {day(enquiry.vendor_offered_date)}"),
                intro=("The booking is confirmed for the offered date. The traveller and the "
                       "provider have been told." if accepted else
                       "The request is cancelled. The provider has been told."),
                rows=(
                    ("Request", request_ref(enquiry)),
                    ("Experience", enquiry.package_title_snapshot),
                    ("Provider", enquiry.vendor_name_snapshot),
                    ("Asked for", day(enquiry.preferred_date) if enquiry.preferred_date else "Flexible"),
                    ("Offered", day(enquiry.vendor_offered_date)),
                    ("Guests", _guests(enquiry.party_size)),
                    ("Traveller", enquiry.contact_name),
                    ("Phone", enquiry.contact_phone),
                    ("Email", enquiry.contact_email),
                ),
            )
    except Exception:
        logger.exception("offer answer email failed for enquiry %s", enquiry_id)
