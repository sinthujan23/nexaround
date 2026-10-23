"""Vendors see and answer requests: package, date, guests and price only.

* What the vendor reads (`_request_out`, the push/email/bell text) never holds
  who asked, how to reach them, where to pick them up or what they wrote.
* Confirming and cancelling move the status as an admin's would; another
  date leaves the request open for NexAround to take to the traveller.
* Only an open request can be answered, and only with what each answer needs.

No database: the functions work on the model objects, so plain stand-ins do.
"""
import uuid
from datetime import date, datetime, timezone
from types import SimpleNamespace

from app.api.v1.partner import _request_out
from app.services import enquiry_lifecycle as lc
from app.services import partner_activity
from app.schemas.partner import PartnerRequest

NOW = datetime(2026, 10, 22, 9, 0, tzinfo=timezone.utc)
TODAY = NOW.date()

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
        package_title_snapshot="Dolphin Watching", vendor_name_snapshot="Blue Ocean",
        preferred_date=date(2026, 10, 25), party_size=4, status=lc.NEW,
        price_option={"id": "a1", "label": "LKR 8,000 ($24) / person (min 3)", "amount": 8000,
                      "usd": 24, "basis": "per_person", "currency": "LKR", "min_people": 3},
        confirmed_date=None, confirmed_at=None, cancelled_at=None, cancellation_reason=None,
        late_cancellation=None, vendor_response=None, vendor_offered_date=None,
        vendor_response_reason=None, vendor_response_note=None, vendor_responded_at=None,
        offer_response=None, offer_responded_at=None,
        created_at=NOW, **TRAVELLER,
    )
    fields.update(overrides)
    row = SimpleNamespace(**fields)
    row.reference = f"#{row.id.hex[:6].upper()}"
    return row


def leaked(text: str) -> list:
    clues = list(TRAVELLER.values()) + ["Fahad", "Testname", "5551", "Hilton", "West Bay", "@", "WhatsApp"]
    return [c for c in clues if c.lower() in text.lower()]


def test_the_vendor_sees_what_when_how_many_and_the_price():
    e = enquiry()
    out = _request_out(e)
    assert out.package_title == "Dolphin Watching"
    assert out.preferred_date == date(2026, 10, 25) and out.party_size == 4
    # Their own price: never NexAround's dollar figure, which carries the commission.
    assert out.price_label == "LKR 8,000 / person (min 3)"
    assert out.reference == e.reference and out.can_answer
    assert leaked(out.model_dump_json()) == []


def test_the_vendor_view_has_no_field_for_the_traveller():
    names = set(PartnerRequest.model_fields)
    assert not names & {"contact_name", "contact_phone", "contact_email", "pickup_location",
                        "message", "user_id", "admin_notes", "vendor_response_note"}


def test_confirming_confirms_for_the_day_asked():
    e = enquiry()
    assert lc.vendor_response_error(e, lc.VENDOR_CONFIRMED, None, None, TODAY) is None
    event = lc.vendor_respond(e, lc.VENDOR_CONFIRMED, now=NOW)
    assert event == lc.CONFIRMED
    assert e.status == lc.CONFIRMED and e.confirmed_date == date(2026, 10, 25)
    assert e.vendor_response == lc.VENDOR_CONFIRMED and e.vendor_responded_at == NOW
    assert e.vendor_response_reason is None


def test_a_flexible_request_needs_the_day_to_confirm():
    e = enquiry(preferred_date=None)
    assert lc.vendor_response_error(e, lc.VENDOR_CONFIRMED, None, None, TODAY)
    assert lc.vendor_response_error(e, lc.VENDOR_CONFIRMED, date(2026, 11, 2), None, TODAY) is None


def test_another_date_leaves_it_open_for_nexaround():
    e = enquiry()
    assert lc.vendor_response_error(e, lc.VENDOR_OTHER_DATE, None, "fully_booked", TODAY)
    assert lc.vendor_response_error(e, lc.VENDOR_OTHER_DATE, date(2026, 10, 27), None, TODAY)
    assert lc.vendor_response_error(e, lc.VENDOR_OTHER_DATE, date(2026, 10, 1), "fully_booked", TODAY)
    assert lc.vendor_response_error(e, lc.VENDOR_OTHER_DATE, date(2026, 10, 25), "fully_booked", TODAY)
    when = date(2026, 10, 27)
    assert lc.vendor_response_error(e, lc.VENDOR_OTHER_DATE, when, "fully_booked", TODAY) is None
    event = lc.vendor_respond(e, lc.VENDOR_OTHER_DATE, now=NOW, when=when,
                              reason="fully_booked", note="Morning only")
    assert event is None
    assert e.status == lc.NEW and e.vendor_offered_date == when
    assert e.vendor_response_note == "Morning only"
    # Still open: NexAround may get them to confirm after all.
    assert _request_out(e).can_answer


