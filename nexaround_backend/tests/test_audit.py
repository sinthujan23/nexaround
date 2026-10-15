"""The audit trail's pure rules, and the wiring that can only be checked by
running the app: who the middleware attributes a write to, what it refuses to
log, and that a revoked or sid-less token is turned away.

The database-touching functions are replaced with in-memory fakes; the pins
here are about what gets asked of them.
"""
import asyncio
import uuid
from types import SimpleNamespace

import pytest
from fastapi import Depends, FastAPI, Request
from fastapi.testclient import TestClient

from app.services import audit


# ── User-Agent → device ─────────────────────────────────────────────────────

CHROME_WIN = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
EDGE_WIN = CHROME_WIN + " Edg/126.0.0.0"
SAFARI_IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
                 "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 "
                 "Mobile/15E148 Safari/604.1")
CHROME_ANDROID = ("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36")
SAFARI_MAC = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/17.5 Safari/605.1.15")
FIREFOX_LINUX = "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0"


@pytest.mark.parametrize("ua,expected", [
    (CHROME_WIN, ("Chrome", "Windows", "desktop")),
    # Edge's string also says Chrome and Safari; the order of checks decides.
    (EDGE_WIN, ("Edge", "Windows", "desktop")),
    (SAFARI_IPHONE, ("Safari", "iOS", "mobile")),
    # Android's string also says Linux.
    (CHROME_ANDROID, ("Chrome", "Android", "mobile")),
    (SAFARI_MAC, ("Safari", "macOS", "desktop")),
    (FIREFOX_LINUX, ("Firefox", "Linux", "desktop")),
    (None, (None, None, "other")),
    ("", (None, None, "other")),
])
def test_user_agents_are_read_into_a_device(ua, expected):
    assert audit.parse_user_agent(ua) == expected


def test_a_device_is_described_in_words():
    assert audit.describe_device("Chrome", "Windows") == "Chrome on Windows"
    assert audit.describe_device("Chrome", None) == "Chrome"
    assert audit.describe_device(None, None) == "Unknown device"


# ── Summaries ───────────────────────────────────────────────────────────────

def test_named_writes_get_a_sentence():
    assert audit.describe_write("PUT", "/api/v1/admin/settings") == \
        "Changed platform settings or API keys"


def test_other_writes_get_a_generated_line_that_names_the_resource():
    assert audit.describe_write("DELETE", "/api/v1/admin/excluded-keywords/{keyword_id}") \
        == "Delete · excluded keywords"
    # No path parameter: creating a thing. With one: acting on a thing.
    assert audit.describe_write("POST", "/api/v1/admin/excluded-keywords") \
        == "Create · excluded keywords"
    assert audit.describe_write("POST", "/api/v1/admin/attractions/{attraction_id}/status") \
        == "Run · attractions › status"


def test_the_last_path_parameter_is_the_target():
    assert audit._target_id({"vendor_id": "v", "login_id": "l"}) == "l"
    assert audit._target_id({}) is None


def test_session_status():
    from datetime import datetime, timedelta, timezone
    now = datetime.now(timezone.utc)
    live = SimpleNamespace(revoked_at=None, expires_at=now + timedelta(minutes=5))
    over = SimpleNamespace(revoked_at=None, expires_at=now - timedelta(minutes=5))
    gone = SimpleNamespace(revoked_at=now, expires_at=now + timedelta(minutes=5))
    assert audit.session_status(live, now) == "active"
    assert audit.session_status(over, now) == "ended"
    # Revoked beats unexpired.
    assert audit.session_status(gone, now) == "revoked"


def test_a_malformed_session_id_is_not_a_session():
    assert audit.parse_sid("not-a-uuid") is None
    assert audit.parse_sid(None) is None
    sid = uuid.uuid4()
    assert audit.parse_sid(str(sid)) == sid


# ── The middleware, end to end ──────────────────────────────────────────────

