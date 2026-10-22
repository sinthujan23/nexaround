"""Admin review of the edits vendors make themselves.

As on GetYourGuide or Viator, what a supplier changes is checked before
travellers see it, while the version they see stays live:

* Package content - what a traveller reads and pays - waits in
  `pending_changes` while the live columns keep showing. A package a vendor
  adds has nothing live yet, so its content sits on the row itself and the row
  stays unpublished (`approved_at` NULL) until an admin approves it.
* Availability (blocked days, how far ahead) and the Show/Hide switch apply at
  once: a vendor who is fully booked has to be able to say so now.
* The profile's content (name, description, email, logo, photos) waits the
  same way.
* Where the business is and how to reach it outside NexAround - address, map
  point, meeting point, website - only an admin sets; vendors cannot.

Plain functions over the model objects: the endpoints load, call and commit.
"""
from __future__ import annotations

import json
from datetime import datetime
from decimal import Decimal
from typing import Optional

from app.services.experience_format import (
    apply_price_options, package_field_value, price_options_for_save,
)

APPROVED = "approved"
PENDING = "pending"
CHANGES_REQUESTED = "changes_requested"
STATUSES = (APPROVED, PENDING, CHANGES_REQUESTED)

# What a vendor writes to a package that an admin checks first. The prices
# travel as "price_options" (the first one is mirrored into the single price
# fields on approval); the dollar prices stay the admin's.
PACKAGE_REVIEWED_SCALARS = (
    "title", "summary", "description", "category", "tags", "photo_urls",
    "price_currency", "duration_minutes", "max_participants", "inclusions", "languages",
)
PACKAGE_REVIEWED = PACKAGE_REVIEWED_SCALARS + ("price_options",)

# What a vendor writes to a package that applies at once.
PACKAGE_INSTANT = ("unavailable_ranges", "booking_window_days", "is_active")

# What a vendor writes to their profile; all of it is checked first.
PROFILE_REVIEWED = ("name", "description", "contact_email", "logo_url", "photo_urls")

# How the admin queue and the emails name a field.
LABELS = {
    "title": "Title",
    "summary": "Summary",
    "description": "Description",
    "category": "Category",
    "tags": "Tags",
    "photo_urls": "Photos",
    "price_currency": "Currency",
    "price_options": "Prices",
    "duration_minutes": "Duration (minutes)",
    "max_participants": "Max participants",
    "inclusions": "What's included",
    "languages": "Languages",
    "name": "Business name",
    "contact_email": "Email",
    "logo_url": "Logo",
}


def _jsonable(value):
    """A column value as JSON keeps it (JSONB has no Decimal)."""
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    return value


def _comparable(value):
    """Equal for values a form round-trip leaves equal: "" and None, 7500
    and 7500.0, the same dict in another key order."""
    if isinstance(value, (Decimal, float, int)) and not isinstance(value, bool):
        return round(float(value), 6)
    if value == "":
        return None
    if isinstance(value, (list, tuple)):
        return [_comparable(v) for v in value]
    if isinstance(value, dict):
        return {k: _comparable(v) for k, v in value.items()}
    return value


def _same(a, b) -> bool:
    return json.dumps(_comparable(a), sort_keys=True, default=str) == json.dumps(
        _comparable(b), sort_keys=True, default=str
    )


def changed_fields(live: dict, proposal: dict) -> dict:
    """The proposed values that differ from the live ones."""
    return {k: v for k, v in proposal.items() if not _same(v, live.get(k))}


# ── Packages ────────────────────────────────────────────────────────────────

def live_package_content(package) -> dict:
    return {key: _jsonable(getattr(package, key)) for key in PACKAGE_REVIEWED}


def vendor_package_content(package) -> dict:
    """What the vendor last asked for: live, with anything waiting on top."""
    return {**live_package_content(package), **(package.pending_changes or {})}


def package_proposal(data, package=None) -> dict:
    """The reviewed fields as a vendor's save (`data`) would store them.

    Dollar prices are kept by option id from what the vendor last asked for,
    which kept them from live: a vendor never sets them.
    """
    out = {key: _jsonable(package_field_value(data, key)) for key in PACKAGE_REVIEWED_SCALARS}
    existing = vendor_package_content(package)["price_options"] if package is not None else None
    out["price_options"] = _jsonable(price_options_for_save(data, existing, vendor=True))
    return out


