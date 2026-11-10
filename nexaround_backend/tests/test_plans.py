"""Subscription plans (Explorer / Voyager / Globetrotter), 2026-11-10.

Pure rules (limits, plan choice, Odyssey windows, RevenueCat parsing) and the
enforcement points, with Redis, the database and the settings table replaced
by fakes — the test container shares the live stack's Redis.
"""
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.api.v1 import billing, proxy
from app.core import job_queue, request_context
from app.services import plan_service, spend_guard, telemetry
from app.services.plan_service import (
    EXPLORER, GLOBETROTTER, VOYAGER, PlanInfo, PlanLimitExceeded,
)

UTC = timezone.utc
NOW = datetime(2026, 11, 10, 12, 0, tzinfo=UTC)


def row(plan, source="revenuecat", end=None, start=None, period="monthly"):
    return SimpleNamespace(plan=plan, source=source, period_end=end, period_start=start,
                           period=period, store="app_store", status="active", auto_renew=True)


class FakeRedis:
    def __init__(self):
        self.data = {}
        self.lists = {}

    async def get(self, k):
        return self.data.get(k)

    async def set(self, k, v, ex=None, nx=False):
        self.data[k] = v
        return True

    async def delete(self, k):
        self.data.pop(k, None)

    async def incr(self, k):
        self.data[k] = str(int(self.data.get(k) or 0) + 1)
        return int(self.data[k])

    async def expire(self, k, ttl):
        return True

    async def lpush(self, k, v):
        self.lists.setdefault(k, []).insert(0, ("L", v))

    async def rpush(self, k, v):
        self.lists.setdefault(k, []).append(("R", v))


@pytest.fixture
def plans(monkeypatch):
    """Plans on, with default limits, and a controllable plan per user."""
    fake = FakeRedis()
    monkeypatch.setattr(plan_service, "_redis", lambda: fake)
    monkeypatch.setattr(plan_service, "_ns", lambda: "test")
    monkeypatch.setattr(plan_service, "_config", {
        "enforce": True, "test_ids": set(),
        "limits": plan_service.merge_limits(None), "min_app_version": "",
    })
    monkeypatch.setattr(plan_service, "_config_at", time.time() + 3600)
    state = SimpleNamespace(plan=PlanInfo(), odyssey_used=0)

    async def _get_plan(uid):
        return state.plan

    async def _used(uid, start):
        return state.odyssey_used

    monkeypatch.setattr(plan_service, "get_plan", _get_plan)
    monkeypatch.setattr(plan_service, "odyssey_used", _used)
    state.redis = fake
    return state


def run(coro):
    import asyncio
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def _clean_request_context():
    """These tests set request ContextVars; later test files must not see them."""
    tokens = [
        request_context.flags_var.set(None),
        request_context.route_var.set(None),
        request_context.user_id_var.set(None),
    ]
    yield
    request_context.user_id_var.reset(tokens[2])
    request_context.route_var.reset(tokens[1])
    request_context.flags_var.reset(tokens[0])


# ── Pure rules ──────────────────────────────────────────────────────────────

def test_limits_match_the_document():
    lim = plan_service.merge_limits(None)
    assert [lim[p]["odyssey_per_period"] for p in (EXPLORER, VOYAGER, GLOBETROTTER)] == [1, 8, 15]
    assert [lim[p]["odyssey_max_days"] for p in (EXPLORER, VOYAGER, GLOBETROTTER)] == [5, 10, 14]
    assert [lim[p]["neva_per_day"] for p in (EXPLORER, VOYAGER, GLOBETROTTER)] == [20, 100, 300]
    assert [lim[p]["ar_radius_m"] for p in (EXPLORER, VOYAGER, GLOBETROTTER)] == [2000, 10000, 10000]
    assert lim[EXPLORER]["odyssey_lite"] and not lim[VOYAGER]["odyssey_lite"]
    assert lim[GLOBETROTTER]["priority_queue"] and not lim[VOYAGER]["priority_queue"]
    assert (lim[EXPLORER]["map_day_usd"], lim[EXPLORER]["map_month_usd"]) == (0.15, 0.50)


def test_admin_overrides_merge_but_cannot_invent_keys():
    lim = plan_service.merge_limits({"explorer": {"neva_per_day": 30, "bogus": 1}, "nope": {}})
    assert lim[EXPLORER]["neva_per_day"] == 30
    assert "bogus" not in lim[EXPLORER] and "nope" not in lim


