"""Experiences marketplace: pure-function rules.

`tests/` in this project is pure-function only — no database, no network, no
TestClient — so this file covers the logic that was deliberately pushed out of
the routers and into `app.services.experience_format`.

The contract test at the bottom is the important one. The Dart models parse
with `json['key'] ?? default`, so renaming a response field does not raise
anywhere: it silently becomes a default, and with no Flutter toolchain on the
build box nothing else would catch it.
"""

from datetime import date, timedelta

import pytest

from app.services.experience_format import (
    DEFAULT_BOOKING_WINDOW_DAYS,
    MAX_BOOKING_WINDOW_DAYS,
    NEARBY_THRESHOLD_M,
    booking_window_error,
    format_duration,
    format_price,
    is_nearby,
    is_published,
    normalize_phone,
    resolve_package_point,
    validate_enquiry_payload,
    whatsapp_number,
)


# --- The coordinate cascade -------------------------------------------------

def test_a_package_following_its_vendor_uses_the_vendor_point():
    assert resolve_package_point(6.9, 79.8, True) == (6.9, 79.8)


def test_a_package_following_its_vendor_ignores_a_stale_override():
    # The override columns may still hold an old meeting point after the admin
    # unticks the box; the flag wins, not the leftover data.
    assert resolve_package_point(6.9, 79.8, True, 1.0, 2.0) == (6.9, 79.8)


def test_a_package_with_its_own_meeting_point_keeps_it():
    assert resolve_package_point(6.9, 79.8, False, 1.0, 2.0) == (1.0, 2.0)


def test_a_package_claiming_its_own_point_but_given_none_falls_back():
    # The column is NOT NULL and the row has to go somewhere; the vendor is the
    # only sane answer.
    assert resolve_package_point(6.9, 79.8, False, None, None) == (6.9, 79.8)
    assert resolve_package_point(6.9, 79.8, False, 1.0, None) == (6.9, 79.8)


@pytest.mark.parametrize(
    "vendor_active,package_active,expected",
    [(True, True, True), (True, False, False), (False, True, False), (False, False, False)],
)
def test_a_package_is_only_published_when_its_vendor_is(
    vendor_active, package_active, expected
):
    assert is_published(vendor_active, package_active) is expected


# --- The "nothing nearby" rule ----------------------------------------------

def test_a_result_inside_the_threshold_is_nearby():
    assert is_nearby(4_200) is True
    assert is_nearby(NEARBY_THRESHOLD_M) is True


def test_a_result_beyond_the_threshold_is_not_nearby():
    assert is_nearby(NEARBY_THRESHOLD_M + 1) is False
    assert is_nearby(8_666_946) is False


def test_no_results_at_all_is_not_nearby():
    assert is_nearby(None) is False


# --- Price and duration formatting ------------------------------------------

@pytest.mark.parametrize(
    "amount,currency,basis,expected",
    [
        (4500, "LKR", "per_person", "LKR 4,500 / person"),
        (7500, "INR", "per_group", "INR 7,500 / group"),
        (499, "QAR", "per_person", "QAR 499 / person"),
        (45, "USD", "per_person", "USD 45 / person"),
        (180, "USD", "per_group", "USD 180 / group"),
        (45, "USD", "from", "From USD 45"),
        (45.5, "USD", "per_person", "USD 45.50 / person"),
        (1234567, "USD", "per_person", "USD 1,234,567 / person"),
        (499, "qar", "per_person", "QAR 499 / person"),
    ],
)
def test_a_price_reads_the_way_the_card_shows_it(amount, currency, basis, expected):
    assert format_price(amount, currency, basis) == expected


@pytest.mark.parametrize(
    "amount,currency,basis,max_people,expected",
    [
        (499, "QAR", "per_group", 4, "QAR 499 / group (max 4)"),
        (7500, "INR", "per_group", 6, "INR 7,500 / group (max 6)"),
        (7500, "INR", "per_group", None, "INR 7,500 / group"),
        # Only a group price carries the size; a per-person price does not.
        (2000, "LKR", "per_person", 5, "LKR 2,000 / person"),
        (45, "USD", "from", 8, "From USD 45"),
    ],
)
def test_a_group_price_carries_the_group_size(amount, currency, basis, max_people, expected):
    assert format_price(amount, currency, basis, max_people) == expected


@pytest.mark.parametrize(
    "amount,currency,basis,max_people,usd,expected",
    [
        (499, "QAR", "per_group", 4, 137, "QAR 499 ($137) / group (max 4)"),
        (7500, "INR", "per_group", 6, 90, "INR 7,500 ($90) / group (max 6)"),
        (2000, "LKR", "per_person", None, 6.5, "LKR 2,000 ($6.50) / person"),
        (3000, "INR", "from", None, 36, "From INR 3,000 ($36)"),
        # A dollar price has no bracket, and an empty USD field shows none.
        (40, "USD", "per_person", None, 40, "USD 40 / person"),
        (499, "QAR", "per_group", 4, None, "QAR 499 / group (max 4)"),
    ],
)
def test_the_typed_dollar_price_follows_in_brackets(
    amount, currency, basis, max_people, usd, expected
):
    assert format_price(amount, currency, basis, max_people, usd) == expected


