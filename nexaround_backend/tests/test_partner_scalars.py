"""What a vendor may write to their own row, and what they must never reach.

The admin update is a full-replacement loop — `setattr(vendor, key, getattr(
data, key))` over a tuple of column names — and every field on the admin schema
has a default. So a partner endpoint that reused the admin tuple would write
those defaults on every save, even though the partner schema never declares the
fields. A vendor pressing Save would flip `is_active` back to True, which
un-suspends them and re-publishes every package they own.

Nothing here needs a database. These are the shape of the escalation.
"""
import pytest

from app.api.v1.experiences_admin import _PACKAGE_SCALARS, _VENDOR_SCALARS
from app.api.v1.partner import (
    _PARTNER_PACKAGE_SCALARS, _PARTNER_VENDOR_SCALARS,
)
from app.schemas.experience import ExperienceVendorBase
from app.schemas.partner import (
    PartnerEnquiryResponse, PartnerEnquiryUpdate, PartnerPackageBase,
    PartnerVendorProfileResponse, PartnerVendorProfileUpdate,
)

# Moderation and reputation. A vendor may see some of these; none may be
# written by one.
FORBIDDEN = {
    "is_active", "rating", "review_count", "internal_notes", "sort_order",
    "google_place_id",
}


def test_the_partner_tuple_is_not_the_admin_tuple():
    """Guards against a lazy `_PARTNER_VENDOR_SCALARS = _VENDOR_SCALARS`."""
    assert _PARTNER_VENDOR_SCALARS is not _VENDOR_SCALARS
    assert _PARTNER_PACKAGE_SCALARS is not _PACKAGE_SCALARS


def test_no_forbidden_field_is_writable_by_a_vendor():
    leaked = FORBIDDEN & set(_PARTNER_VENDOR_SCALARS)
    assert not leaked, (
        f"a vendor could write {sorted(leaked)} to their own row. "
        f"`is_active` alone lets a suspended vendor un-suspend themselves."
    )


def test_no_forbidden_field_is_even_accepted_by_the_schema():
    """Both halves matter: the tuple is only dangerous if a value can arrive."""
    leaked = FORBIDDEN & set(PartnerVendorProfileUpdate.model_fields)
    assert not leaked, f"the update schema declares {sorted(leaked)}"


def test_the_vendor_tuple_invents_nothing():
    """A name not on the model would raise on every save."""
    unknown = set(_PARTNER_VENDOR_SCALARS) - set(ExperienceVendorBase.model_fields)
    assert not unknown, f"not real columns: {sorted(unknown)}"


def test_nothing_is_accepted_and_then_silently_dropped():
    """The bug class that lost the social links: sent, validated, never saved."""
    declared = set(PartnerVendorProfileUpdate.model_fields) - {"latitude", "longitude"}
    dropped = declared - set(_PARTNER_VENDOR_SCALARS)
    assert not dropped, (
        f"the form can send {sorted(dropped)} and the save loop ignores them"
    )


def test_the_two_vendor_tuples_differ_by_exactly_the_forbidden_set():
    """The drift test that earns its keep.

    The day someone adds a column to the admin tuple, this fails and forces a
    conscious decision about whether a vendor may write it too — instead of the
    field quietly existing on one side only.
    """
    assert set(_VENDOR_SCALARS) - set(_PARTNER_VENDOR_SCALARS) == FORBIDDEN


def test_a_vendor_cannot_reorder_themselves_up_the_listing():
    assert "sort_order" not in _PARTNER_PACKAGE_SCALARS
    assert "sort_order" not in PartnerPackageBase.model_fields


def test_a_vendor_CAN_hide_their_own_package():
    """Deliberate, and pinned so nobody "hardens" it away.

    On a package `is_active` is the vendor's own publish toggle. It is safe
    because `is_published` stays gated behind the vendor's `is_active`, which
    only an admin can set — a suspended vendor cannot surface anything with it.
    """
    assert "is_active" in _PARTNER_PACKAGE_SCALARS


def test_the_package_tuple_only_names_fields_the_schema_has():
    unknown = set(_PARTNER_PACKAGE_SCALARS) - set(PartnerPackageBase.model_fields)
    assert not unknown, f"not on the partner package schema: {sorted(unknown)}"


@pytest.mark.parametrize("field", ["internal_notes", "sort_order", "google_place_id"])
def test_admin_only_fields_are_not_even_readable(field):
    """The model calls `internal_notes` admin-only; the response must honour it."""
    assert field not in PartnerVendorProfileResponse.model_fields


@pytest.mark.parametrize("field", ["is_active", "rating", "review_count"])
def test_moderation_state_is_visible_but_not_writable(field):
    """A vendor should see that their listing is hidden without un-hiding it."""
    assert field in PartnerVendorProfileResponse.model_fields
    assert field not in PartnerVendorProfileUpdate.model_fields


def test_the_platforms_private_notes_never_reach_a_vendor():
    assert "admin_notes" not in PartnerEnquiryResponse.model_fields
    assert "admin_notes" not in PartnerEnquiryUpdate.model_fields
    assert "vendor_notes" in PartnerEnquiryResponse.model_fields


def test_a_vendor_does_not_learn_the_travellers_account_id():
    """Contact details, yes. An identifier into the traveller app, no."""
    assert "user_id" not in PartnerEnquiryResponse.model_fields