def test_best_plan_takes_the_highest_live_row():
    rows = [row(VOYAGER, end=NOW + timedelta(days=5)),
            row(GLOBETROTTER, source="admin", end=None),
            row(GLOBETROTTER, end=NOW - timedelta(days=1))]
    info = plan_service.best_plan(rows, NOW)
    assert info.plan == GLOBETROTTER and info.source == "admin"


def test_best_plan_is_explorer_when_everything_expired():
    assert plan_service.best_plan([row(VOYAGER, end=NOW - timedelta(seconds=1))], NOW).plan == EXPLORER
    assert plan_service.best_plan([], NOW).plan == EXPLORER


def test_explorer_odyssey_window_is_the_calendar_month():
    start, reset = plan_service.odyssey_window(PlanInfo(), NOW)
    assert start == datetime(2026, 11, 1, tzinfo=UTC) and reset == datetime(2026, 12, 1, tzinfo=UTC)


def test_paid_odyssey_window_renews_on_the_billing_day():
    info = PlanInfo(plan=VOYAGER, period_start=datetime(2026, 9, 20, 8, 0, tzinfo=UTC))
    start, reset = plan_service.odyssey_window(info, NOW)
    assert start == datetime(2026, 10, 20, 8, 0, tzinfo=UTC)
    assert reset == datetime(2026, 11, 20, 8, 0, tzinfo=UTC)


def test_paid_window_from_the_31st_survives_short_months():
    info = PlanInfo(plan=VOYAGER, period_start=datetime(2026, 1, 31, tzinfo=UTC))
    start, reset = plan_service.odyssey_window(info, datetime(2026, 3, 5, tzinfo=UTC))
    assert (start, reset) == (datetime(2026, 2, 28, tzinfo=UTC), datetime(2026, 3, 31, tzinfo=UTC))


def test_radius_caps():
    lim = plan_service.merge_limits(None)[EXPLORER]
    assert plan_service.radius_cap(lim, "POI", "ar") == 2000
    assert plan_service.radius_cap(lim, "POI", None) == 25000
    assert plan_service.radius_cap(lim, "Hospital", "ar") is None
    assert plan_service.radius_cap(lim, "Medical", None) is None


# ── Enforcement ─────────────────────────────────────────────────────────────

def test_odyssey_explorer_gets_one_lite_plan(plans):
    grant = run(plan_service.check_odyssey(uuid.uuid4(), 5))
    assert grant.lite and not grant.priority
    plans.odyssey_used = 1
    with pytest.raises(PlanLimitExceeded) as e:
        run(plan_service.check_odyssey(uuid.uuid4(), 3))
    assert e.value.feature == "odyssey" and e.value.limit == 1


def test_odyssey_trip_length_per_plan(plans):
    with pytest.raises(PlanLimitExceeded) as e:
        run(plan_service.check_odyssey(uuid.uuid4(), 6))
    assert e.value.feature == "odyssey_days"
    plans.plan = PlanInfo(plan=GLOBETROTTER, period_start=NOW - timedelta(days=3))
    grant = run(plan_service.check_odyssey(uuid.uuid4(), 14))
    assert grant.priority and not grant.lite


def test_retry_of_a_counted_plan_skips_the_count(plans):
    plans.odyssey_used = 1
    run(plan_service.check_odyssey(uuid.uuid4(), 4, new_plan=False))


def test_nothing_is_limited_until_enforced(plans, monkeypatch):
    plan_service._config["enforce"] = False
    plans.odyssey_used = 99
    grant = run(plan_service.check_odyssey(uuid.uuid4(), 14))
    assert not grant.lite
    run(plan_service.check_neva(uuid.uuid4()))
    assert run(plan_service.radius_cap_for(uuid.uuid4(), "POI", "ar")) is None


def test_test_accounts_are_limited_before_go_live(plans):
    uid = uuid.uuid4()
    plan_service._config["enforce"] = False
    plan_service._config["test_ids"] = {str(uid)}
    with pytest.raises(PlanLimitExceeded):
        run(plan_service.check_odyssey(uid, 9))
    run(plan_service.check_odyssey(uuid.uuid4(), 9))  # everyone else: unlimited


