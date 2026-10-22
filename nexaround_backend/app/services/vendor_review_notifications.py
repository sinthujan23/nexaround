"""Telling a vendor what NexAround decided about their own edits.

An approval, or a request for changes with the admin's note, reaches every
active login of the vendor: an email (a web login's address, or the
NexAround account email of an app login) and a push to the app logins. The
bell line is written with the decision itself (partner_activity).

Runs after the response as a background task, in its own session, and never
raises: a failed email must not undo the decision.
"""
import logging
import uuid
from typing import Optional

from sqlalchemy import select

from app.core.database import async_session
from app.models.experience import ExperienceVendor, VendorUser
from app.models.user import User
from app.services import email_service
from app.services.enquiry_notifications import _push_data

logger = logging.getLogger(__name__)

# The app opens the vendor portal's notifications on a tap.
PUSH_TYPE = "vendor_review"
PORTAL_URL = "https://partner.nexaround.com"


async def review_decided(
    vendor_id: uuid.UUID,
    *,
    title: str,
    body: str,
    subject: str,
    approved: bool,
    note: Optional[str],
    package_id: Optional[uuid.UUID] = None,
    is_new: bool = False,
) -> None:
    """[title]/[body] from partner_activity.review_text; [subject] names what
    was reviewed ("Dolphin Watching Trip", "your business profile")."""
    try:
        async with async_session() as db:
            vendor = await db.get(ExperienceVendor, vendor_id)
            if vendor is None:
                return
            logins = (await db.execute(
                select(VendorUser).where(
                    VendorUser.vendor_id == vendor_id, VendorUser.is_active.is_(True),
                )
            )).scalars().all()

            data = {"type": PUSH_TYPE, "vendor_id": str(vendor_id)}
            if package_id:
                data["package_id"] = str(package_id)
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

            path = f"/packages/{package_id}" if package_id else "/profile"
            for address, web in sorted(recipients.items()):
                await email_service.send_experience_update_email(
                    address,
                    subject=f"{title} · NexAround",
                    heading="Approved" if approved else "Changes needed",
                    intro=(
                        f"NexAround approved {subject}. Travellers can find it in the app now."
                        if approved and is_new else
                        f"NexAround approved the changes to {subject}. Travellers see them now."
                        if approved else
                        f"NexAround reviewed {subject} and asked for changes before it can go live."
                        + ("" if is_new else " Travellers keep seeing the current version until then.")
                    ),
                    rows=(("Business", vendor.name), ("What changes", None if approved else note)),
                    notes=(
                        () if approved or web else
                        ("Open the NexAround app, go to Experiences and tap Vendor portal to make the changes.",)
                    ),
                    link_label="Open the partner portal" if web else "",
                    link_url=f"{PORTAL_URL}{path}" if web else "",
                )
    except Exception:
        logger.exception("vendor review notice failed for vendor %s", vendor_id)
