"""The website contact forms: a message reaches the inbox, or the form is told
it did not. Both forms used to say "sent" while nothing left the browser.
"""
import asyncio

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.v1 import proxy
from app.core.database import get_db
from app.services import email_service

INBOX = "team@example.com"
VALID = {
    "site": "app.nexaround.com",
    "name": "Ann Lee",
    "email": "ann@example.com",
    "topic": "App Inquiry & Feedback",
    "message": "Hello, I would like to know more.",
}


class _Settings:
    def __init__(self, db):
        pass

    async def get_setting(self, key, default=None):
        return INBOX


@pytest.fixture
def sent(monkeypatch):
    calls = []

    async def fake_send(to_email, **kwargs):
        calls.append((to_email, kwargs))
        return True

    async def not_limited(key, redis):
        return False

    async def no_redis():
        return None

    monkeypatch.setattr(email_service, "send_website_contact_email", fake_send)
    monkeypatch.setattr(proxy, "SettingsService", _Settings)
    monkeypatch.setattr(proxy, "get_redis_client", no_redis)
    monkeypatch.setattr(proxy._landing_contact_limiter, "_check_rate_limit", not_limited)
    return calls


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(proxy.router)
    app.dependency_overrides[get_db] = lambda: None
    return TestClient(app)


def test_message_goes_to_the_inbox(client, sent):
    response = client.post("/landing/contact", json=VALID)
    assert response.status_code == 200
    to_email, fields = sent[0]
    assert to_email == INBOX
    assert fields["email"] == "ann@example.com"
    assert fields["site"] == "app.nexaround.com"


def test_failed_send_is_an_error_not_a_success(client, sent, monkeypatch):
    async def failing(to_email, **kwargs):
        return False

    monkeypatch.setattr(email_service, "send_website_contact_email", failing)
    assert client.post("/landing/contact", json=VALID).status_code == 502


def test_spam_trap_looks_accepted_but_sends_nothing(client, sent):
    response = client.post("/landing/contact", json={**VALID, "website": "http://spam.example"})
    assert response.status_code == 200
    assert sent == []


def test_rate_limited(client, sent, monkeypatch):
    async def limited(key, redis):
        return True

    monkeypatch.setattr(proxy._landing_contact_limiter, "_check_rate_limit", limited)
    assert client.post("/landing/contact", json=VALID).status_code == 429
    assert sent == []


@pytest.mark.parametrize(
    "change",
    [
        {"email": "not-an-email"},
        {"email": "a@b.com\nBcc: x@example.com"},
        {"site": "evil.example"},
        {"message": ""},
        {"name": ""},
    ],
)
def test_bad_input_is_rejected(client, sent, change):
    assert client.post("/landing/contact", json={**VALID, **change}).status_code == 422
    assert sent == []


def _send(**overrides):
    fields = dict(
        site="nexaround.com", topic="Other", name="Ann", email="ann@example.com", message="Hi"
    )
    fields.update(overrides)
    return asyncio.run(email_service.send_website_contact_email(INBOX, **fields))


def test_unconfigured_smtp_is_not_reported_as_sent(monkeypatch):
    monkeypatch.setattr(email_service.settings, "SMTP_HOST", "")
    assert _send() is False


def test_visitor_text_is_escaped_and_reply_goes_to_the_visitor(monkeypatch):
    mails = []

    def capture(to_email, subject, body, reply_to=""):
        mails.append((subject, body, reply_to))
        return True

    monkeypatch.setattr(email_service.settings, "SMTP_HOST", "smtp.example.com")
    monkeypatch.setattr(email_service.settings, "SMTP_USER", "user")
    monkeypatch.setattr(email_service, "_send_smtp_sync", capture)

    assert _send(topic="Line\nBreak", name="<b>Ann</b>", message="<script>x</script>\nline two") is True

    subject, body, reply_to = mails[0]
    assert "\n" not in subject
    assert "<script>" not in body and "<b>Ann" not in body
    assert "line two" in body and "<br>" in body
    assert reply_to == "ann@example.com"
