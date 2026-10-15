"""The free-text region on a package ("Kerala State · Munnar region")."""
import pytest
from pydantic import ValidationError

from app.api.v1.experiences_admin import _PACKAGE_SCALARS
from app.api.v1.partner import _PARTNER_PACKAGE_SCALARS
from app.schemas.experience import ExperiencePackageCard, ExperiencePackageCreate
from app.services.experience_format import package_field_value


def test_admin_saves_it_trimmed():
    data = ExperiencePackageCreate(title="T", region_label="  Kerala State · Munnar region ")
    assert package_field_value(data, "region_label") == "Kerala State · Munnar region"


@pytest.mark.parametrize("cleared", ["", "   ", None])
def test_a_cleared_box_stores_nothing(cleared):
    data = ExperiencePackageCreate(title="T", region_label=cleared)
    assert package_field_value(data, "region_label") is None


def test_it_is_short_text():
    with pytest.raises(ValidationError):
        ExperiencePackageCreate(title="T", region_label="x" * 121)


def test_only_the_admin_can_write_it():
    assert "region_label" in _PACKAGE_SCALARS
    assert "region_label" not in _PARTNER_PACKAGE_SCALARS


def test_the_app_gets_it_on_cards_and_detail():
    # The detail schema extends the card one, so both carry it.
    assert "region_label" in ExperiencePackageCard.model_fields