@pytest.fixture
def app_and_log(monkeypatch):
    """A tiny app with the real middleware and routes shaped like ours."""
    log = []

    async def fake_record(**kw):
        log.append(kw)

    monkeypatch.setattr(audit, "record", fake_record)

    app = FastAPI()
    app.middleware("http")(audit.audit_http_middleware)

    async def authed(request: Request):
        # What verify_admin_token / get_current_vendor do after verifying.
        audit.set_actor(
            request, actor_type="admin", actor_id="root", actor_label="root",
            session_id=str(uuid.uuid4()),
        )

    async def anon():
        return None

    @app.put("/api/v1/admin/settings")
    async def put_settings(request: Request, _=Depends(authed)):
        request.state.audit_detail = {"fields": ["platform_name"]}
        return {"ok": True}

    @app.get("/api/v1/admin/settings")
    async def get_settings(_=Depends(authed)):
        return {"ok": True}

    @app.get("/api/v1/admin/dashboard")
    async def dashboard(_=Depends(authed)):
        return {"ok": True}

    @app.delete("/api/v1/admin/excluded-keywords/{keyword_id}")
    async def delete_kw(keyword_id: str, _=Depends(authed)):
        return {"ok": True}

    @app.post("/api/v1/admin/engagement/announcements")
    async def refused(_=Depends(authed)):
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="no")

    @app.post("/api/v1/admin/unauthenticated")
    async def unauth(_=Depends(anon)):
        return {"ok": True}

    @app.post("/api/v1/partner/activity/seen")
    async def seen(_=Depends(authed)):
        return {"ok": True}

    @app.post("/api/v1/admin/login")
    async def login(_=Depends(authed)):
        return {"ok": True}

    @app.post("/api/v1/auth/login")
    async def traveller_login():
        return {"ok": True}

    return TestClient(app), log


def test_a_write_is_recorded_against_the_actor(app_and_log):
    client, log = app_and_log
    assert client.put("/api/v1/admin/settings").status_code == 200
    assert len(log) == 1
    row = log[0]
    assert row["actor_type"] == "admin" and row["actor_label"] == "root"
    assert row["category"] == "change" and row["method"] == "PUT"
    assert row["route"] == "/api/v1/admin/settings"
    assert row["summary"] == "Changed platform settings or API keys"
    assert row["status_code"] == 200 and row["success"] is True
    # Handed over by the endpoint through request.state.
    assert row["detail"] == {"fields": ["platform_name"]}


def test_the_target_comes_from_the_matched_route(app_and_log):
    client, log = app_and_log
    client.delete("/api/v1/admin/excluded-keywords/abc-123")
    assert log[0]["target_id"] == "abc-123"
    assert log[0]["route"] == "/api/v1/admin/excluded-keywords/{keyword_id}"


def test_a_refused_write_is_still_recorded_and_marked_failed(app_and_log):
    client, log = app_and_log
    assert client.post("/api/v1/admin/engagement/announcements").status_code == 422
    assert log[0]["success"] is False and log[0]["status_code"] == 422
    assert "refused" in log[0]["summary"]


def test_ordinary_reads_are_not_recorded_but_secret_reads_are(app_and_log):
    client, log = app_and_log
    client.get("/api/v1/admin/dashboard")
    assert log == []
    client.get("/api/v1/admin/settings")
    assert len(log) == 1 and log[0]["category"] == "access"


def test_an_unauthenticated_write_is_not_recorded(app_and_log):
    """Otherwise anyone on the internet can grow the table."""
    client, log = app_and_log
    client.post("/api/v1/admin/unauthenticated")
    assert log == []


def test_noise_and_hand_recorded_routes_are_skipped(app_and_log):
    client, log = app_and_log
    client.post("/api/v1/partner/activity/seen")
    client.post("/api/v1/admin/login")
    assert log == []


def test_routes_outside_admin_and_partner_are_ignored(app_and_log):
    client, log = app_and_log
    client.post("/api/v1/auth/login")
    assert log == []


def test_an_audit_failure_never_breaks_the_response(monkeypatch, app_and_log):
    client, log = app_and_log

    async def boom(**kw):
        raise RuntimeError("db down")

    monkeypatch.setattr(audit, "record", boom)
    assert client.put("/api/v1/admin/settings").status_code == 200


# ── record() itself ─────────────────────────────────────────────────────────

def test_record_swallows_a_database_error(monkeypatch):
    class _Boom:
        async def __aenter__(self):
            raise RuntimeError("db down")

        async def __aexit__(self, *a):
            return False

    monkeypatch.setattr(audit, "async_session", lambda: _Boom())
    # Must not raise.
    asyncio.run(audit.record(
        actor_type="admin", actor_id="x", actor_label="x",
        category="change", action="change.put", summary="s",
    ))


def test_a_token_without_a_session_id_is_refused():
    assert asyncio.run(audit.session_is_live(
        None, actor_type="admin", actor_id="root")) is False
    assert asyncio.run(audit.session_is_live(
        "garbage", actor_type="vendor", actor_id="x")) is False
