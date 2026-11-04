"""NexAround's commission: an admin types what the vendor gets and the
package's percentage; the traveller's price is worked out from the two, and
vendors only ever see their own amounts."""
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.schemas.experience import PriceOption
from app.services.experience_format import (
    apply_price_options, commission_of, commission_totals, normalize_price_options,
    pick_price_option, price_options_for_save, vendor_option_label, vendor_view_options,
    with_commission, without_commission,
)

# Blue Ocean's fishing trip: the vendor gets 12,000 and 15,000 an hour.
SMALL = {"id": "aaaa1111", "vendor_amount": 12000.0, "amount": 15000.0, "usd": 45.0,
         "basis": "per_hour", "min_people": 1, "max_people": 3}
LARGE = {"id": "bbbb2222", "vendor_amount": 15000.0, "amount": 18750.0, "usd": 56.0,
         "basis": "per_hour", "min_people": 4, "max_people": 6}


@pytest.mark.parametrize("vendor,percent,traveller", [
    (12000, 25, 15000.0),
    (15000, 25, 18750.0),
    (28000, 0, 28000.0),
    (13333, 25, 16666.25),
    (100, 12.5, 112.5),
])
def test_the_traveller_pays_the_vendors_amount_plus_the_commission(vendor, percent, traveller):
    assert with_commission(vendor, percent) == traveller


def test_the_commission_comes_back_out_of_an_older_forms_price():
    assert without_commission(18750, 25) == 15000.0
    assert without_commission(28000, None) == 28000.0


def test_an_admin_types_the_vendors_amount():
    out = normalize_price_options(
        [{"id": "aaaa1111", "vendor_amount": 12000, "amount": 1, "usd": 45, "basis": "per_hour"}],
        [SMALL], percent=25,
    )
    assert out[0]["vendor_amount"] == 12000.0
    assert out[0]["amount"] == 15000.0  # worked out, whatever the form sent
    assert out[0]["usd"] == 45.0


def test_an_admin_form_from_before_commissions_keeps_the_travellers_price():
    out = normalize_price_options([{"id": "aaaa1111", "amount": 15000}], [SMALL], percent=25)
    assert (out[0]["vendor_amount"], out[0]["amount"]) == (12000.0, 15000.0)


def test_a_vendor_types_their_own_amount_and_never_the_dollars():
    data = SimpleNamespace(price_options=[
        PriceOption(id="aaaa1111", amount=13000, basis="per_hour"),
    ])
    out = price_options_for_save(data, [SMALL], vendor=True, percent=25)
    assert out[0]["vendor_amount"] == 13000.0
    assert out[0]["amount"] == 16250.0
    assert out[0]["usd"] == 45.0


def test_saving_works_the_prices_out_again_with_the_packages_commission():
    package = SimpleNamespace(commission_percent=10, price_amount=None, price_usd=None,
                              price_basis="per_person")
    apply_price_options(package, [SMALL, LARGE])
    assert [o["amount"] for o in package.price_options] == [13200.0, 16500.0]
    assert [o["vendor_amount"] for o in package.price_options] == [12000.0, 15000.0]
    assert package.price_amount == 13200.0


def test_options_from_before_commissions_were_all_the_vendors():
    package = SimpleNamespace(commission_percent=0, price_amount=None, price_usd=None,
                              price_basis="per_person")
    apply_price_options(package, [{"id": "cccc3333", "amount": 7000.0, "usd": 21.0,
                                   "basis": "per_person"}])
    assert package.price_options[0]["vendor_amount"] == 7000.0
    assert package.price_options[0]["amount"] == 7000.0


def test_the_vendor_sees_only_their_own_amount():
    view = vendor_view_options([SMALL])
    assert view == [{"id": "aaaa1111", "amount": 12000.0, "basis": "per_hour",
                     "min_people": 1, "max_people": 3}]


def test_a_request_keeps_the_split_as_it_was():
    snapshot, error = pick_price_option([SMALL, LARGE], "bbbb2222", 5, "LKR", 6, 25)
    assert error is None
    assert snapshot["amount"] == 18750.0
    assert snapshot["vendor_amount"] == 15000.0
    assert snapshot["commission_amount"] == 3750.0
    assert snapshot["commission_percent"] == 25.0
    assert snapshot["label"].startswith("LKR 18,750")


def test_the_vendor_reads_their_own_amount_on_a_request():
    snapshot, _ = pick_price_option([SMALL, LARGE], "aaaa1111", 2, "LKR", 6, 25)
    assert vendor_option_label(snapshot) == "LKR 12,000 / hour"
    # A request from before commissions: all of it was the vendor's.
    assert vendor_option_label({"amount": 7000, "basis": "per_person", "currency": "LKR"}) \
        == "LKR 7,000 / person"
    assert commission_of({"amount": 7000, "currency": "LKR"}) == 0.0


def test_an_admin_price_needs_the_vendors_amount():
    with pytest.raises(ValidationError):
        PriceOption(basis="per_group")
    assert PriceOption(vendor_amount=28000).amount is None


def test_the_report_sums_each_vendor_and_currency():
    rows = [
        {"vendor_id": "v1", "vendor_name": "Blue Ocean", "currency": "LKR",
         "traveller_amount": 15000, "vendor_amount": 12000, "commission_amount": 3000},
        {"vendor_id": "v1", "vendor_name": "Blue Ocean", "currency": "LKR",
         "traveller_amount": 18750, "vendor_amount": 15000, "commission_amount": 3750},
        {"vendor_id": "v2", "vendor_name": "Elephant Track", "currency": "INR",
         "traveller_amount": None, "vendor_amount": None, "commission_amount": None},
    ]
    totals = commission_totals(rows)
    assert totals[0] == {
        "vendor_id": "v1", "vendor_name": "Blue Ocean", "currency": "LKR", "bookings": 2,
        "traveller_amount": 33750.0, "vendor_amount": 27000.0, "commission_amount": 6750.0,
    }
    assert totals[1]["bookings"] == 1 and totals[1]["commission_amount"] == 0.0
