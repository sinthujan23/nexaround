"""The rules around the Experience Booking Terms and the Provider Agreement.

Like test_experiences.py, these cover the logic pushed out of the endpoints so
it can be tested without a database.
"""

from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.services import legal_service, legal_texts
from app.services.legal_service import (
    APP_TOO_OLD, APP_UPGRADE_GRACE, PROVIDER_GRACE, TERMS_CHANGED,
    customer_terms_error, vendor_is_listed,
)

PUBLISHED = datetime(2026, 10, 16, 9, 0, tzinfo=timezone.utc)


# --- Vendors: listed while accepted or within the grace period ---------------

def test_a_vendor_who_accepted_the_current_version_is_listed():
    late = PUBLISHED + PROVIDER_GRACE * 10
    assert vendor_is_listed(2, 2, PUBLISHED, late) is True


def test_a_vendor_who_accepted_a_later_version_is_listed():
    late = PUBLISHED + PROVIDER_GRACE * 10
    assert vendor_is_listed(3, 2, PUBLISHED, late) is True


def test_every_vendor_stays_listed_during_the_grace_period():
    during = PUBLISHED + PROVIDER_GRACE - timedelta(minutes=1)
    assert vendor_is_listed(None, 1, PUBLISHED, during) is True
    assert vendor_is_listed(1, 2, PUBLISHED, during) is True


def test_a_vendor_who_has_not_accepted_is_hidden_after_the_grace_period():
    after = PUBLISHED + PROVIDER_GRACE
    assert vendor_is_listed(None, 1, PUBLISHED, after) is False


def test_accepting_an_older_version_is_not_enough_once_a_new_one_is_past_grace():
    after = PUBLISHED + PROVIDER_GRACE + timedelta(days=1)
    assert vendor_is_listed(1, 2, PUBLISHED, after) is False


# --- Travellers: the version sent with a request ----------------------------

def test_a_request_with_the_current_version_goes_through():
    assert customer_terms_error(3, 3, PUBLISHED, PUBLISHED) is None


def test_a_request_with_an_old_version_must_review_the_new_terms():
    status, message = customer_terms_error(2, 3, PUBLISHED, PUBLISHED)
    assert status == TERMS_CHANGED == 409
    assert "updated" in message


def test_an_old_app_without_terms_is_let_through_during_the_upgrade_grace():
    during = PUBLISHED + APP_UPGRADE_GRACE - timedelta(minutes=1)
    assert customer_terms_error(None, 1, PUBLISHED, during) is None


def test_an_old_app_without_terms_is_refused_after_the_upgrade_grace():
    after = PUBLISHED + APP_UPGRADE_GRACE
    status, message = customer_terms_error(None, 1, PUBLISHED, after)
    assert status == APP_TOO_OLD == 426
    assert "update" in message.lower()


def test_the_refusals_read_as_sentences_the_app_will_show():
    # The app shows a server detail only if it is short, one line, and free of
    # technical markers (user_message.dart's safeServerDetail).
    for result in (
        customer_terms_error(1, 2, PUBLISHED, PUBLISHED),
        customer_terms_error(None, 1, PUBLISHED, PUBLISHED + APP_UPGRADE_GRACE),
    ):
        message = result[1]
        assert len(message) <= 160 and "\n" not in message and "{" not in message


# --- The version-1 texts ----------------------------------------------------

@pytest.mark.parametrize("body", [legal_texts.CUSTOMER_BODY, legal_texts.PROVIDER_BODY])
def test_the_texts_keep_the_clients_core_wording(body):
    assert "online intermediary platform" in body
    assert "72 hours" in body
    assert "direct contractual relationship" in body


@pytest.mark.parametrize("body", [legal_texts.CUSTOMER_BODY, legal_texts.PROVIDER_BODY])
def test_the_liability_exclusions_are_qualified_by_law(body):
    # An unqualified exclusion of liability for injury can be struck out whole.
    assert "To the fullest extent permitted by applicable law" in body
    assert "cannot be excluded or limited by law" in body


@pytest.mark.parametrize("body", [legal_texts.CUSTOMER_BODY, legal_texts.PROVIDER_BODY])
def test_no_single_country_is_named_as_governing_law(body):
    # The app is released worldwide; the client has not chosen a jurisdiction.
    assert "Sri Lanka" not in body
    assert "operating company is registered" in body


@pytest.mark.parametrize("body", [legal_texts.CUSTOMER_BODY, legal_texts.PROVIDER_BODY])
def test_the_texts_use_only_the_markup_every_client_renders(body):
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        assert not stripped.startswith(("#", "*", "1.")) or stripped.startswith("## ")
        assert not stripped.startswith("### ")


def test_every_kind_has_a_default():
    assert set(legal_service._DEFAULTS) == set(legal_service.KINDS)
    for title, body, highlights in legal_service._DEFAULTS.values():
        assert title and body and 1 <= len(highlights) <= 6
        assert all(len(line) <= 160 for line in highlights)


# --- Schemas ----------------------------------------------------------------

def test_a_provider_must_confirm_they_may_accept_for_the_business():
    from app.schemas.legal import PartnerAgreementAccept

    with pytest.raises(ValidationError):
        PartnerAgreementAccept(version=1, authorised=False)
    assert PartnerAgreementAccept(version=1, authorised=True).authorised


def test_highlights_are_trimmed_and_blank_lines_dropped():
    from app.schemas.legal import LegalDocumentSave

    saved = LegalDocumentSave(
        title="Terms", body="x" * 40, highlights=["  Pay on site  ", "", "   "],
    )
    assert saved.highlights == ["Pay on site"]


def test_the_enquiry_carries_the_accepted_terms_version():
    from app.schemas.experience import (
        ExperienceEnquiryAdminResponse, ExperienceEnquiryCreate,
    )
    from app.schemas.partner import PartnerEnquiryResponse

    assert "accepted_terms_version" in ExperienceEnquiryCreate.model_fields
    for schema in (ExperienceEnquiryAdminResponse, PartnerEnquiryResponse):
        assert {"terms_version", "terms_accepted_at"} <= set(schema.model_fields)
