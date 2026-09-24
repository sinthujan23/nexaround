"""The partner portal's activity feed: when a save earns a line, and what it says.

The saves are full replacements from a form, so "did anything change" has to
survive values that come back in another type. Get it wrong one way and every
Save press writes "updated" to the feed; the other way and a real change is
silent. No database: a fake session only collects what is added.
"""
import uuid
from datetime import date
from decimal import Decimal
from types import SimpleNamespace

from app.api.v1.partner import _PARTNER_PACKAGE_SCALARS, _PARTNER_VENDOR_SCALARS
from app.services import partner_activity as pa
from app.utils.geo_utils import create_point


class FakeSession:
    def __init__(self):
        self.added = []

    def add(self, row):
        self.added.append(row)


def _package(**overrides):
    fields = {f: None for f in _PARTNER_PACKAGE_SCALARS}
    fields.update(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), title="Sunset Kayak",
        price_amount=Decimal("99.99"), tags=["kayak"], summary="",
        is_active=True, location=create_point(8.57, 81.23),
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def _vendor(**overrides):
    fields = {f: None for f in _PARTNER_VENDOR_SCALARS}
    fields.update(
        id=uuid.uuid4(), name="Lagoon Tours", is_active=True,
        internal_notes="", location=create_point(8.57, 81.23),
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def _save(obj, **changes):
    """What a form save does: every field rewritten, the point rebuilt."""
    for key, value in changes.items():
        setattr(obj, key, value)
    lat, lng = changes.pop("_coords", (8.57, 81.23))
    obj.location = create_point(lat, lng)


def test_an_unchanged_package_save_writes_nothing():
    db = FakeSession()
    package = _package()
    before = pa.snapshot(package, _PARTNER_PACKAGE_SCALARS)
    # Same values, different types: float for the Decimal, None for "", a
    # fresh list, a rebuilt geometry object for the same point.
    _save(package, price_amount=99.99, summary=None, tags=["kayak"])
    assert pa.package_updated(db, package, before, actor=pa.VENDOR) is None
    assert db.added == []


def test_a_real_edit_is_recorded():
    db = FakeSession()
    package = _package()
    before = pa.snapshot(package, _PARTNER_PACKAGE_SCALARS)
    _save(package, price_amount=120)
    payload = pa.package_updated(db, package, before, actor=pa.ADMIN)
    assert payload["kind"] == "package.updated"
    assert payload["title"] == "Sunset Kayak updated"
    assert payload["actor"] == "admin"
    assert len(db.added) == 1


def test_moving_the_meeting_point_is_a_change():
    package = _package()
    before = pa.snapshot(package, _PARTNER_PACKAGE_SCALARS)
    package.location = create_point(8.60, 81.20)
    assert pa.package_updated(FakeSession(), package, before, actor=pa.VENDOR)


def test_switching_a_package_off_says_so():
    package = _package()
    before = pa.snapshot(package, _PARTNER_PACKAGE_SCALARS)
    _save(package, is_active=False)
    payload = pa.package_updated(FakeSession(), package, before, actor=pa.ADMIN)
    assert payload["kind"] == "package.hidden"
    assert payload["title"] == "Sunset Kayak is now hidden"


def test_an_admin_only_vendor_edit_never_reaches_the_feed():
    """An internal note must not surface as "NexAround updated your profile"."""
    vendor = _vendor()
    before = pa.snapshot(vendor, _PARTNER_VENDOR_SCALARS + ("is_active",))
    vendor.internal_notes = "Late payer, chase monthly"
    vendor.sort_order = 3
    _save(vendor)
    assert pa.profile_updated(FakeSession(), vendor, before, actor=pa.ADMIN) is None


def test_suspending_and_restoring_a_listing_have_their_own_lines():
    vendor = _vendor()
    before = pa.snapshot(vendor, _PARTNER_VENDOR_SCALARS + ("is_active",))
    _save(vendor, is_active=False)
    assert pa.profile_updated(FakeSession(), vendor, before, actor=pa.ADMIN)["kind"] == "listing.suspended"

    before = pa.snapshot(vendor, _PARTNER_VENDOR_SCALARS + ("is_active",))
    _save(vendor, is_active=True)
    assert pa.profile_updated(FakeSession(), vendor, before, actor=pa.ADMIN)["kind"] == "listing.restored"


def test_new_enquiry_wording_matches_the_backfill():
    """Migration d5e6f7a8b9c0 builds the same text in SQL for old enquiries."""
    enquiry = SimpleNamespace(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), package_id=uuid.uuid4(),
        contact_name="Amara", package_title_snapshot="Sunset Kayak",
        party_size=4, preferred_date=date(2026, 10, 5),
    )
    payload = pa.enquiry_created(FakeSession(), enquiry)
    assert payload["title"] == "New enquiry from Amara"
    assert payload["body"] == "Sunset Kayak · 4 guests · 5 Oct 2026"
    assert payload["actor"] == "traveller"
    assert payload["actor_login_id"] is None


def test_a_vendor_action_carries_who_did_it():
    login = SimpleNamespace(id=uuid.uuid4(), display_name=None, email="priya@lagoon.lk")
    enquiry = SimpleNamespace(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), contact_name="Amara",
        package_title_snapshot=None, status="contacted",
    )
    payload = pa.enquiry_status(FakeSession(), enquiry, actor=pa.VENDOR, login=login)
    assert payload["title"] == "Amara's enquiry marked Contacted"
    assert payload["actor_login_id"] == str(login.id)
    assert payload["actor_name"] == "priya@lagoon.lk"


def test_announce_strips_the_routing_field(monkeypatch):
    sent = []

    async def fake_publish(vendor_id, event_type, data):
        sent.append((vendor_id, event_type, data))

    monkeypatch.setattr(pa.partner_events, "publish", fake_publish)
    payload = pa.record(FakeSession(), "v-1", "profile.updated", "Business profile updated", actor=pa.ADMIN)

    import asyncio
    asyncio.run(pa.announce(payload, None))
    assert len(sent) == 1
    vendor_id, event_type, data = sent[0]
    assert (vendor_id, event_type) == ("v-1", pa.ACTIVITY_CREATED)
    assert "vendor_id" not in data and data["title"] == "Business profile updated"