def test_cancelling_tells_the_traveller_only_the_reason_label():
    e = enquiry()
    assert lc.vendor_response_error(e, lc.VENDOR_CANCELLED, None, None, TODAY)
    event = lc.vendor_respond(e, lc.VENDOR_CANCELLED, now=NOW, reason="weather",
                              note="Call me on +94 77 123 4567")
    assert event == lc.PROVIDER_CANCELLED and e.status == lc.PROVIDER_CANCELLED
    # The traveller's email shows cancellation_reason: the label, not the note.
    assert e.cancellation_reason == "Weather or sea conditions"
    assert e.vendor_response_note == "Call me on +94 77 123 4567"


def test_only_an_open_request_can_be_answered():
    for status in (lc.CONFIRMED, lc.CLOSED, lc.CUSTOMER_CANCELLED, lc.PROVIDER_CANCELLED):
        e = enquiry(status=status)
        assert lc.vendor_response_error(e, lc.VENDOR_CONFIRMED, None, None, TODAY)
        assert not _request_out(e).can_answer
    assert lc.vendor_response_error(enquiry(), "maybe", None, None, TODAY)


def test_the_vendors_own_lines_name_no_traveller():
    for action, extra in ((lc.VENDOR_CONFIRMED, {}),
                          (lc.VENDOR_OTHER_DATE, {"when": date(2026, 10, 27), "reason": "weather"}),
                          (lc.VENDOR_CANCELLED, {"reason": "fully_booked"})):
        e = enquiry()
        lc.vendor_respond(e, action, now=NOW, **extra)
        title, body = partner_activity.answer_text(e, today=TODAY)
        assert "Dolphin Watching" in title
        assert leaked(title + body) == []
    title, body = partner_activity.request_text(enquiry(), today=TODAY)
    assert body == "Sun 25 Oct · 4 guests. Confirm it or offer another date in the vendor portal."


def _offered(when=date(2026, 10, 27)):
    e = enquiry()
    lc.vendor_respond(e, lc.VENDOR_OTHER_DATE, now=NOW, when=when, reason="fully_booked")
    return e


def test_an_offered_date_waits_for_the_traveller():
    e = _offered()
    assert lc.pending_offer(e) == date(2026, 10, 27)
    assert lc.offer_response_error(e, TODAY) is None
    assert lc.offer_response_error(enquiry(), TODAY), "nothing was offered"


def test_accepting_confirms_the_booking_for_the_offered_date():
    e = _offered()
    event = lc.respond_to_offer(e, True, now=NOW)
    assert event == lc.CONFIRMED
    assert e.status == lc.CONFIRMED and e.confirmed_date == date(2026, 10, 27)
    assert e.offer_response == lc.OFFER_ACCEPTED and lc.pending_offer(e) is None
    assert lc.offer_response_error(e, TODAY), "it can only be answered once"


def test_declining_cancels_the_request():
    e = _offered()
    event = lc.respond_to_offer(e, False, now=NOW)
    assert event == lc.CUSTOMER_CANCELLED and e.status == lc.CUSTOMER_CANCELLED
    assert e.cancellation_reason == lc.DECLINED_OFFER_REASON
    # Never confirmed, so never a late cancellation.
    assert not e.late_cancellation
    title, body = partner_activity.update_text(e, lc.CUSTOMER_CANCELLED, today=TODAY)
    assert title == "Other date declined: Dolphin Watching"
    assert leaked(title + body) == []


def test_a_past_offered_date_cannot_be_accepted():
    e = _offered(when=date(2026, 10, 23))
    assert lc.offer_response_error(e, date(2026, 10, 24))


def test_a_new_offer_asks_the_traveller_again():
    e = _offered()
    e.offer_response = lc.OFFER_ACCEPTED  # as if answered, status left open by an admin
    e.status = lc.NEW
    lc.vendor_respond(e, lc.VENDOR_OTHER_DATE, now=NOW, when=date(2026, 10, 29), reason="weather")
    assert e.offer_response is None and lc.pending_offer(e) == date(2026, 10, 29)
