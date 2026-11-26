"""Explorer feedback and the quarterly survey (client request, 2026-11-26).

Pure rules only (app/services/feedback_service.py): no database. The
database flows (one answer per round, the pop-up caps) were checked against a
throwaway Postgres when this was built.
"""
import asyncio
import io
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from PIL import Image

from app.api.v1 import admin
from app.services import creator_auth
from app.services import feedback_service as fb


# ── Net Promoter Score ─────────────────────────────────────────────────────

def test_nps_is_promoters_minus_detractors():
    # 9–10 promote, 7–8 are passive, 0–6 detract.
    scores = [10, 9, 9, 8, 7, 6, 0, 10, 9, 3]
    parts = fb.nps_parts(scores)
    assert parts["promoters"] == 50
    assert parts["detractors"] == 30
    assert parts["passives"] == 20
    assert parts["score"] == 20


def test_nps_extremes_and_empty():
    assert fb.nps_parts([10, 9])["score"] == 100
    assert fb.nps_parts([0, 6])["score"] == -100
    assert fb.nps_parts([7, 8])["score"] == 0
    assert fb.nps_parts([])["score"] is None


# ── "Build next" options ───────────────────────────────────────────────────

def test_options_get_stable_unique_keys_and_safe_icons():
    out = fb.normalise_options([
        {"label": "Offline maps", "icon": "wifi_off"},
        {"label": "Offline maps!", "icon": "not_an_icon"},
        {"label": "  "},
    ], [], False)
    assert [o["key"] for o in out] == ["offline_maps", "offline_maps_2"]
    assert out[0]["icon"] == "wifi_off"
    assert out[1]["icon"] == "lightbulb"


def test_renaming_keeps_the_key_so_old_answers_still_count():
    existing = [{"key": "offline_maps", "label": "Offline maps", "icon": "wifi_off"}]
    out = fb.normalise_options([{"key": "offline_maps", "label": "Offline maps for guides"}], existing, True)
    assert out == [{"key": "offline_maps", "label": "Offline maps for guides", "icon": "lightbulb"}]


def test_options_cannot_be_removed_once_answered():
    existing = [{"key": "a", "label": "A"}, {"key": "b", "label": "B"}]
    with pytest.raises(HTTPException) as e:
        fb.normalise_options([{"key": "a", "label": "A"}], existing, True)
    assert e.value.status_code == 400
    # Before any answers the team may reshape the list freely.
    assert len(fb.normalise_options([{"key": "a", "label": "A"}], existing, False)) == 1


def test_at_most_fifteen_options():
    with pytest.raises(HTTPException):
        fb.normalise_options([{"label": f"Idea {i}"} for i in range(16)], [], False)


# ── Fixed vocabularies match what the app sends ────────────────────────────

def test_message_types_have_no_idea():
    # Client, 2026-11-26: "idea" was split into Suggestion and Improvement.
    assert fb.MESSAGE_TYPES == ("suggestion", "improvement", "problem", "love", "other")
    assert fb.message_type("idea") == "suggestion"
    assert fb.message_type("improvement") == "improvement"
    with pytest.raises(HTTPException):
        fb.message_type("wish")


def test_price_ranges_and_pay_answers():
    assert fb.WOULD_PAY == ("yes", "maybe", "no")
    assert fb.PRICE_RANGES == ("lt2", "2to5", "5to8", "8to12", "gt12")
    assert set(fb.QUICK_REASONS) == set(fb.QUICK_FEATURES)
    assert all("other" in reasons for reasons in fb.QUICK_REASONS.values())


# ── Screenshots stay private and per explorer ──────────────────────────────

def _png(w=400, h=800) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", (w, h), (0, 121, 123)).save(out, format="PNG")
    return out.getvalue()


def test_screenshots_saved_privately_and_only_owner_names_accepted(tmp_path, monkeypatch):
    monkeypatch.setattr(fb, "FEEDBACK_UPLOAD_DIR", str(tmp_path))
    me, other = uuid.uuid4(), uuid.uuid4()
    name = fb.save_screenshot(me, _png())
    assert name.endswith(".webp") and fb.screenshot_path(me, name)
    # Another explorer can't attach my picture, and odd names are refused.
    assert fb._clean_screenshots(other, [name]) == []
    assert fb.screenshot_path(me, "../../etc/passwd") is None
    assert fb._clean_screenshots(me, [name, name, "nope.webp"]) == [name]


def test_screenshot_limits(tmp_path, monkeypatch):
    monkeypatch.setattr(fb, "FEEDBACK_UPLOAD_DIR", str(tmp_path))
    me = uuid.uuid4()
    with pytest.raises(HTTPException):
        fb.save_screenshot(me, b"not a picture")
    names = [fb.save_screenshot(me, _png()) for _ in range(4)]
    with pytest.raises(HTTPException):
        fb._clean_screenshots(me, names)


# ── Panel access ───────────────────────────────────────────────────────────

def test_feedback_is_a_team_area():
    assert creator_auth.FEEDBACK in creator_auth.SECTIONS


def test_team_member_without_the_area_gets_403(monkeypatch):
    monkeypatch.setattr(admin, "decode_token", lambda t: {"role": creator_auth.ROLE})

    async def member(payload, request):
        return SimpleNamespace(name="Kim", id=uuid.uuid4(), sections=["city_tours"])

    monkeypatch.setattr(admin, "live_member", member)
    dep = admin.allow_team(creator_auth.FEEDBACK)
    with pytest.raises(HTTPException) as e:
        asyncio.run(dep(SimpleNamespace(), "Bearer x"))
    assert e.value.status_code == 403


def test_team_member_with_the_area_gets_in(monkeypatch):
    monkeypatch.setattr(admin, "decode_token", lambda t: {"role": creator_auth.ROLE})

    async def member(payload, request):
        return SimpleNamespace(name="Kim", id=uuid.uuid4(), sections=[creator_auth.FEEDBACK])

    monkeypatch.setattr(admin, "live_member", member)
    user = asyncio.run(admin.allow_team(creator_auth.FEEDBACK)(SimpleNamespace(), "Bearer x"))
    assert user.name == "Kim" and not user.is_admin
