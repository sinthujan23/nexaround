"""The partner portal's activity feed — what the bell shows.

Call sites build a row with one of the helpers below *before* their commit, so
the feed line and the change it describes land in one transaction, then pass
the returned payload to `announce()` after the commit so open portal tabs add
it live.

Only fields the vendor can see are compared when deciding whether an update is
worth a line. The admin forms also save `internal_notes`, `sort_order` and the
like on every press, and a line saying "NexAround updated your profile" for an
internal note would both be noise and leak that one was written.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Iterable, Optional

from app.models.experience import VendorActivity
from app.services import partner_events

ACTIVITY_CREATED = "activity.created"

TRAVELLER = "traveller"
VENDOR = "vendor"
ADMIN = "admin"


def _norm(value):
    """Make a before/after pair comparable across a save.

    The saves are full replacements from a form, so a value that did not
    change can still come back in another type: `price_amount` is a Decimal
    from the database and a float from the form (Decimal("99.99") != 99.99),
    and an emptied text field may be "" on one side and None on the other.
    """
    if isinstance(value, (Decimal, float)):
        return round(float(value), 6)
    if value == "":
        return None
    if isinstance(value, list):
        return tuple(value)
    return value


def _coords(location):
    # The geometry is rebuilt as a new object on every save, so compare the
    # point it describes, not the object.
    from app.utils.geo_utils import get_lat_lng

    lat, lng = get_lat_lng(location)
    return None if lat is None else (round(lat, 6), round(lng, 6))


def snapshot(obj, fields: Iterable[str]) -> dict:
    """The vendor-visible state an update is judged by. Take it before the
    save; the helpers below take the after-state themselves."""
    snap = {f: _norm(getattr(obj, f)) for f in fields}
    snap["location"] = _coords(obj.location)
    return snap


def _changed(obj, before: dict) -> list:
    after = snapshot(obj, [f for f in before if f != "location"])
    return [f for f in before if after[f] != before[f]]


def to_payload(row: VendorActivity) -> dict:
    return {
        "id": str(row.id),
        "kind": row.kind,
        "title": row.title,
        "body": row.body,
        "actor": row.actor,
        "actor_login_id": str(row.actor_login_id) if row.actor_login_id else None,
        "actor_name": row.actor_name,
        "enquiry_id": str(row.enquiry_id) if row.enquiry_id else None,
        "package_id": str(row.package_id) if row.package_id else None,
        "created_at": row.created_at.isoformat(),
    }


def record(
    db,
    vendor_id,
    kind: str,
    title: str,
    *,
    actor: str,
    body: Optional[str] = None,
    login=None,
    enquiry_id=None,
    package_id=None,
) -> dict:
    """Add a feed line to the session (the caller commits) and return its payload.

    `id` and `created_at` are set here rather than left to column defaults so
    the payload is complete before the flush.
    """
    row = VendorActivity(
        id=uuid.uuid4(),
        vendor_id=vendor_id,
        kind=kind,
        title=title[:255],
        body=body[:500] if body else None,
        actor=actor,
        actor_login_id=login.id if login is not None else None,
        actor_name=(login.display_name or login.email) if login is not None else None,
        enquiry_id=enquiry_id,
        package_id=package_id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(row)
    payload = to_payload(row)
    payload["vendor_id"] = str(vendor_id)
    return payload


async def announce(*payloads: Optional[dict]) -> None:
    """Push committed feed lines to that vendor's open tabs. Never raises."""
    for payload in payloads:
        if not payload:
            continue
        data = dict(payload)
        vendor_id = data.pop("vendor_id")
        await partner_events.publish(vendor_id, ACTIVITY_CREATED, data)


# ── The lines themselves ─────────────────────────────────────────────────────
# One helper per kind keeps the wording in one place. Vendors get no enquiry
# lines: requests go only to Nexaround (the old ones are filtered out on read).

def review_received(db, review, package) -> dict:
    """A traveller rated one of the vendor's packages: the nudge to answer it."""
    stars = f"{review.rating}/5"
    return record(
        db, review.vendor_id, "review.created",
        f"{review.reviewer_name} rated {package.title} {stars}",
        body=(review.comment or "")[:200] or None,
        actor=TRAVELLER,
        package_id=package.id,
    )


def package_created(db, package, *, actor: str, login=None) -> dict:
    return record(
        db, package.vendor_id, "package.created", f"{package.title} added",
        body=None if package.is_active else "Hidden from travellers until you switch it on.",
        actor=actor, login=login, package_id=package.id,
    )


def package_updated(db, package, before: dict, *, actor: str, login=None) -> Optional[dict]:
    """A line for a package save, or None if nothing the vendor sees changed.

    Switching a package on or off gets its own wording — it is the change a
    vendor most needs to notice, especially when NexAround made it.
    """
    changed = _changed(package, before)
    if not changed:
        return None
    if changed == ["is_active"]:
        if package.is_active:
            kind, title = "package.live", f"{package.title} is now live"
        else:
            kind, title = "package.hidden", f"{package.title} is now hidden"
    else:
        kind, title = "package.updated", f"{package.title} updated"
    return record(db, package.vendor_id, kind, title, actor=actor, login=login, package_id=package.id)


def package_deleted(db, package, *, actor: str, login=None) -> dict:
    # No package_id: the row is about to be gone, and the FK would null it anyway.
    return record(
        db, package.vendor_id, "package.deleted", f"{package.title} deleted",
        actor=actor, login=login,
    )


def profile_updated(db, vendor, before: dict, *, actor: str, login=None) -> Optional[dict]:
    """A line for a profile save, or None if nothing the vendor sees changed.

    `is_active` is only ever in `before` for an admin save: suspending or
    restoring the listing gets its own wording.
    """
    changed = _changed(vendor, before)
    if not changed:
        return None
    if "is_active" in changed:
        if vendor.is_active:
            return record(
                db, vendor.id, "listing.restored", "Your listing is live again",
                body="Travellers can see your published packages.",
                actor=actor, login=login,
            )
        return record(
            db, vendor.id, "listing.suspended", "Your listing was suspended",
            body="Travellers cannot see your packages. Contact NexAround.",
            actor=actor, login=login,
        )
    return record(db, vendor.id, "profile.updated", "Business profile updated", actor=actor, login=login)
