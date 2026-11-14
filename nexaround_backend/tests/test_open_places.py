"""Free map data for free users (2026-11-12).

Pure rules (sections, areas, score, version gate), who gets free data, the
fallback order (free data → Geoapify → today's Google method) and the medical
exemption. Nothing here touches the network, DuckDB or the database.
"""
import asyncio
import time
import uuid
from datetime import timedelta

import pytest

from app.core import request_context
from app.services import banded_places_service, open_places_service, plan_service, spend_guard
from app.services.open_data import geoapify_places, sections
from app.services.open_data.score import label_for, popularity_score
from app.services.plan_service import EXPLORER, VOYAGER, PlanInfo


def run(coro):
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def _clean_context():
    tokens = [
        request_context.app_version_var.set(None),
        request_context.map_cap_exempt_var.set(False),
        request_context.user_id_var.set(None),
    ]
    yield
    request_context.user_id_var.reset(tokens[2])
    request_context.map_cap_exempt_var.reset(tokens[1])
    request_context.app_version_var.reset(tokens[0])


# ── Sections ────────────────────────────────────────────────────────────────

def test_sections_from_overture_categories():
    assert sections.section_for(["health_care", "hospital"], "hospital") == "Hospital"
    assert sections.section_for(
        ["shopping", "specialty_store", "pharmacy_and_drug_store", "pharmacy"],
        "pharmacy_and_drug_store") == "Medical"
    assert sections.section_for(["health_care", "outpatient_care_facility", "dental_clinic"],
                                "dental_clinic") == "Medical"
    assert sections.section_for(["food_and_drink", "restaurant"], "restaurant") == "Food & Drink"
    assert sections.section_for(["lodging", "hotel"], "hotel") == "Hotels"
    assert sections.section_for(["shopping", "shopping_mall"], "shopping_mall") == "Shopping"
    # Left out: RV parks, car dealers, and sights (they stay on Google).
    assert sections.section_for(["lodging", "rv_park"], "rv_park") is None
    assert sections.section_for(["shopping", "vehicle_dealer"], "auto_dealer") is None
    assert sections.section_for(["cultural_and_historic", "historic_site"], "historic_site") is None
    assert sections.section_for(None, None) is None


def test_tags_match_google_types():
    assert sections.tags_for("Food & Drink", "barbecue_restaurant") == ["restaurant"]
    assert sections.tags_for("Food & Drink", "bar") == ["bar"]
    assert sections.tags_for("Food & Drink", "coffee_shop") == ["cafe"]
    assert sections.tags_for("Food & Drink", "non_alcoholic_beverage_venue") == ["cafe"]
    assert sections.tags_for("Medical", "pharmacy_and_drug_store") == ["pharmacy"]
    assert sections.tags_for("Medical", "dental_clinic") == ["dentist"]
    assert sections.tags_for("Hospital", "hospital") == ["hospital"]


def test_download_areas():
    assert sections.tile_of(15.88, 108.33) == "15.5_108.0"
    assert sections.tile_of(-33.87, 151.21) == "-34.0_151.0"
    assert sections.tile_bbox("15.5_108.0") == (15.5, 108.0, 16.0, 108.5)
    small = sections.tiles_for_circle(15.75, 108.25, 2000)
    assert small == ["15.5_108.0"]
    wide = sections.tiles_for_circle(15.88, 108.33, 50000)
    assert "15.5_108.0" in wide and 4 <= len(wide) <= 9


def test_version_gate():
    assert sections.version_at_least("1.0.18", "1.0.18")
    assert sections.version_at_least("1.0.19+180", "1.0.18")
    assert sections.version_at_least("1.1", "1.0.18")
    assert not sections.version_at_least("1.0.17", "1.0.18")
    assert not sections.version_at_least(None, "1.0.18")   # old builds send no version
    assert sections.version_at_least(None, "")             # no minimum set
    assert sections.version_at_least(None, "0")            # "0" = every build
    assert sections.version_at_least("1.0.16", "0")


# ── Score ───────────────────────────────────────────────────────────────────

