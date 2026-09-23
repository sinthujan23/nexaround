"""Every field the vendor form sends must actually reach the row, and come back.

The admin endpoints copy request fields to the model through an explicit tuple
of column names, and build their reply field by field. Both are hand-maintained,
so a field added to the schema but forgotten in either place is accepted, saved
without complaint and then simply gone - which is what happened to the three
social links: the form posted them, the API answered 200, and a refresh showed
empty boxes.

Pydantic cannot catch it: every one of these columns is Optional, so a missing
value is a valid `None` rather than an error. These tests are the check.
"""
import uuid
from datetime import datetime

import pytest

from app.api.v1.experiences_admin import (
    _PACKAGE_SCALARS, _VENDOR_SCALARS, _vendor_response,
)
from app.schemas.experience import (
    ExperiencePackageBase, ExperienceVendorBase,
)
from app.utils.geo_utils import create_point

# Written into the model by hand because they are not plain columns: the two
# coordinates become a PostGIS point.
_VENDOR_HANDLED_SEPARATELY = {"latitude", "longitude"}
_PACKAGE_HANDLED_SEPARATELY = {"latitude", "longitude", "vendor_id"}


def test_every_vendor_field_is_written_to_the_row():
    declared = set(ExperienceVendorBase.model_fields) - _VENDOR_HANDLED_SEPARATELY
    missing = sorted(declared - set(_VENDOR_SCALARS))
    assert not missing, (
        f"accepted by the schema but never saved: {missing}. "
        f"Add them to _VENDOR_SCALARS."
    )


def test_the_scalar_list_invents_nothing():
    """A name here that is not on the schema would raise on every save."""
    declared = set(ExperienceVendorBase.model_fields)
    unknown = sorted(set(_VENDOR_SCALARS) - declared)
    assert not unknown, f"_VENDOR_SCALARS names fields the schema does not have: {unknown}"


def test_every_package_field_is_written_to_the_row():
    declared = set(ExperiencePackageBase.model_fields) - _PACKAGE_HANDLED_SEPARATELY
    missing = sorted(declared - set(_PACKAGE_SCALARS))
    assert not missing, (
        f"accepted by the schema but never saved: {missing}. "
        f"Add them to _PACKAGE_SCALARS."
    )


class _Vendor:
    """A row with every column set to something recognisable."""

    def __init__(self):
        self.id = uuid.uuid4()
        # A real point: the reply derives latitude and longitude from it.
        self.location = create_point(6.9271, 79.8612)
        self.created_at = datetime(2026, 9, 23, 9, 0, 0)
        self.updated_at = None
        self.rating = 4.5
        self.review_count = 12
        self.photo_urls = ["https://example.test/a.jpg"]
        self.is_active = True
        self.sort_order = 3
        # Capped at two characters by the schema, so it cannot take the
        # recognisable placeholder the others get.
        self.country_code = "LK"
        for name in (
            "name", "description", "address", "google_place_id", "city",
            "contact_phone", "contact_whatsapp",
            "contact_instagram", "contact_facebook", "contact_x",
            "contact_email", "website", "logo_url", "internal_notes",
        ):
            setattr(self, name, f"value-for-{name}")


def test_every_vendor_field_comes_back_in_the_reply():
    """The reply is built field by field, so an omission reads as an empty box."""
    out = _vendor_response(_Vendor(), package_count=2)
    lost = [
        name for name in ExperienceVendorBase.model_fields
        if name not in _VENDOR_HANDLED_SEPARATELY
        and getattr(out, name, None) in (None, "", [])
    ]
    assert not lost, f"stored but not returned: {sorted(lost)}"


@pytest.mark.parametrize("field", ["contact_instagram", "contact_facebook", "contact_x"])
def test_the_social_links_specifically(field):
    """The three that were actually lost, pinned by name."""
    assert field in _VENDOR_SCALARS
    assert getattr(_vendor_response(_Vendor()), field) == f"value-for-{field}"
