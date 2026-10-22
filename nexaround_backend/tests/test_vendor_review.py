"""A vendor's own edits wait for an admin while the live version keeps showing.

The rules, from services/vendor_review:
* a new package stays unpublished until approved;
* content edits to a live package wait in `pending_changes`, the live columns
  untouched; availability and Show/Hide apply at once;
* a save that changes nothing reviewed leaves the review as it was;
* approving applies the edits (dollar prices kept); sending back keeps them
  with the admin's note.

No database: the functions work on the model objects, so plain stand-ins do.
"""
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

from app.api.v1.partner import _package_out, _profile_response
from app.schemas.partner import (
    PartnerPackageCreate, PartnerPackageUpdate, PartnerVendorProfileUpdate,
)
from app.services import partner_activity, vendor_review as vr
from app.services.experience_format import is_published

NOW = datetime(2026, 10, 22, 12, 0, tzinfo=timezone.utc)
LATER = datetime(2026, 10, 23, 9, 0, tzinfo=timezone.utc)


def _live_package(**overrides):
    fields = dict(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), title="Dolphin Watching", summary="Sunrise trip",
        description="Boat from Nilaveli", category="boat", tags=[], photo_urls=["/a.jpg"],
        price_currency="LKR", price_amount=30000, price_usd=90, price_basis="per_group",
        price_options=[{"id": "aa11", "amount": 30000, "usd": 90, "basis": "per_group",
                        "min_people": None, "max_people": 7}],
        duration_minutes=180, max_participants=7, inclusions=["Life jackets"], languages=["English"],
        unavailable_ranges=[], booking_window_days=None, is_active=True,
        uses_vendor_location=True, meeting_point_address=None, location=None,
        review_status=vr.APPROVED, pending_changes=None, review_note=None,
        submitted_at=None, reviewed_at=None, approved_at=NOW, is_published=True,
        created_at=NOW, updated_at=NOW,
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def _form(package, **changes):
    """What the vendor's form sends: what GET showed, with their edits."""
    asked = vr.vendor_package_content(package)
    body = {
        **{k: asked[k] for k in vr.PACKAGE_REVIEWED_SCALARS},
        "price_options": [
            {k: o[k] for k in ("id", "amount", "basis", "min_people", "max_people")}
            for o in asked["price_options"]
        ],
        "unavailable_ranges": package.unavailable_ranges,
        "booking_window_days": package.booking_window_days,
        "is_active": package.is_active,
    }
    body.update(changes)
    return PartnerPackageUpdate(**body)


def test_a_new_package_waits_unpublished():
    package = _live_package(approved_at=None, review_status=None)
    data = PartnerPackageCreate(title="Whale Watching", price_options=[{"amount": 9000, "basis": "per_person"}])
    vr.new_package(package, vr.package_proposal(data), NOW)
    assert package.title == "Whale Watching"
    assert package.review_status == vr.PENDING and package.submitted_at == NOW
    assert package.approved_at is None
    assert not is_published(True, package.is_active, package.approved_at is not None)
    # No dollar price from a vendor.
    assert package.price_options[0]["usd"] is None


def test_an_edit_to_a_live_package_waits_and_the_live_version_stays():
    package = _live_package()
    sent = vr.submit_package(package, vr.package_proposal(_form(package, title="Dolphin Safari"), package), NOW)
    assert sent
    assert package.title == "Dolphin Watching"
    assert package.pending_changes == {"title": "Dolphin Safari"}
    assert package.review_status == vr.PENDING


def test_the_vendor_sees_what_they_asked_for():
    package = _live_package(pending_changes={"title": "Dolphin Safari"}, review_status=vr.PENDING)
    out = _package_out(package)
    assert out.title == "Dolphin Safari"
    assert out.review_status == vr.PENDING
    assert out.is_published and out.is_approved
    assert not hasattr(out.price_options[0], "usd")


def test_saving_the_same_again_or_only_the_switch_keeps_the_admins_note():
    package = _live_package()
    vr.submit_package(package, vr.package_proposal(_form(package, title="Dolphin Safari"), package), NOW)
    vr.request_changes(package, "Use a photo of the boat.", NOW)
    package.is_active = False  # the Show/Hide switch, applied by the endpoint
    sent = vr.submit_package(package, vr.package_proposal(_form(package), package), LATER)
    assert not sent
    assert package.review_status == vr.CHANGES_REQUESTED
    assert package.review_note == "Use a photo of the boat."
    assert package.submitted_at == NOW