def test_on_request_ignores_the_dollar_price():
    assert format_price(None, "QAR", "per_group", 4, 137) == "Price on request"


def test_a_missing_price_reads_as_on_request():
    assert format_price(None) == "Price on request"
    assert format_price(100, "USD", "on_request") == "Price on request"


def test_an_unknown_currency_falls_back_to_its_code():
    assert format_price(50, "XYZ", "per_person") == "XYZ 50 / person"


@pytest.mark.parametrize(
    "minutes,expected",
    [(90, "1h 30m"), (60, "1h"), (45, "45m"), (120, "2h"), (0, ""), (None, "")],
)
def test_a_duration_reads_in_hours_and_minutes(minutes, expected):
    assert format_duration(minutes) == expected


# --- Phone handling ---------------------------------------------------------

def test_a_whatsapp_number_has_no_plus_or_spaces():
    # wa.me rejects a leading '+', tel: accepts it — the two must differ.
    assert whatsapp_number("+94 77 123 4567") == "94771234567"
    assert normalize_phone("+94 77 123 4567") == "+94771234567"


def test_a_number_too_short_to_dial_is_rejected():
    assert whatsapp_number("123") is None
    assert normalize_phone("123") is None
    assert whatsapp_number(None) is None
    assert whatsapp_number("") is None


# --- Enquiry validation -----------------------------------------------------

def test_a_complete_enquiry_passes():
    assert validate_enquiry_payload({
        "contact_name": "Test Traveller",
        "contact_phone": "+94 71 555 0000",
        "contact_email": "a@b.com",
        "party_size": 4,
    }) == []


def test_an_enquiry_without_a_usable_name_or_phone_is_rejected():
    errors = validate_enquiry_payload({"contact_name": "A", "contact_phone": "12"})
    assert len(errors) == 2


def test_an_enquiry_with_a_malformed_email_is_rejected():
    errors = validate_enquiry_payload({
        "contact_name": "Traveller", "contact_phone": "+94715550000",
        "contact_email": "not-an-email",
    })
    assert errors and "email" in errors[0].lower()


def test_an_absent_email_is_fine_because_phone_is_the_required_channel():
    assert validate_enquiry_payload({
        "contact_name": "Traveller", "contact_phone": "+94715550000",
    }) == []


@pytest.mark.parametrize("size", [0, 101])
def test_an_implausible_party_size_is_rejected(size):
    errors = validate_enquiry_payload({
        "contact_name": "Traveller", "contact_phone": "+94715550000",
        "party_size": size,
    })
    assert errors


# --- Booking window ---------------------------------------------------------

TODAY = date(2026, 12, 1)


def test_no_date_is_always_fine():
    assert booking_window_error(None, TODAY, 30) is None


def test_a_date_inside_the_packages_window_passes():
    assert booking_window_error(TODAY + timedelta(days=30), TODAY, 30) is None


def test_a_date_beyond_the_packages_window_is_refused():
    error = booking_window_error(TODAY + timedelta(days=45), TODAY, 30)
    assert error == "This experience can only be booked up to 30 days ahead."


def test_a_package_without_a_window_gets_the_platform_default():
    last = TODAY + timedelta(days=DEFAULT_BOOKING_WINDOW_DAYS)
    assert booking_window_error(last, TODAY, None) is None
    assert booking_window_error(last + timedelta(days=2), TODAY, None)


def test_a_traveller_a_day_ahead_of_utc_is_not_refused_their_last_day():
    """Their calendar's last day is the server's last day plus one."""
    assert booking_window_error(TODAY + timedelta(days=31), TODAY, 30) is None


def test_a_traveller_a_day_behind_utc_can_still_ask_for_their_today():
    assert booking_window_error(TODAY - timedelta(days=1), TODAY, 30) is None


def test_a_date_that_has_passed_is_refused():
    assert booking_window_error(TODAY - timedelta(days=2), TODAY, 30)


def test_the_partner_and_admin_forms_accept_the_same_windows():
    from pydantic import ValidationError

    from app.schemas.experience import ExperiencePackageBase
    from app.schemas.partner import PartnerPackageBase

    for schema in (ExperiencePackageBase, PartnerPackageBase):
        assert schema(title="Boat", booking_window_days=30).booking_window_days == 30
        assert schema(title="Boat").booking_window_days is None
        for bad in (0, MAX_BOOKING_WINDOW_DAYS + 1):
            with pytest.raises(ValidationError):
                schema(title="Boat", booking_window_days=bad)


# --- Client/server contract -------------------------------------------------

