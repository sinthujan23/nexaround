"""The admin's two tools for a request whose phone number does not work.

* Notify traveller: a line in the app's bell, a push and an email, which
  works with the app already in the stores (the bell and push open My
  requests). The message is copied into the admin notes.
* Edit phone: the right number, with its country code; the old one is kept
  in the admin notes.

Nothing here reaches Firebase, SMTP or the database: all are faked.
"""
import asyncio
import uuid
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi import BackgroundTasks, HTTPException

from app.api.v1 import experiences_admin
from app.models.experience import ExperienceEnquiry
from app.schemas.experience import EnquiryTravellerMessage, ExperienceEnquiryUpdate
from app.services import email_service, enquiry_notifications
from app.services.experience_format import international_phone

WRONG = "+94039485322"


def _enquiry(**over):
    fields = dict(
        id=uuid.uuid4(), user_id=uuid.uuid4(), vendor_id=uuid.uuid4(),
        package_title_snapshot="Private Ocean Tours", vendor_name_snapshot="Blue Ocean",
        contact_name="Sam", contact_phone=WRONG, contact_email="sam@example.com",
        preferred_date=None, party_size=2, status="new", admin_notes=None,
        created_at=datetime(2026, 11, 22, 15, 37, tzinfo=timezone.utc),
    )
    fields.update(over)
    return ExperienceEnquiry(**fields)


class _Db:
    """Hands back the enquiry and an active user; records what is added."""

    def __init__(self, enquiry, user_active=True):
        self.enquiry = enquiry
        self.user = SimpleNamespace(id=enquiry.user_id, is_active=user_active, preferences={})
        self.added = []
        self.commits = 0

    async def get(self, model, _id):
        return self.enquiry if model.__name__ == "ExperienceEnquiry" else self.user

    def add(self, row):
        self.added.append(row)

    async def commit(self):
        self.commits += 1

    async def refresh(self, _row):
        pass


# --- international_phone ------------------------------------------------------

@pytest.mark.parametrize("typed, saved", [
    ("+234 803-123 4567", "+2348031234567"),
    ("00 44 7700 900123", "+447700900123"),
    ("+94 (77) 123.4567", "+94771234567"),
])
def test_a_number_with_its_country_code_is_saved_compact(typed, saved):
    assert international_phone(typed) == saved


@pytest.mark.parametrize("typed", [
    "0803 123 4567",      # no country code
    "+0 803 123 4567",    # no country code starts with 0
    "+44 12",             # too short
    "+1234567890123456",  # 16 digits, longer than E.164
    "+44 7700 9001 ext 2",
    "+44+7700900123",
    "",
])
def test_anything_else_is_refused(typed):
    assert international_phone(typed) is None


# --- message_traveller (service) ---------------------------------------------

def test_the_message_goes_to_the_bell_the_phone_and_the_email(monkeypatch):
    enquiry = _enquiry()
    db = _Db(enquiry)
    pushes, emails = [], []

    async def fake_push(_db, user_id, title, body, enquiry_id):
        pushes.append((user_id, title, body, enquiry_id))
        return True

    async def fake_email(to, **kw):
        emails.append((to, kw))
        return True

    monkeypatch.setattr(enquiry_notifications, "_push", fake_push)
    monkeypatch.setattr(email_service, "send_experience_update_email", fake_email)

    sent = asyncio.run(enquiry_notifications.message_traveller(db, enquiry, "Please resend your number."))

    assert sent == {"bell": True, "push": True, "email": True}
    [line] = db.added
    # The type the app's bell and push route to My requests.
    assert line.type == "experience_request"
    assert line.title == "About your Private Ocean Tours request"
    assert line.body == "Please resend your number."
    assert line.push_status == "sent"
    assert pushes == [(enquiry.user_id, line.title, line.body, enquiry.id)]
    [(to, kw)] = emails
    assert to == "sam@example.com"
    assert kw["intro"] == "Please resend your number."
    assert ("Request", enquiry.reference) in kw["rows"]


