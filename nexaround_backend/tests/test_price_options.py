"""Several prices per package: "LKR 30,000 per trip (max 7)" or
"LKR 8,000 per person (min 3)"."""
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.schemas.experience import PriceOption
from app.services.experience_format import (
    apply_price_options, legacy_price_options, normalize_price_options,
    option_label, pick_price_option, price_options_for_save,
)

TRIP = {"id": "aaaa1111", "amount": 30000.0, "usd": 90.0, "basis": "per_group",
        "min_people": None, "max_people": None}
PER_HEAD = {"id": "bbbb2222", "amount": 8000.0, "usd": 24.0, "basis": "per_person",
            "min_people": 3, "max_people": None}


def test_each_option_reads_like_the_card():
    assert option_label(TRIP, "LKR", 7) == "LKR 30,000 ($90) / group (max 7)"
    assert option_label(PER_HEAD, "LKR", 7) == "LKR 8,000 ($24) / person (min 3)"


def test_an_hourly_price_reads_per_hour():
    option = {"id": "cccc3333", "amount": 13000.0, "usd": 39.0, "basis": "per_hour",
              "min_people": None, "max_people": None}
    assert option_label(option, "LKR", 4) == "LKR 13,000 ($39) / hour"
    assert PriceOption(amount=13000, basis="per_hour").basis == "per_hour"


def test_a_group_price_with_a_minimum_shows_both():
    option = {**TRIP, "min_people": 2, "max_people": 5}
    assert option_label(option, "LKR", 7) == "LKR 30,000 ($90) / group (min 2, max 5)"


def test_new_options_get_ids_and_known_ones_keep_theirs():
    out = normalize_price_options(
        [{"id": "aaaa1111", "amount": 1, "basis": "per_group"}, {"amount": 2}],
        [TRIP],
    )
    assert out[0]["id"] == "aaaa1111"
    assert out[1]["id"] and out[1]["id"] != "aaaa1111"
    assert out[1]["basis"] == "per_person"


def test_an_invented_or_repeated_id_is_replaced():
    out = normalize_price_options(
        [{"id": "aaaa1111", "amount": 1}, {"id": "aaaa1111", "amount": 2}, {"id": "zzz", "amount": 3}],
        [TRIP],
    )
    ids = [o["id"] for o in out]
    assert ids[0] == "aaaa1111"
    assert len(set(ids)) == 3 and "zzz" not in ids


def test_a_vendor_save_keeps_the_admins_dollars():
    out = normalize_price_options(
        [{"id": "aaaa1111", "amount": 31000, "usd": 1}, {"amount": 5000, "usd": 99}],
        [TRIP], keep_usd=True,
    )
    assert out[0]["usd"] == 90.0
    assert out[1]["usd"] is None


def test_an_older_form_replaces_only_the_first_option():
    out = legacy_price_options([TRIP, PER_HEAD], 32000, 95, "per_group")
    assert out[0]["id"] == "aaaa1111" and out[0]["amount"] == 32000.0 and out[0]["usd"] == 95.0
    assert out[1] == PER_HEAD


def test_an_older_form_clearing_the_price_means_on_request():
    assert legacy_price_options([TRIP, PER_HEAD], None, None, "per_group") == []


def test_a_vendors_older_form_keeps_the_dollars_too():
    data = SimpleNamespace(price_options=None, price_amount=32000, price_basis="per_group")
    out = price_options_for_save(data, [TRIP], vendor=True)
    assert out[0]["usd"] == 90.0


def test_the_first_option_is_mirrored_for_older_apps():
    package = SimpleNamespace(price_amount=None, price_usd=None, price_basis="per_person")
    apply_price_options(package, [TRIP, PER_HEAD])
    assert (package.price_amount, package.price_usd, package.price_basis) == (30000.0, 90.0, "per_group")
    apply_price_options(package, [])
    assert package.price_amount is None and package.price_usd is None


def test_a_request_names_its_option_and_keeps_a_copy():
    snapshot, error = pick_price_option([TRIP, PER_HEAD], "bbbb2222", 3, "LKR", 7)
    assert error is None
    assert snapshot["label"] == "LKR 8,000 ($24) / person (min 3)"
    assert snapshot["currency"] == "LKR" and snapshot["amount"] == 8000.0


def test_an_older_app_gets_the_first_option():
    snapshot, error = pick_price_option([TRIP, PER_HEAD], None, 2, "LKR", 7)
    assert error is None and snapshot["id"] == "aaaa1111"


@pytest.mark.parametrize("option_id,guests,message", [
    ("bbbb2222", 2, "at least 3"),
    ("aaaa1111", 8, "up to 7"),
    ("gone0000", 3, "changed"),
])
def test_guests_must_fit_the_option(option_id, guests, message):
    snapshot, error = pick_price_option([TRIP, PER_HEAD], option_id, guests, "LKR", 7)
    assert snapshot is None and message in error


def test_price_on_request_has_nothing_to_pick():
    assert pick_price_option([], None, 4, "LKR", 7) == (None, None)


def test_min_above_max_is_refused():
    with pytest.raises(ValidationError):
        PriceOption(amount=1, min_people=5, max_people=3)


def test_an_unknown_basis_is_refused():
    with pytest.raises(ValidationError):
        PriceOption(amount=1, basis="per_day")


# --- The currency the traveller picks in the app (display only) --------------

from app.services.experience_format import convert_price, display_label  # noqa: E402

RATES = {"LKR": 331.7, "INR": 95.0, "QAR": 3.64}
DOHA = {"id": "dddd4444", "amount": 475.0, "usd": 130.0, "basis": "per_group",
        "min_people": None, "max_people": None}


def test_dollars_use_the_typed_price_exactly():
    assert display_label(DOHA, "QAR", 6, "USD", RATES) == "USD 130 / group (max 6)"


def test_other_currencies_go_through_the_typed_dollars_and_say_approximately():
    assert display_label(DOHA, "QAR", 6, "INR", RATES) == "≈ INR 12,350 / group (max 6)"


def test_the_vendors_own_currency_is_exact():
    assert display_label(PER_HEAD, "LKR", 7, "LKR", RATES) == "LKR 8,000 / person (min 3)"


def test_without_typed_dollars_the_daily_rate_is_used():
    no_usd = {**PER_HEAD, "usd": None}
    value, approximate = convert_price(8000, "LKR", None, "USD", RATES)
    assert approximate and round(value, 2) == round(8000 / 331.7, 2)
    assert display_label(no_usd, "LKR", 7, "USD", RATES) == "≈ USD 24 / person (min 3)"


def test_a_starting_price_keeps_from_in_front():
    option = {**PER_HEAD, "basis": "from", "min_people": None}
    assert display_label(option, "LKR", 7, "INR", RATES) == "From ≈ INR 2,280"


def test_no_choice_or_no_rate_means_no_display_label():
    assert display_label(DOHA, "QAR", 6, None, RATES) is None
    assert display_label(DOHA, "QAR", 6, "EUR", RATES) is None