def test_neva_daily_limit(plans):
    uid = uuid.uuid4()
    for _ in range(20):
        run(plan_service.check_neva(uid))
        run(plan_service.count_neva(uid))
    with pytest.raises(PlanLimitExceeded) as e:
        run(plan_service.check_neva(uid))
    assert e.value.limit == 20 and e.value.resets_at.hour == 0


def test_bands_explorer_two_medical_all(plans):
    assert run(plan_service.max_bands_for(uuid.uuid4(), "POI")) == 2
    assert run(plan_service.max_bands_for(uuid.uuid4(), "Hospital")) is None
    plans.plan = PlanInfo(plan=VOYAGER)
    assert run(plan_service.max_bands_for(uuid.uuid4(), "POI")) is None


def test_limit_body_is_readable_by_old_apps():
    body = PlanLimitExceeded("neva", "You have used today's messages.", limit=20).body()
    assert body["detail"] == "You have used today's messages."
    assert body["code"] == "plan_limit" and body["feature"] == "neva"


# ── Live map data limit ─────────────────────────────────────────────────────

@pytest.fixture
def map_guard(monkeypatch):
    spent = {"day": 0.0, "month": 0.0}

    async def _caps(uid):
        return 0.15, 0.50

    async def _spend(uid):
        return spent["day"], spent["month"]

    async def _cfg(force=False):
        return {"monthly_budget": 0, "user_daily_cap": 0, "enforce": False}

    monkeypatch.setattr(plan_service, "map_caps", _caps)
    monkeypatch.setattr(spend_guard, "user_map_spend", _spend)
    monkeypatch.setattr(spend_guard, "_load_config", _cfg)
    return spent


def test_map_cap_blocks_and_flags_the_response(map_guard):
    flags = {}
    request_context.flags_var.set(flags)
    request_context.route_var.set("/api/v1/places/nearby")
    uid = uuid.uuid4()
    assert run(spend_guard.allowed(uid)) == (True, None)
    map_guard["day"] = 0.16
    ok, reason = run(spend_guard.allowed(uid))
    assert not ok and "saved places" in reason
    assert flags == {"plan_limit": "live_map"}


def test_map_cap_uses_the_request_user_when_none_given(map_guard):
    request_context.route_var.set("/api/v1/places/nearby/banded")
    request_context.user_id_var.set(uuid.uuid4())
    map_guard["month"] = 0.60
    assert run(spend_guard.allowed(None))[0] is False


def test_map_cap_spares_odyssey_and_voice(map_guard):
    uid = uuid.uuid4()
    map_guard["day"] = 9.0
    request_context.route_var.set("/api/v1/itineraries/odyssey/generate")
    assert run(spend_guard.allowed(uid))[0] is True
    request_context.route_var.set("/api/v1/neva/voice")
    assert run(spend_guard.allowed(uid, map_data=False))[0] is True


def test_map_spend_counters_only_count_map_calls(monkeypatch):
    monkeypatch.setattr(telemetry, "_NS", "t")
    base = {"ts": "2026-11-10T12:00:00+00:00", "user_id": "u1"}
    keys = [k for k, _ in telemetry._spend_keys({**base, "provider": "google_maps",
                                                   "route": "/api/v1/places/nearby"})]
    assert "spend:t:map:u1:d:2026-11-10" in keys and "spend:t:map:u1:m:2026-11" in keys
    keys = [k for k, _ in telemetry._spend_keys({**base, "provider": "google_maps",
                                                   "route": "/api/v1/itineraries/odyssey/generate"})]
    assert not any(":map:" in k for k in keys)
    keys = [k for k, _ in telemetry._spend_keys({**base, "provider": "gemini", "route": "/x"})]
    assert not any(":map:" in k for k in keys)
    assert spend_guard.map_spend_keys("u1", NOW) == (
        f"spend:{spend_guard._ns()}:map:u1:d:2026-11-10", f"spend:{spend_guard._ns()}:map:u1:m:2026-11")


# ── Neva through the Gemini proxy, priority queue ───────────────────────────

def test_neva_prompt_is_recognised_in_the_proxy():
    neva = {"systemInstruction": {"parts": [{"text": "You are Neva — a warm, witty ..."}]}}
    assert proxy._is_neva_prompt(neva)
    # What the app actually sends (gemini_service.dart): snake_case.
    assert proxy._is_neva_prompt({"system_instruction": {"parts": [{"text": "You are Neva — hi"}]}})
    assert not proxy._is_neva_prompt({"contents": []})
    assert not proxy._is_neva_prompt({"systemInstruction": "plain"})