def test_score_rewards_an_active_business():
    bare = popularity_score(confidence=0.6)
    full = popularity_score(confidence=0.9, website="w", phone="p", social="s", brand="b")
    assert bare == 24 and full == 81
    assert popularity_score(confidence=1, website="w", phone="p", social="s", brand="b",
                            wiki_views=50000, our_points=99) == 100
    assert popularity_score(confidence=None) == 0


def test_labels():
    assert label_for(wiki_views=5000, score=70) == "Famous"
    assert label_for(our_points=6, score=30) == "Popular with travellers"
    assert label_for(score=90) is None


def test_around_you_sorts_free_places_by_score():
    pool = [
        {"id": "a", "popularity": 20, "distance_m": 100},
        {"id": "b", "popularity": 80, "distance_m": 900},
        {"id": "c", "popularity": 80, "distance_m": 300},
    ]
    assert [p["id"] for p in sorted(pool, key=banded_places_service._rank_for_selection)] == ["c", "b", "a"]
    # Google places keep their rating order; popularity is never set on them.
    g = [{"id": "x", "rating": 4.8, "review_count": 900}, {"id": "y", "rating": 3.9, "review_count": 900}]
    assert [p["id"] for p in sorted(g, key=banded_places_service._rank_for_selection)] == ["x", "y"]


# ── Who gets free data ──────────────────────────────────────────────────────

@pytest.fixture
def cfg(monkeypatch):
    state = {"plan": PlanInfo()}
    monkeypatch.setattr(plan_service, "_config", {
        "enforce": True, "test_ids": set(), "limits": plan_service.merge_limits(None),
        "min_app_version": "", "free_data": "on", "free_data_min_version": "1.0.18",
    })
    monkeypatch.setattr(plan_service, "_config_at", time.time() + 3600)

    async def _get_plan(uid):
        return state["plan"]

    monkeypatch.setattr(plan_service, "get_plan", _get_plan)
    request_context.app_version_var.set("1.0.18")
    return state


def test_free_user_on_new_app_gets_free_data(cfg):
    assert run(plan_service.places_source_for(uuid.uuid4(), "Food & Drink")) == "open"
    assert run(plan_service.places_source_for(uuid.uuid4(), "Hospital")) == "open"


def test_sights_stay_on_google(cfg):
    for cat in ("POI", "Attractions", "Nature", "Experiences", None):
        assert run(plan_service.places_source_for(uuid.uuid4(), cat)) == "google"


def test_paid_users_old_apps_and_switch_off_use_google(cfg):
    uid = uuid.uuid4()
    request_context.app_version_var.set("1.0.17")
    assert run(plan_service.places_source_for(uid, "Shopping")) == "google"
    request_context.app_version_var.set(None)
    assert run(plan_service.places_source_for(uid, "Shopping")) == "google"
    request_context.app_version_var.set("1.0.18")
    cfg["plan"] = PlanInfo(plan=VOYAGER)
    assert run(plan_service.places_source_for(uid, "Shopping")) == "google"
    cfg["plan"] = PlanInfo(plan=EXPLORER)
    plan_service._config["free_data"] = "off"
    assert run(plan_service.places_source_for(uid, "Shopping")) == "google"


def test_test_mode_is_test_accounts_only(cfg):
    tester, other = uuid.uuid4(), uuid.uuid4()
    plan_service._config["free_data"] = "test"
    plan_service._config["test_ids"] = {str(tester)}
    assert run(plan_service.places_source_for(tester, "Hotels")) == "open"
    assert run(plan_service.places_source_for(other, "Hotels")) == "google"


# ── Fallback order ──────────────────────────────────────────────────────────

def _fake_places(n, prefix="op_"):
    return [{
        "id": f"{prefix}{i}", "name": f"Place {prefix}{i}", "latitude": 1.0, "longitude": 2.0,
        "rating": 0.0, "review_count": 0, "photo_urls": [], "tags": ["restaurant"],
        "distance_m": 100.0 * i, "is_active": True, "created_at": "2026-11-12T00:00:00+00:00",
        "popularity": 50, "data_source": "open",
    } for i in range(n)]


