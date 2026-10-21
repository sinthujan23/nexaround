"""The optional pickup location on an experience enquiry."""
import asyncio

import pytest
from pydantic import ValidationError

from app.schemas.experience import ExperienceEnquiryAdminResponse, ExperienceEnquiryCreate
from app.services import email_service

PKG = "00000000-0000-0000-0000-000000000001"


def base(**kw):
    return {"package_id": PKG, "contact_name": "Ann", "contact_phone": "+441234567", **kw}


def test_it_is_optional():
    assert ExperienceEnquiryCreate(**base()).pickup_location is None


def test_a_chosen_place_fits():
    data = ExperienceEnquiryCreate(**base(pickup_location="Blanket Hotel, Munnar, Kerala, India"))
    assert data.pickup_location == "Blanket Hotel, Munnar, Kerala, India"


def test_it_is_capped():
    with pytest.raises(ValidationError):
        ExperienceEnquiryCreate(**base(pickup_location="x" * 501))


def test_the_admin_sees_it():
    assert "pickup_location" in ExperienceEnquiryAdminResponse.model_fields


def test_the_enquiry_email_shows_it_escaped(monkeypatch):
    sent = {}
    monkeypatch.setattr(email_service.settings, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(email_service.settings, "SMTP_USER", "u")
    monkeypatch.setattr(
        email_service, "_send_smtp_sync",
        lambda to, subject, body: sent.setdefault("body", body),
    )
    asyncio.run(email_service.send_new_enquiry_email(
        "v@example.com", vendor_name="V", package_title="P",
        contact_name="Ann", contact_phone="+441234567",
        pickup_location="<b>Hotel</b> & Spa",
    ))
    assert "Pickup" in sent["body"]
    assert "&lt;b&gt;Hotel&lt;/b&gt; &amp; Spa" in sent["body"]
