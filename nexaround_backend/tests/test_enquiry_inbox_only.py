"""Requests reach Nexaround only, never the vendor.

The team contacts the traveller and the vendor itself, so a booking cannot be
arranged around the platform's commission. A vendor with a contact email on
file must still get nothing.
"""
import asyncio
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

from app.api.v1 import experiences
from app.services import enquiry_notifications

PLATFORM = "support@example.com"
VENDOR_EMAIL = "vendor@example.com"


def _enquiry():
    return SimpleNamespace(
        id=uuid.uuid4(), vendor_id=uuid.uuid4(),
        vendor_name_snapshot="Desert Track", package_title_snapshot="Desert Safari",
        contact_name="Ann", contact_phone="+97455554444", contact_email="ann@example.com",
        preferred_date=None, confirmed_date=None, party_size=2,
        pickup_location="Al Wakrah", message=None, price_option=None,
        cancelled_at=datetime(2026, 10, 21, tzinfo=timezone.utc),
        cancellation_reason=None, late_cancellation=False,
    )


class _Db:
    """Hands back the enquiry, or a vendor that has an email on file."""

    def __init__(self, enquiry):
        self.enquiry = enquiry

    async def get(self, model, _id):
        if model.__name__ == "ExperienceEnquiry":
            return self.enquiry
        return SimpleNamespace(contact_email=VENDOR_EMAIL)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _Settings:
    def __init__(self, _db):
        pass

    async def get_setting(self, key, default=None):
        return PLATFORM if key == "contact_email" else default


def test_a_new_enquiry_is_emailed_to_the_platform_only(monkeypatch):
    sent = []
    enquiry = _enquiry()
    monkeypatch.setattr(experiences, "async_session", lambda: _Db(enquiry))
    monkeypatch.setattr(experiences, "SettingsService", _Settings)

    async def fake_send(to, **kw):
        sent.append(to)

    monkeypatch.setattr(experiences, "send_new_enquiry_email", fake_send)
    asyncio.run(experiences._dispatch_enquiry_email(enquiry.id))
    assert sent == [PLATFORM]


def test_a_traveller_cancellation_is_emailed_to_the_platform_only(monkeypatch):
    sent = []
    enquiry = _enquiry()
    monkeypatch.setattr(enquiry_notifications, "async_session", lambda: _Db(enquiry))
    monkeypatch.setattr(enquiry_notifications, "SettingsService", _Settings)

    async def fake_send(to, **kw):
        sent.append(to)

    monkeypatch.setattr(
        enquiry_notifications.email_service, "send_experience_update_email", fake_send
    )
    asyncio.run(enquiry_notifications.customer_cancelled(enquiry.id))
    assert sent == [PLATFORM]
