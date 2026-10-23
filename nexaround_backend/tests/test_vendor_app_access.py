"""Vendors managing their listing from the app, and what they hear of requests.

A vendor learns THAT a request came in - package, date, guests - and never
who sent it: Nexaround contacts the traveller, so the booking (and the
commission) cannot go around it. Pure functions only - no DB, no network.
"""
import uuid
from datetime import date
from types import SimpleNamespace

from app.api.v1.partner import _claims
from app.core.security import create_access_token, decode_token
from app.models.experience import VendorUser
from app.services import partner_activity
from app.services.partner_auth import claims_ok

TODAY = date(2026, 10, 21)

# Every traveller detail a request holds, each easy to spot in a string.
TRAVELLER = {
    "contact_name": "Fahad Testname",
    "contact_phone": "+97455512345",
    "contact_email": "fahad.testname@example.com",
    "pickup_location": "Hilton Doha, West Bay",
    "message": "Please call me on +974 5551 2345 or WhatsApp",
}


def enquiry(**overrides):
    fields = dict(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(), package_id=uuid.uuid4(),
        package_title_snapshot="Desert Safari", preferred_date=date(2026, 10, 25),
        party_size=4, **TRAVELLER,
    )
    fields.update(overrides)
    return SimpleNamespace(**fields)


def leaked(text: str) -> list:
    """The traveller details (or recognisable parts of them) found in `text`."""
    clues = list(TRAVELLER.values()) + ["Fahad", "Testname", "5551", "55512345", "Hilton", "West Bay", "@"]
    return [c for c in clues if c.lower() in text.lower()]


def test_the_request_line_says_what_was_asked_for_and_nothing_of_who():
    title, body = partner_activity.request_text(enquiry(), today=TODAY)
    assert title == "New request: Desert Safari"
    assert body == "Sun 25 Oct · 4 guests. Confirm it or offer another date in the vendor portal."
    assert leaked(title + body) == []


def test_the_feed_line_carries_no_traveller_detail_in_any_field():
    class Session:
        def add(self, row):
            self.row = row

    db = Session()
    payload = partner_activity.request_received(db, enquiry())
    assert db.row.kind == "request.received"
    assert payload["actor_name"] is None
    assert leaked(" ".join(str(v) for v in payload.values() if v)) == []


def test_a_flexible_request_for_one_guest():
    _, body = partner_activity.request_text(enquiry(preferred_date=None, party_size=1), today=TODAY)
    assert body == "Flexible date · 1 guest. Confirm it or offer another date in the vendor portal."
    _, body = partner_activity.request_text(enquiry(preferred_date=None, party_size=None), today=TODAY)
    assert body == "Flexible date. Confirm it or offer another date in the vendor portal."


def test_a_date_in_another_year_says_the_year():
    _, body = partner_activity.request_text(enquiry(preferred_date=date(2027, 1, 3)), today=TODAY)
    assert body.startswith("Sun 3 Jan 2027 · 4 guests.")


def test_the_web_portal_does_not_hide_the_new_line():
    # partner._shown drops "enquiry.%" kinds: those old lines name the traveller.
    assert not "request.received".startswith("enquiry.")


def test_an_app_login_is_named_after_the_person_not_an_email():
    assert VendorUser(email="owner@desert.qa").label == "owner@desert.qa"
    assert VendorUser(app_user_id=uuid.uuid4(), display_name="Ilham").label == "Ilham (app)"
    assert VendorUser(app_user_id=uuid.uuid4()).label == "App user (app)"


def test_an_app_session_token_is_a_partner_token_for_that_login_only():
    vendor_id, login_id, traveller_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    login = VendorUser(id=login_id, vendor_id=vendor_id, app_user_id=traveller_id)
    payload = decode_token(create_access_token(_claims(login, uuid.uuid4())))

    assert claims_ok(payload, vendor_id)
    assert not claims_ok(payload, uuid.uuid4())
    # Names the vendor login, never the traveller account: the token cannot
    # be used on traveller endpoints, which look `sub` up in `users`.
    assert payload["sub"] == str(login_id)
    assert str(traveller_id) not in str(payload.values())


def test_a_confirmation_says_the_booked_day_and_nothing_of_who():
    confirmed = enquiry(confirmed_date=date(2026, 10, 26), confirmed_at=TODAY)
    title, body = partner_activity.update_text(confirmed, "confirmed", today=TODAY)
    assert title == "Booking confirmed: Desert Safari"
    assert body == "Mon 26 Oct · 4 guests. NexAround will be in touch with the details."
    assert leaked(title + body) == []


def test_a_cancellation_says_whether_it_was_booked():
    asked = enquiry(confirmed_date=None, confirmed_at=None)
    booked = enquiry(confirmed_date=date(2026, 10, 26), confirmed_at=TODAY)
    for event in ("provider_cancelled", "customer_cancelled"):
        title, body = partner_activity.update_text(asked, event, today=TODAY)
        assert title == "Request cancelled: Desert Safari"
        assert body == "Sun 25 Oct · 4 guests. Nothing to do on your side."
        assert partner_activity.update_text(booked, event, today=TODAY)[0] == "Booking cancelled: Desert Safari"
        assert leaked(title + body) == []


def test_only_confirmations_and_cancellations_reach_the_vendor():
    class Session:
        def add(self, row):
            self.row = row

    db = Session()
    quiet = enquiry(confirmed_date=None, confirmed_at=None)
    for event in ("contacted", "closed", "new", "spam"):
        assert partner_activity.request_updated(db, quiet, event) is None
    payload = partner_activity.request_updated(db, quiet, "provider_cancelled")
    assert db.row.kind == "request.cancelled" and payload["actor"] == "admin"
    assert leaked(" ".join(str(v) for v in payload.values() if v)) == []