def test_with_no_app_account_only_the_email_goes(monkeypatch):
    enquiry = _enquiry(user_id=None)
    db = _Db(enquiry)

    async def no_push(*_a, **_k):
        raise AssertionError("no account, no push")

    async def fake_email(to, **kw):
        return True

    monkeypatch.setattr(enquiry_notifications, "_push", no_push)
    monkeypatch.setattr(email_service, "send_experience_update_email", fake_email)

    sent = asyncio.run(enquiry_notifications.message_traveller(db, enquiry, "Hello there"))

    assert sent == {"bell": False, "push": False, "email": True}
    assert db.added == []


def test_a_failed_push_still_leaves_the_bell_line(monkeypatch):
    enquiry = _enquiry(contact_email=None)
    db = _Db(enquiry)

    async def broken_push(*_a, **_k):
        raise RuntimeError("firebase down")

    monkeypatch.setattr(enquiry_notifications, "_push", broken_push)

    sent = asyncio.run(enquiry_notifications.message_traveller(db, enquiry, "Hello there"))

    assert sent == {"bell": True, "push": False, "email": False}
    assert db.added[0].push_status == "failed"


# --- POST /admin/experiences/enquiries/{id}/message --------------------------

def _send(db, text):
    return asyncio.run(experiences_admin.message_traveller(
        db.enquiry.id, EnquiryTravellerMessage(message=text), db=db, _=None,
    ))


def test_the_message_is_copied_into_the_admin_notes(monkeypatch):
    enquiry = _enquiry(admin_notes="Called twice, no answer.")
    db = _Db(enquiry)

    async def fake(_db, _enquiry, _text):
        return {"bell": True, "push": True, "email": True}

    monkeypatch.setattr(enquiry_notifications, "message_traveller", fake)

    result = _send(db, "  Please resend your number.  ")

    assert (result.bell, result.push, result.email) == (True, True, True)
    first, second = result.enquiry.admin_notes.split("\n")
    assert first == "Called twice, no answer."
    assert second.endswith(" · Message sent (app + email): Please resend your number.")


def test_an_empty_message_is_refused(monkeypatch):
    db = _Db(_enquiry())
    with pytest.raises(HTTPException) as caught:
        _send(db, "   ")
    assert caught.value.status_code == 400


def test_a_traveller_with_no_way_to_reach_them_is_refused():
    db = _Db(_enquiry(user_id=None, contact_email=None))
    with pytest.raises(HTTPException) as caught:
        _send(db, "Hello there")
    assert caught.value.status_code == 400


def test_nothing_sent_is_an_error_and_writes_no_note(monkeypatch):
    enquiry = _enquiry()
    db = _Db(enquiry)

    async def nothing(*_a):
        return {"bell": False, "push": False, "email": False}

    monkeypatch.setattr(enquiry_notifications, "message_traveller", nothing)
    with pytest.raises(HTTPException) as caught:
        _send(db, "Hello there")
    assert caught.value.status_code == 502
    assert enquiry.admin_notes is None


# --- PATCH /admin/experiences/enquiries/{id}: contact_phone -------------------

def _patch(db, **fields):
    return asyncio.run(experiences_admin.update_enquiry(
        db.enquiry.id, ExperienceEnquiryUpdate(**fields), BackgroundTasks(), db=db, _=None,
    ))


def test_the_corrected_phone_is_saved_and_the_old_one_noted():
    enquiry = _enquiry()
    db = _Db(enquiry)

    result = _patch(db, contact_phone="+234 803 123 4567")

    assert result.contact_phone == "+2348031234567"
    assert result.admin_notes.endswith(f" · Phone changed from {WRONG} to +2348031234567.")
    # Only the phone: the status and the vendor are left alone.
    assert result.status == "new"


def test_a_phone_without_a_country_code_is_refused():
    enquiry = _enquiry()
    db = _Db(enquiry)
    with pytest.raises(HTTPException) as caught:
        _patch(db, contact_phone="0803 123 4567")
    assert caught.value.status_code == 400
    assert enquiry.contact_phone == WRONG


def test_saving_the_same_number_adds_no_note():
    enquiry = _enquiry(contact_phone="+2348031234567")
    db = _Db(enquiry)
    result = _patch(db, contact_phone="+234 803 123 4567")
    assert result.admin_notes is None