# Every key the Dart ExperiencePackageModel.fromJson reads. Dart parses with
# `json['key'] ?? default`, so a rename here is silent on the client: the card
# just renders a blank price or a zero distance forever. Keep this list and
# `experience_model.dart` in lockstep.
PACKAGE_CARD_KEYS = {
    "id", "title", "summary", "category", "vendor_id", "vendor_name",
    "vendor_whatsapp", "vendor_instagram", "vendor_facebook", "vendor_x",
    "cover_photo_url", "photo_count", "price_amount", "price_currency",
    "price_basis", "price_label", "duration_minutes", "duration_label",
    "latitude", "longitude", "distance_m", "tags", "region_label",
    "rating_avg", "rating_count", "max_participants", "country_code",
    "country_name", "price_options",
}

NEARBY_RESPONSE_KEYS = {
    "packages", "total", "limit", "offset", "nearest_distance_m",
    "has_nearby", "nearby_threshold_m", "country_mode",
}


def test_the_package_card_still_carries_every_field_the_app_parses():
    from app.schemas.experience import ExperiencePackageCard

    assert set(ExperiencePackageCard.model_fields.keys()) == PACKAGE_CARD_KEYS


def test_the_nearby_response_still_carries_every_field_the_app_parses():
    from app.schemas.experience import ExperienceNearbyResponse

    assert set(ExperienceNearbyResponse.model_fields.keys()) == NEARBY_RESPONSE_KEYS


def test_the_package_detail_extends_the_card_rather_than_replacing_it():
    from app.schemas.experience import ExperiencePackageCard, ExperiencePackageDetail

    detail = set(ExperiencePackageDetail.model_fields.keys())
    assert PACKAGE_CARD_KEYS <= detail
    assert {"description", "photo_urls", "video_urls", "vendor", "inclusions"} <= detail


def test_the_vendor_email_is_never_exposed_to_the_app():
    # It is the enquiry notification destination, not a public contact channel.
    from app.schemas.experience import ExperienceVendorPublic

    fields = set(ExperienceVendorPublic.model_fields.keys())
    assert "contact_email" not in fields
    assert "internal_notes" not in fields
    assert {
        "contact_phone",
        "contact_whatsapp",
        "contact_instagram",
        "contact_facebook",
        "contact_x",
    } <= fields


# --- Vendors listed by country only ------------------------------------------

def test_a_package_following_a_vendor_with_no_point_has_no_point():
    assert resolve_package_point(None, None, True) == (None, None)


def test_a_package_with_its_own_point_keeps_it_when_the_vendor_has_none():
    assert resolve_package_point(None, None, False, 6.9, 79.8) == (6.9, 79.8)


def test_a_vendor_always_needs_a_country():
    from app.services.experience_format import vendor_place_problem

    assert vendor_place_problem(6.9, 79.8, "LK") is None
    assert vendor_place_problem(None, None, "LK") is None
    assert vendor_place_problem(6.9, 79.8, None)
    assert vendor_place_problem(None, None, None)
    assert vendor_place_problem(None, None, "  ")


def test_half_a_point_is_refused_even_with_a_country():
    from app.services.experience_format import vendor_place_problem

    assert vendor_place_problem(6.9, None, "LK")
    assert vendor_place_problem(None, 79.8, "LK")


@pytest.mark.parametrize("value", [None, "", "true", "True", "garbage", "1"])
def test_country_mode_is_on_unless_explicitly_switched_off(value):
    from app.services.experience_format import parse_country_mode

    assert parse_country_mode(value) is True


@pytest.mark.parametrize("value", ["false", "False", " FALSE ", "0", "off", "no"])
def test_country_mode_can_be_switched_off(value):
    from app.services.experience_format import parse_country_mode

    assert parse_country_mode(value) is False


def test_the_app_models_can_be_built_for_a_vendor_with_no_point():
    import uuid

    from app.schemas.experience import ExperiencePackageCard, ExperienceVendorPublic

    vendor = ExperienceVendorPublic(id=uuid.uuid4(), name="Boat Co")
    assert vendor.latitude is None and vendor.longitude is None
    card = ExperiencePackageCard(
        id=uuid.uuid4(), title="Day trip", vendor_id=vendor.id, vendor_name="Boat Co",
    )
    assert card.latitude is None and card.distance_m is None


def test_the_vendor_forms_accept_a_vendor_with_only_a_country():
    from app.schemas.experience import ExperienceVendorCreate
    from app.schemas.partner import PartnerVendorProfileUpdate

    admin = ExperienceVendorCreate(name="Boat Co", country_code="LK")
    assert admin.latitude is None and admin.description is None and admin.contact_phone is None
    # Where the business is is the admin's alone: the vendor's form drops it.
    partner = PartnerVendorProfileUpdate(name="Boat Co", country_code="LK")
    assert "country_code" not in partner.model_dump()
