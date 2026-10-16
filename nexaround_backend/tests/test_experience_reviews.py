"""Ratings and reviews: how a rating reads, what each side sees."""
import pytest
from pydantic import ValidationError

from app.schemas.experience import (
    ExperiencePackageCard, MyEnquiryOut, ReviewCreate, ReviewPublic,
)
from app.schemas.partner import PartnerReviewResponse
from app.services import experience_reviews as rv


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


def test_a_review_belongs_to_a_user_and_a_package_not_an_enquiry():
    from app.models.experience import ExperienceReview

    columns = ExperienceReview.__table__.c
    assert "enquiry_id" not in columns
    unique = [
        sorted(c.name for c in con.columns)
        for con in ExperienceReview.__table__.constraints
        if con.__class__.__name__ == "UniqueConstraint"
    ]
    assert ["package_id", "user_id"] in unique


def test_cards_and_requests_carry_the_new_fields():
    assert {"rating_avg", "rating_count"} <= set(ExperiencePackageCard.model_fields)
    assert {"can_review", "review"} <= set(MyEnquiryOut.model_fields)


def test_delete_review_endpoint_exists():
    from app.api.v1.experiences import router
    delete_routes = [
        r.path for r in router.routes
        if "DELETE" in getattr(r, "methods", set())
    ]
    assert "/experiences/packages/{package_id}/review" in delete_routes


