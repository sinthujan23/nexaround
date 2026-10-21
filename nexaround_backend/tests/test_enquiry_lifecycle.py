"""The life of an experience request: confirmation, cancellation, 72 hours."""

from datetime import date, datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services import enquiry_lifecycle as lc

NOW = datetime(2026, 10, 16, 9, 0, tzinfo=timezone.utc)


def enquiry(status=lc.NEW, preferred=None, confirmed=None):
    return SimpleNamespace(
        status=status, preferred_date=preferred, confirmed_date=confirmed,
        confirmed_at=None, cancelled_at=None, cancellation_reason=None,
        late_cancellation=None,
    )


# --- The 72-hour window -----------------------------------------------------

def test_the_free_period_ends_three_days_before_the_booked_day():
    assert lc.free_cancellation_last_day(date(2026, 10, 20)) == date(2026, 10, 17)


def test_nothing_booked_has_no_free_period():
    assert lc.free_cancellation_last_day(None) is None


def test_cancelling_a_confirmed_booking_in_time_is_not_late():
    booked = date(2026, 10, 20)
    on_last_free_day = datetime(2026, 10, 17, 23, 0, tzinfo=timezone.utc)
    assert lc.is_late_cancellation(lc.CONFIRMED, booked, on_last_free_day) is False


def test_cancelling_a_confirmed_booking_inside_72_hours_is_late():
    booked = date(2026, 10, 20)
    two_days_before = datetime(2026, 10, 18, 13, 0, tzinfo=timezone.utc)
    assert lc.is_late_cancellation(lc.CONFIRMED, booked, two_days_before) is True


def test_the_last_free_day_lasts_until_it_ends_everywhere_on_earth():
    # Midnight UTC is still the last free day in the Americas (and at UTC-12
    # until noon), so the app there showed "free": the server must agree.
    booked = date(2026, 10, 20)
    assert lc.is_late_cancellation(
        lc.CONFIRMED, booked, datetime(2026, 10, 18, 11, 59, tzinfo=timezone.utc)
    ) is False
    assert lc.is_late_cancellation(
        lc.CONFIRMED, booked, datetime(2026, 10, 18, 12, 0, tzinfo=timezone.utc)
    ) is True


@pytest.mark.parametrize("status", [lc.NEW, lc.CONTACTED])
def test_cancelling_a_request_not_yet_confirmed_is_never_late(status):
    the_day_itself = datetime(2026, 10, 20, 8, 0, tzinfo=timezone.utc)
    assert lc.is_late_cancellation(status, date(2026, 10, 20), the_day_itself) is False


# --- Who may do what ----------------------------------------------------------

@pytest.mark.parametrize("status", [lc.NEW, lc.CONTACTED, lc.CONFIRMED])
def test_a_traveller_can_cancel_an_open_request_or_booking(status):
    assert lc.customer_cancel_error(status) is None


@pytest.mark.parametrize("status", [lc.CLOSED, lc.CUSTOMER_CANCELLED, lc.PROVIDER_CANCELLED])
def test_a_traveller_cannot_cancel_what_is_already_over(status):
    assert lc.customer_cancel_error(status)


def test_a_vendor_cannot_say_the_traveller_cancelled():
    assert lc.vendor_status_error(lc.NEW, lc.CUSTOMER_CANCELLED, None)


@pytest.mark.parametrize("cancelled", [lc.CUSTOMER_CANCELLED, lc.PROVIDER_CANCELLED])
def test_a_vendor_cannot_reopen_a_cancellation(cancelled):
    assert lc.vendor_status_error(cancelled, lc.CONTACTED, None)


def test_a_vendor_confirms_only_with_a_date():
    assert lc.vendor_status_error(lc.NEW, lc.CONFIRMED, None)
    assert lc.vendor_status_error(lc.NEW, lc.CONFIRMED, date(2026, 10, 20)) is None


def test_the_confirmed_date_defaults_to_the_preferred_one():
    e = enquiry(preferred=date(2026, 10, 20))
    assert lc.booked_date(e) == date(2026, 10, 20)
    assert lc.booked_date(e, date(2026, 10, 22)) == date(2026, 10, 22)


# --- Applying a change ----------------------------------------------------------

def test_confirming_dates_and_stamps_the_booking_and_tells_the_traveller():
    e = enquiry(lc.CONTACTED, preferred=date(2026, 10, 20))
    event = lc.apply_status(e, lc.CONFIRMED, now=NOW)

    assert event == lc.CONFIRMED
    assert (e.status, e.confirmed_date, e.confirmed_at) == (lc.CONFIRMED, date(2026, 10, 20), NOW)


def test_moving_a_confirmed_date_tells_the_traveller_again():
    e = enquiry(lc.CONFIRMED, preferred=date(2026, 10, 20), confirmed=date(2026, 10, 20))
    e.confirmed_at = NOW
    later = NOW + timedelta(hours=2)

    assert lc.apply_status(e, lc.CONFIRMED, now=later, confirmed_date=date(2026, 10, 21)) == lc.CONFIRMED
    assert e.confirmed_date == date(2026, 10, 21)
    assert e.confirmed_at == NOW  # still when it was first confirmed


def test_saving_the_same_confirmation_tells_nobody():
    e = enquiry(lc.CONFIRMED, confirmed=date(2026, 10, 20))
    assert lc.apply_status(e, lc.CONFIRMED, now=NOW) is None


def test_a_traveller_cancelling_late_is_recorded_with_the_reason():
    e = enquiry(lc.CONFIRMED, confirmed=date(2026, 10, 17))
    event = lc.apply_status(e, lc.CUSTOMER_CANCELLED, now=NOW, reason="  Flight moved ")

    assert event == lc.CUSTOMER_CANCELLED
    assert e.cancelled_at == NOW
    assert e.cancellation_reason == "Flight moved"
    assert e.late_cancellation is True


def test_a_provider_cancellation_is_never_marked_late():
    e = enquiry(lc.CONFIRMED, confirmed=date(2026, 10, 17))
    assert lc.apply_status(e, lc.PROVIDER_CANCELLED, now=NOW) == lc.PROVIDER_CANCELLED
    assert e.late_cancellation is None


def test_an_admin_reopening_a_cancellation_clears_it():
    e = enquiry(lc.CUSTOMER_CANCELLED)
    e.cancelled_at, e.cancellation_reason, e.late_cancellation = NOW, "x", True

    lc.apply_status(e, lc.CONTACTED, now=NOW)

    assert (e.cancelled_at, e.cancellation_reason, e.late_cancellation) == (None, None, None)


# --- Schemas ------------------------------------------------------------------

def test_every_view_of_an_enquiry_carries_the_booking():
    from app.schemas.experience import ExperienceEnquiryAdminResponse, MyEnquiryOut

    fields = {
        "confirmed_date", "cancelled_at", "cancellation_reason",
        "late_cancellation", "free_cancellation_last_day",
    }
    for schema in (ExperienceEnquiryAdminResponse, MyEnquiryOut):
        assert fields <= set(schema.model_fields), schema.__name__


def test_statuses_fit_the_column():
    assert all(len(s) <= 20 for s in lc.ALL_STATUSES)


def test_the_terms_tell_travellers_how_to_cancel_in_the_app():
    from app.services import legal_texts

    assert "My requests" in legal_texts.CUSTOMER_BODY
    assert "partner portal" in legal_texts.PROVIDER_BODY
