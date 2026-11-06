"""The app's "List your experience" form: businesses asking to join."""
import asyncio
import uuid
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.api.v1 import experiences
from app.schemas.experience import ProviderApplicationCreate, ProviderApplicationUpdate

GOOD = {
    "business_name": "Blue Ocean Adventures",
    "contact_name": "Ravi",
    "contact_phone": "+94 77 123 4567",
    "contact_email": "info@blueocean.lk",
    "country_code": "lk",
    "city": "Trincomalee",
    "offering": "Snorkeling and dolphin trips, LKR 7,000 per person.",
}


def test_a_complete_form_is_accepted():
    data = ProviderApplicationCreate(**GOOD)
    assert data.country_code == "LK"
    assert data.links is None


@pytest.mark.parametrize("field,value", [
    ("contact_email", "not-an-email"),
    ("contact_phone", "call me"),
    ("offering", "boats"),
    ("business_name", "B"),
])
def test_a_broken_field_is_refused(field, value):
    with pytest.raises(ValidationError):
        ProviderApplicationCreate(**{**GOOD, field: value})


def test_only_known_statuses():
    assert ProviderApplicationUpdate(status="contacted").status == "contacted"
    with pytest.raises(ValidationError):
        ProviderApplicationUpdate(status="approved")


class _Db:
    def __init__(self, row):
        self.row = row

    async def get(self, model, _id):
        return self.row

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _Settings:
    def __init__(self, _db):
        pass

    async def get_setting(self, key, default=None):
        return "support@example.com" if key == "contact_email" else default


def test_the_application_is_emailed_to_the_platform_inbox(monkeypatch):
    from app.services import email_service

    row = SimpleNamespace(
        id=uuid.uuid4(), business_name="Blue Ocean Adventures", contact_name="Ravi",
        contact_phone="+94771234567", contact_email="info@blueocean.lk",
        country_code="LK", city="Trincomalee", offering="Snorkeling", links=None,
    )
    sent = []

    async def fake_send(to, **kw):
        sent.append((to, kw["subject"], dict(kw["rows"])))

    monkeypatch.setattr(experiences, "async_session", lambda: _Db(row))
    monkeypatch.setattr(experiences, "SettingsService", _Settings)
    monkeypatch.setattr(email_service, "send_experience_update_email", fake_send)
    asyncio.run(experiences._email_application(row.id))

    (to, subject, rows), = sent
    assert to == "support@example.com"
    assert "Blue Ocean Adventures" in subject
    assert rows["Location"] == "Trincomalee, Sri Lanka"


# ── The same form on app.nexaround.com (2026-11-06) ──

def _row():
    return SimpleNamespace(
        id=uuid.uuid4(), business_name="Blue Ocean Adventures", contact_name="Ravi",
        contact_phone="+94771234567", contact_email="info@blueocean.lk",
        country_code="LK", city="Trincomalee", offering="Snorkeling", links=None,
    )


@pytest.mark.parametrize("source,label", [
    (None, "nexARound app"),
    ("website", "app.nexaround.com website"),
])
def test_the_email_says_where_it_was_sent_from(monkeypatch, source, label):
    from app.services import email_service

    row = _row()
    sent = []

    async def fake_send(to, **kw):
        sent.append((kw["intro"], dict(kw["rows"])))

    monkeypatch.setattr(experiences, "async_session", lambda: _Db(row))
    monkeypatch.setattr(experiences, "SettingsService", _Settings)
    monkeypatch.setattr(email_service, "send_experience_update_email", fake_send)
    args = (row.id,) if source is None else (row.id, source)
    asyncio.run(experiences._email_application(*args))

    (intro, rows), = sent
    assert rows["Sent from"] == label
    assert ("app.nexaround.com" in intro) == (source == "website")


def test_the_app_needs_no_source_and_a_made_up_one_is_refused():
    assert ProviderApplicationCreate(**GOOD).source == "app"
    assert ProviderApplicationCreate(**GOOD, source="website").source == "website"
    with pytest.raises(ValidationError):
        ProviderApplicationCreate(**GOOD, source="elsewhere")


def test_a_filled_spam_trap_saves_nothing(monkeypatch):
    from fastapi import BackgroundTasks

    class _NoWrites:
        def add(self, _row):
            raise AssertionError("a bot's form must not be saved")

    async def not_limited(_ip):
        return False

    monkeypatch.setattr(experiences, "_too_many_applications", not_limited)
    request = SimpleNamespace(client=SimpleNamespace(host="203.0.113.9"), headers={})
    tasks = BackgroundTasks()
    data = ProviderApplicationCreate(**GOOD, source="website", website="http://spam.example")

    result = asyncio.run(experiences.create_provider_application(
        data, tasks, request, db=_NoWrites(), current_user=None))

    assert result.status == "new"
    assert tasks.tasks == []
