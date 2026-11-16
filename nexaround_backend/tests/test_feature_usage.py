"""Feature usage page: which features explorers use (app.services.feature_usage).

Pure functions only; the endpoint's SQL just feeds `build_report` its rows.
"""
import uuid
from datetime import date, datetime, timedelta, timezone

from app.services.feature_usage import (
    ACTIONS, FEATURES, FUNNELS, MAX_REPORT_AGE, build_report, clean_opens, window,
)

NOW = datetime(2026, 11, 16, 9, 0, tzinfo=timezone.utc)
V1, V2 = uuid.uuid4(), uuid.uuid4()
A, B, C, D = (uuid.uuid4() for _ in range(4))


# --- what the app may report -------------------------------------------------

def test_unknown_features_are_dropped():
    rows = clean_opens([
        {"visit_id": V1, "feature": "experiences", "opened_at": NOW},
        {"visit_id": V1, "feature": "admin_panel", "opened_at": NOW},
        {"visit_id": None, "feature": "home", "opened_at": NOW},
    ], NOW)
    assert [r["feature"] for r in rows] == ["experiences"]


def test_a_visit_counts_each_feature_once_keeping_the_first_open():
    early = NOW - timedelta(minutes=5)
    rows = clean_opens([
        {"visit_id": V1, "feature": "home", "opened_at": NOW},
        {"visit_id": V1, "feature": "home", "opened_at": early},
        {"visit_id": V2, "feature": "home", "opened_at": NOW},
    ], NOW)
    assert sorted((r["visit_id"] == V1, r["opened_at"]) for r in rows) == [(False, NOW), (True, early)]


def test_times_are_clamped_to_now_and_old_reports_dropped():
    rows = clean_opens([
        {"visit_id": V1, "feature": "ar", "opened_at": NOW + timedelta(days=2)},     # phone clock ahead
        {"visit_id": V1, "feature": "neva", "opened_at": NOW - MAX_REPORT_AGE - timedelta(minutes=1)},
        {"visit_id": V1, "feature": "discover", "opened_at": None},                  # no time sent
        {"visit_id": V1, "feature": "plans", "opened_at": datetime(2026, 11, 15, 8, 0)},  # naive = UTC
    ], NOW)
    got = {r["feature"]: r["opened_at"] for r in rows}
    assert got == {
        "ar": NOW,
        "discover": NOW,
        "plans": datetime(2026, 11, 15, 8, 0, tzinfo=timezone.utc),
    }


def test_every_action_belongs_to_a_known_feature():
    assert all(feature in FEATURES for _, feature in ACTIONS.values())


def test_every_funnel_pairs_a_feature_with_one_of_its_actions():
    assert all(ACTIONS[action][1] == feature for feature, (action, _) in FUNNELS.items())


# --- the report ---------------------------------------------------------------

def test_window_is_the_last_days_and_the_same_length_before():
    current, previous = window(date(2026, 11, 16), 7)
    assert (current[0], current[-1], len(current)) == (date(2026, 11, 10), date(2026, 11, 16), 7)
    assert (previous[0], previous[-1], len(previous)) == (date(2026, 11, 3), date(2026, 11, 9), 7)


DAYS, PREV = window(date(2026, 11, 16), 7)
TODAY, YESTERDAY, LAST_WEEK = DAYS[-1], DAYS[-2], PREV[0]


def report(opens=(), actions=(), active=(), signups=None, since=None):
    return build_report(DAYS, PREV, opens, actions, active, signups or {}, since)


def feature(rep, key):
    return next(f for f in rep["features"] if f["key"] == key)


def test_a_feature_counts_each_explorer_once_whether_opened_or_used():
    rep = report(
        opens=[("experiences", A, TODAY, 1), ("experiences", A, YESTERDAY, 2), ("experiences", B, TODAY, 1)],
        actions=[("experience_requests", B, TODAY, 1), ("experience_requests", C, TODAY, 3)],
    )
    exp = feature(rep, "experiences")
    assert (exp["users"], exp["open_users"], exp["opens"], exp["action_users"]) == (3, 2, 4, 2)
    assert exp["daily"][-2:] == [1, 3]   # yesterday A; today A, B, C


def test_previous_window_feeds_only_the_comparison():
    rep = report(
        opens=[("neva", A, LAST_WEEK, 1), ("neva", B, TODAY, 1)],
        actions=[("neva_messages", C, LAST_WEEK, 5)],
    )
    neva = feature(rep, "neva")
    assert (neva["users"], neva["prev_users"]) == (1, 2)
    msgs = next(a for a in rep["actions"] if a["key"] == "neva_messages")
    assert (msgs["count"], msgs["prev_count"], msgs["prev_users"]) == (0, 5, 1)
    assert rep["explorers"] == 1


def test_rows_outside_both_windows_are_ignored():
    old = PREV[0] - timedelta(days=1)
    rep = report(opens=[("home", A, old, 1)], actions=[("discover_runs", A, old, 1)], active=[(A, old)])
    assert (rep["features"], rep["explorers"], rep["active_explorers"]) == ([], 0, 0)


def test_features_rank_by_explorers_and_share_is_of_all_explorers():
    rep = report(
        opens=[("home", A, TODAY, 1), ("home", B, TODAY, 1), ("ar", A, TODAY, 1)],
        active=[(A, TODAY), (B, TODAY), (C, TODAY), (D, TODAY)],
    )
    assert [f["key"] for f in rep["features"]] == ["home", "ar"]
    assert (rep["explorers"], feature(rep, "home")["share"], feature(rep, "ar")["share"]) == (4, 0.5, 0.25)


def test_an_explorer_seen_only_through_an_action_still_counts():
    # Old app builds report no opens and some explorers have no 30 s visit,
    # but a saved plan is still real use.
    rep = report(actions=[("odyssey_plans", A, TODAY, 1)], active=[(B, TODAY)])
    assert (rep["explorers"], rep["active_explorers"]) == (2, 1)


def test_coverage_counts_explorers_whose_app_reports_opens():
    rep = report(opens=[("home", A, TODAY, 1)], active=[(A, TODAY), (B, TODAY)], since=TODAY)
    assert (rep["reporting_explorers"], rep["active_explorers"], rep["opens_since"]) == (1, 2, TODAY.isoformat())


def test_funnel_counts_openers_who_went_on_to_act():
    rep = report(
        opens=[("experiences", A, TODAY, 1), ("experiences", B, TODAY, 1)],
        actions=[("experience_requests", B, TODAY, 1), ("experience_requests", C, TODAY, 1)],
    )
    assert rep["funnels"] == [{
        "feature": "experiences", "label": "Experiences",
        "action": "experience_requests", "action_label": "sent a request",
        "opened": 2, "acted": 1,
    }]


def test_no_funnel_before_any_opens_arrive():
    rep = report(actions=[("experience_requests", A, TODAY, 1)])
    assert rep["funnels"] == []


def test_signups_and_active_per_day():
    rep = report(
        active=[(A, TODAY), (B, TODAY), (A, YESTERDAY), (C, LAST_WEEK)],
        signups={TODAY: 3, LAST_WEEK: 2},
    )
    assert rep["active_daily"][-2:] == [1, 2]
    assert (rep["new_signups"], rep["prev_new_signups"], rep["prev_active_explorers"]) == (3, 2, 1)