@pytest.fixture
def sources(monkeypatch):
    state = {"rows": 0, "geo": 0, "google_ok": True, "asked_geo": False}

    async def _rows(*a, **k):
        return _fake_places(state["rows"])

    async def _geo(*a, **k):
        state["asked_geo"] = True
        return _fake_places(state["geo"], prefix="ga_")

    async def _google_ok(uid):
        return state["google_ok"]

    async def _tiles(*a, **k):
        return True

    async def _record(*a, **k):
        return None

    monkeypatch.setattr(open_places_service, "_rows", _rows)
    monkeypatch.setattr(open_places_service, "_geoapify", _geo)
    monkeypatch.setattr(open_places_service, "_google_allowed", _google_ok)
    monkeypatch.setattr(open_places_service, "ensure_tiles", _tiles)
    monkeypatch.setattr(open_places_service, "_record", _record)
    return state


def _nearby():
    return run(open_places_service.nearby(
        user_id=uuid.uuid4(), latitude=1.0, longitude=2.0, category="Food & Drink", radius=5000,
    ))


def test_enough_free_places_never_asks_anyone_else(sources):
    sources["rows"] = 12
    res = _nearby()
    assert res.source == "open" and len(res.places) == 12
    assert not sources["asked_geo"]
    assert all(p.rating == 0 and p.data_source == "open" for p in res.places)


def test_new_area_is_topped_up_from_geoapify(sources):
    sources["rows"], sources["geo"] = 2, 10
    res = _nearby()
    assert res is not None and sources["asked_geo"] and len(res.places) == 12


def test_too_few_free_places_hands_over_to_google(sources):
    sources["rows"], sources["geo"] = 2, 1
    assert _nearby() is None


def test_past_the_google_limit_free_places_are_still_shown(sources):
    sources["rows"], sources["geo"], sources["google_ok"] = 2, 1, False
    res = _nearby()
    assert res is not None and len(res.places) == 3


def test_free_data_failure_falls_back_to_google(sources, monkeypatch):
    async def _broken(*a, **k):
        raise RuntimeError("db down")

    monkeypatch.setattr(open_places_service, "_rows", _broken)
    assert _nearby() is None


# ── Medical exemption, Geoapify mapping ────────────────────────────────────

def test_medical_requests_skip_the_plan_map_limit(monkeypatch):
    called = {"cap": False}

    async def _cap(uid):
        called["cap"] = True
        raise spend_guard.SpendBlocked("plan_map_limit", "used up")

    async def _cfg():
        return {"enforce": False, "monthly_budget": 0, "user_daily_cap": 0}

    monkeypatch.setattr(spend_guard, "_check_plan_map_cap", _cap)
    monkeypatch.setattr(spend_guard, "_load_config", _cfg)
    uid = uuid.uuid4()
    request_context.map_cap_exempt_var.set(True)
    run(spend_guard.check(uid))
    assert not called["cap"]
    request_context.map_cap_exempt_var.set(False)
    with pytest.raises(spend_guard.SpendBlocked):
        run(spend_guard.check(uid))


def test_geoapify_feature_to_place():
    f = {"properties": {
        "name": "Pho 24", "place_id": "abc123", "lat": 16.05, "lon": 108.22,
        "categories": ["catering", "catering.restaurant"], "formatted": "1 Tran Phu, Da Nang",
        "distance": 420, "datasource": {"raw": {"phone": "+84 1", "opening_hours": "Mo-Su 07:00-22:00"}},
    }}
    p = geoapify_places.to_place(f, "Food & Drink")
    assert p["id"] == "ga_abc123" and p["tags"] == ["restaurant"] and p["phone"] == "+84 1"
    assert p["distance_m"] == 420.0
    assert geoapify_places.to_place({"properties": {"name": ""}}, "Food & Drink") is None


def test_open_ids():
    assert open_places_service.is_open_id("op_123") and open_places_service.is_open_id("ga_x")
    assert not open_places_service.is_open_id("ChIJabc")