def test_fixing_what_was_asked_sends_it_again():
    package = _live_package()
    vr.submit_package(package, vr.package_proposal(_form(package, title="Dolphin Safari"), package), NOW)
    vr.request_changes(package, "Use a photo of the boat.", NOW)
    sent = vr.submit_package(
        package, vr.package_proposal(_form(package, photo_urls=["/boat.jpg"]), package), LATER,
    )
    assert sent
    assert package.review_status == vr.PENDING and package.review_note is None
    assert package.pending_changes == {"title": "Dolphin Safari", "photo_urls": ["/boat.jpg"]}


def test_going_back_to_what_is_live_leaves_nothing_to_review():
    package = _live_package(pending_changes={"title": "Dolphin Safari"}, review_status=vr.PENDING)
    vr.submit_package(package, vr.package_proposal(_form(package, title="Dolphin Watching"), package), NOW)
    assert package.pending_changes is None
    assert package.review_status == vr.APPROVED


def test_approving_makes_the_prices_live_and_keeps_the_dollars():
    package = _live_package()
    options = [
        {"id": "aa11", "amount": 32000, "basis": "per_group", "max_people": 7},
        {"amount": 8000, "basis": "per_person", "min_people": 3},
    ]
    vr.submit_package(package, vr.package_proposal(_form(package, price_options=options), package), NOW)
    assert package.price_amount == 30000  # still live
    vr.approve_package(package, LATER)
    assert package.price_amount == 32000 and package.price_basis == "per_group"
    assert package.price_options[0]["usd"] == 90  # the admin's, kept by id
    assert package.price_options[1]["usd"] is None
    assert package.review_status == vr.APPROVED and package.pending_changes is None
    assert package.reviewed_at == LATER and package.approved_at == NOW


def test_approving_a_new_package_publishes_it():
    package = _live_package(approved_at=None, review_status=vr.PENDING)
    vr.approve_package(package, LATER)
    assert package.approved_at == LATER
    assert is_published(True, True, package.approved_at is not None)


def test_the_admin_sees_each_change_against_what_is_live():
    package = _live_package(pending_changes={"title": "Dolphin Safari"}, review_status=vr.PENDING)
    rows = vr.diff_rows(vr.live_package_content(package), package.pending_changes)
    assert rows == [{"field": "title", "label": "Title", "before": "Dolphin Watching", "after": "Dolphin Safari"}]
    assert vr.pending_summary(package, "package") == "Title"
    new = _live_package(approved_at=None, review_status=vr.PENDING)
    assert vr.pending_summary(new, "package") == "New package"
    new_rows = vr.diff_rows(vr.live_package_content(new), vr.live_package_content(new), is_new=True)
    assert all(r["before"] is None for r in new_rows)
    assert "tags" not in {r["field"] for r in new_rows}  # empty fields left out


def _vendor(**overrides):
    fields = dict(
        id=uuid.uuid4(), name="Blue Ocean Adventures", description="Boat tours", contact_email="a@b.lk",
        logo_url=None, photo_urls=["/v.jpg"], website="https://blueocean.lk", address="Nilaveli",
        city="Trincomalee", country_code="LK", location=None, is_active=True,
        contact_phone=None, contact_whatsapp=None, contact_instagram=None, contact_facebook=None,
        contact_x=None, rating=None, review_count=0, created_at=NOW, updated_at=NOW,
        review_status=vr.APPROVED, pending_changes=None, review_note=None,
        submitted_at=None, reviewed_at=None,
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def test_profile_edits_wait_and_the_address_is_not_the_vendors():
    vendor = _vendor()
    data = PartnerVendorProfileUpdate(
        name="Blue Ocean Tours", description="Boat tours", contact_email="a@b.lk",
        photo_urls=["/v.jpg"], website="https://elsewhere.example", address="Somewhere else",
    )
    sent = vr.submit_profile(vendor, vr.profile_proposal(data), NOW)
    assert sent
    assert vendor.name == "Blue Ocean Adventures"
    assert vendor.pending_changes == {"name": "Blue Ocean Tours"}
    out = _profile_response(vendor, 3)
    assert out.name == "Blue Ocean Tours" and out.review_status == vr.PENDING
    assert out.website == "https://blueocean.lk" and out.address == "Nilaveli"
    vr.approve_profile(vendor, LATER)
    assert vendor.name == "Blue Ocean Tours" and vendor.review_status == vr.APPROVED
    assert vendor.website == "https://blueocean.lk"


def test_the_vendor_is_told_with_the_admins_note():
    title, body = partner_activity.review_text("Dolphin Watching", False, "Use a photo of the boat.")
    assert title == "Changes needed: Dolphin Watching"
    assert body == "Use a photo of the boat."
    title, body = partner_activity.review_text("Whale Watching", True, None, is_new=True)
    assert title == "Approved: Whale Watching"
    assert body == "It is now live for travellers."