def _apply_package_content(package, content: dict) -> None:
    for key, value in content.items():
        if key == "price_options":
            apply_price_options(package, value)
        elif key in PACKAGE_REVIEWED_SCALARS:
            setattr(package, key, value)


def new_package(package, proposal: dict, now: datetime) -> None:
    """A package a vendor adds: its content on the row, waiting for review."""
    _apply_package_content(package, proposal)
    package.approved_at = None
    package.pending_changes = None
    package.review_status = PENDING
    package.review_note = None
    package.submitted_at = now


def submit_package(package, proposal: dict, now: datetime) -> bool:
    """File a vendor's save of an existing package's reviewed fields.

    True when it went (again) to review. A save that changes nothing the
    admin checks - the Show/Hide switch, the calendar - leaves the review as
    it was, a "changes requested" note included.
    """
    if package.approved_at is None:
        # Nothing live yet: the row itself is the proposal.
        if not changed_fields(live_package_content(package), proposal):
            return False
        _apply_package_content(package, proposal)
    else:
        changes = changed_fields(live_package_content(package), proposal)
        if not changes:
            # Back to what is live: nothing left to review.
            if package.pending_changes or package.review_status != APPROVED:
                package.pending_changes = None
                package.review_status = APPROVED
                package.review_note = None
            return False
        if package.pending_changes and _same(changes, package.pending_changes):
            return False
        package.pending_changes = changes
    package.review_status = PENDING
    package.review_note = None
    package.submitted_at = now
    return True


def approve_package(package, now: datetime) -> None:
    """Make what the vendor asked for live. The caller re-derives
    `is_published` (a first approval publishes)."""
    if package.pending_changes:
        _apply_package_content(package, package.pending_changes)
    package.pending_changes = None
    package.review_status = APPROVED
    package.review_note = None
    package.reviewed_at = now
    if package.approved_at is None:
        package.approved_at = now


# ── Profiles ────────────────────────────────────────────────────────────────

def _blank_none(value):
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


def live_profile_content(vendor) -> dict:
    return {key: _jsonable(getattr(vendor, key)) for key in PROFILE_REVIEWED}


def vendor_profile_content(vendor) -> dict:
    return {**live_profile_content(vendor), **(vendor.pending_changes or {})}


def profile_proposal(data) -> dict:
    out = {key: _blank_none(getattr(data, key)) for key in PROFILE_REVIEWED}
    out["photo_urls"] = list(data.photo_urls or [])
    return out


def submit_profile(vendor, proposal: dict, now: datetime) -> bool:
    """File a vendor's profile save; True when it went (again) to review."""
    changes = changed_fields(live_profile_content(vendor), proposal)
    if not changes:
        if vendor.pending_changes or vendor.review_status != APPROVED:
            vendor.pending_changes = None
            vendor.review_status = APPROVED
            vendor.review_note = None
        return False
    if vendor.pending_changes and _same(changes, vendor.pending_changes):
        return False
    vendor.pending_changes = changes
    vendor.review_status = PENDING
    vendor.review_note = None
    vendor.submitted_at = now
    return True


def approve_profile(vendor, now: datetime) -> None:
    for key, value in (vendor.pending_changes or {}).items():
        if key in PROFILE_REVIEWED:
            setattr(vendor, key, value)
    vendor.pending_changes = None
    vendor.review_status = APPROVED
    vendor.review_note = None
    vendor.reviewed_at = now


# ── Either ──────────────────────────────────────────────────────────────────

def request_changes(row, note: str, now: datetime) -> None:
    """Send it back with what to change. What the vendor asked for stays,
    so they fix it rather than start again."""
    row.review_status = CHANGES_REQUESTED
    row.review_note = note.strip()
    row.reviewed_at = now


def diff_rows(live: dict, proposed: dict, *, is_new: bool = False) -> list[dict]:
    """Field by field for the admin: what travellers see now, what the
    vendor asked for. A new package lists every field it has."""
    keys = proposed if not is_new else [k for k in proposed if proposed[k] not in (None, "", [])]
    return [
        {
            "field": key,
            "label": LABELS.get(key, key.replace("_", " ").capitalize()),
            "before": None if is_new else live.get(key),
            "after": proposed[key],
        }
        for key in keys
    ]


def pending_summary(row, kind: str) -> Optional[str]:
    """"Title, Photos" for a list line; None when nothing waits."""
    if kind == "package" and row.approved_at is None:
        return "New package"
    names = [LABELS.get(k, k) for k in (row.pending_changes or {})]
    return ", ".join(names) or None
