"""Ratings and reviews: who may review, how a rating reads, what each side sees."""
from datetime import date, timedelta

import pytest
from pydantic import ValidationError

from app.schemas.experience import (
    ExperiencePackageCard, MyEnquiryOut, ReviewCreate, ReviewPublic,
)
from app.schemas.partner import PartnerReviewResponse
from app.services import experience_reviews as rv

TODAY = date(2026, 10, 20)


# --- who may review --------------------------------------------------------

def test_a_confirmed_booking_whose_day_has_come_may_be_reviewed():
    assert rv.eligibility_error("confirmed", TODAY, TODAY) is None
    assert rv.eligibility_error("confirmed", TODAY - timedelta(days=3), TODAY) is None


def test_a_finished_trip_marked_closed_may_be_reviewed_if_it_was_confirmed():
    assert rv.eligibility_error("closed", TODAY - timedelta(days=1), TODAY) is None


def test_the_day_must_have_come():
    assert rv.eligibility_error("confirmed", TODAY + timedelta(days=1), TODAY)


@pytest.mark.parametrize("status", ["new", "contacted", "spam"])
def test_an_unconfirmed_request_may_not_be_reviewed(status):
    assert rv.eligibility_error(status, TODAY - timedelta(days=5), TODAY)


def test_closed_without_ever_being_confirmed_does_not_count():
    # An enquiry the provider closed without booking has no confirmed day.
    assert rv.eligibility_error("closed", None, TODAY)


@pytest.mark.parametrize("status", ["customer_cancelled", "provider_cancelled"])
def test_a_cancelled_booking_may_not_be_reviewed(status):
    assert rv.eligibility_error(status, TODAY - timedelta(days=5), TODAY)


# --- the rating itself -----------------------------------------------------

@pytest.mark.parametrize("bad", [0, 6, -1])
def test_stars_are_one_to_five(bad):
    with pytest.raises(ValidationError):
        ReviewCreate(rating=bad)


def test_the_comment_is_capped():
    with pytest.raises(ValidationError):
        ReviewCreate(rating=5, comment="x" * 1001)


@pytest.mark.parametrize("empty", ["", "   ", None])
def test_a_cleared_comment_stores_nothing(empty):
    assert rv.clean_comment(empty) is None
    assert rv.clean_reply(empty) is None


def test_names_are_first_name_and_last_initial():
    assert rv.reviewer_display_name("Anna Kowalski") == "Anna K."
    assert rv.reviewer_display_name("anna de la cruz") == "anna C."
    assert rv.reviewer_display_name("Madonna") == "Madonna"
    assert rv.reviewer_display_name("  ") == "Traveller"
    assert rv.reviewer_display_name(None) == "Traveller"


def test_an_average_has_one_decimal_and_halves_round_up():
    assert rv.summarize([5, 4])["average"] == 4.5
    assert rv.summarize([5, 4, 4, 4])["average"] == 4.3   # 4.25
    assert rv.summarize([5, 5, 4])["average"] == 4.7      # 4.666
    assert rv.summarize([1])["average"] == 1.0


def test_nothing_rated_is_none_not_zero():
    out = rv.summarize([])
    assert out["average"] is None and out["count"] == 0
    assert out["breakdown"] == {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}


def test_the_breakdown_counts_each_star():
    out = rv.summarize([5, 5, 4, 1])
    assert out["count"] == 4
    assert out["breakdown"] == {1: 1, 2: 0, 3: 0, 4: 1, 5: 2}


# --- what each side is shown ------------------------------------------------

def test_the_public_review_carries_no_user_or_contact_detail():
    fields = set(ReviewPublic.model_fields)
    assert not fields & {"user_id", "enquiry_id", "contact_phone", "contact_email", "status"}


def test_the_partner_review_carries_no_user_or_contact_detail():
    fields = set(PartnerReviewResponse.model_fields)
    assert not fields & {"user_id", "enquiry_id", "contact_name", "contact_phone", "contact_email"}


def test_cards_and_requests_carry_the_new_fields():
    assert {"rating_avg", "rating_count"} <= set(ExperiencePackageCard.model_fields)
    assert {"can_review", "review"} <= set(MyEnquiryOut.model_fields)