def test_priority_jobs_jump_the_queue(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setattr(job_queue, "_get_redis", lambda: fake)
    run(job_queue.enqueue("generate_odyssey", itinerary_id="a"))
    run(job_queue.enqueue("generate_odyssey", _priority=True, itinerary_id="b"))
    pushed = fake.lists[job_queue.pending_key()]
    assert [side for side, _ in pushed] == ["L", "R"]
    assert "_priority" not in json.loads(pushed[1][1])["kwargs"]


# ── RevenueCat ──────────────────────────────────────────────────────────────

def _iso(dt):
    return dt.isoformat().replace("+00:00", "Z")


def test_app_store_monthly_voyager():
    sub = {
        "entitlements": {"voyager": {"product_identifier": "voyager_monthly",
                                     "expires_date": _iso(NOW + timedelta(days=20)),
                                     "purchase_date": _iso(NOW - timedelta(days=10))}},
        "subscriptions": {"voyager_monthly": {"store": "app_store", "is_sandbox": True}},
    }
    s = billing.state_from_subscriber(sub, NOW)
    assert (s["plan"], s["period"], s["store"], s["status"]) == (VOYAGER, "monthly", "app_store", "active")
    assert s["environment"] == "SANDBOX" and s["auto_renew"]


def test_play_yearly_globetrotter_beats_voyager():
    sub = {
        "entitlements": {
            "voyager": {"product_identifier": "voyager:monthly",
                        "expires_date": _iso(NOW + timedelta(days=3))},
            "globetrotter": {"product_identifier": "globetrotter:yearly",
                             "expires_date": _iso(NOW + timedelta(days=300))},
        },
        "subscriptions": {"globetrotter": {"store": "PLAY_STORE"}},
    }
    s = billing.state_from_subscriber(sub, NOW)
    assert (s["plan"], s["period"], s["store"]) == (GLOBETROTTER, "yearly", "play_store")


def test_cancelled_billing_issue_expired_refunded():
    def state(extra, expires_days=10):
        return billing.state_from_subscriber({
            "entitlements": {"voyager": {"product_identifier": "voyager_monthly",
                                         "expires_date": _iso(NOW + timedelta(days=expires_days))}},
            "subscriptions": {"voyager_monthly": extra},
        }, NOW)
    assert state({"unsubscribe_detected_at": "x"})["status"] == "cancelled"
    assert state({"billing_issues_detected_at": "x"})["status"] == "billing_issue"
    assert state({}, expires_days=-1)["status"] == "expired"
    refunded = state({"refunded_at": "x"})
    assert refunded["status"] == "expired" and refunded["period_end"] <= NOW


def test_no_plan_entitlement_means_none():
    assert billing.state_from_subscriber({"entitlements": {"pro": {}}}, NOW) is None


def test_event_fallback():
    e = {"type": "INITIAL_PURCHASE", "product_id": "globetrotter_yearly", "store": "APP_STORE",
         "environment": "PRODUCTION", "entitlement_ids": ["globetrotter"],
         "expiration_at_ms": (NOW + timedelta(days=365)).timestamp() * 1000,
         "purchased_at_ms": NOW.timestamp() * 1000}
    s = billing.state_from_event(e, NOW)
    assert (s["plan"], s["period"], s["status"]) == (GLOBETROTTER, "yearly", "active")
    s = billing.state_from_event({**e, "type": "EXPIRATION"}, NOW)
    assert s["status"] == "expired" and s["period_end"] <= NOW
    s = billing.state_from_event({**e, "type": "PRODUCT_CHANGE", "new_product_id": "voyager_monthly",
                                  "entitlement_ids": []}, NOW)
    assert s["plan"] == VOYAGER


def test_event_user_ids():
    uid, other = uuid.uuid4(), uuid.uuid4()
    assert billing.event_user_ids({"app_user_id": str(uid)}) == [uid]
    assert billing.event_user_ids({"app_user_id": "$RCAnonymousID:abc", "aliases": [str(uid)]}) == [uid]
    ids = billing.event_user_ids({"type": "TRANSFER", "transferred_from": [str(uid)],
                                  "transferred_to": [str(other)]})
    assert set(ids) == {uid, other}
