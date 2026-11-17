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
# Every source counted since long before both windows, unless a test says so.
LONG_AGO = date(2026, 6, 1)
ALL_COUNTED = {k: LONG_AGO for k in [*ACTIONS, "opens", "sessions", "signups"]}


def report(opens=(), actions=(), active=(), signups=None, firsts=None):
    return build_report(DAYS, PREV, opens, actions, active, signups or {}, {**ALL_COUNTED, **(firsts or {})})


def row(rows, key):
    return next(r for r in rows if r["key"] == key)


def test_screens_count_people_once_and_share_is_of_explorers_whose_app_reports():
    rep = report(opens=[
        ("experiences", A, TODAY, 1), ("experiences", A, YESTERDAY, 2), ("experiences", B, TODAY, 1),
        ("home", A, TODAY, 1), ("home", B, TODAY, 1), ("home", C, TODAY, 1), ("home", D, TODAY, 1),
    ])
    exp = row(rep["screens"], "experiences")
    assert (exp["users"], exp["visits"], exp["share"], rep["reporting_explorers"]) == (2, 4, 0.5, 4)
    assert exp["daily"][-2:] == [1, 2]
    assert [r["key"] for r in rep["screens"]] == ["home", "experiences"]


def test_actions_count_people_and_times_across_all_explorers():
    rep = report(actions=[("experience_requests", B, TODAY, 1), ("experience_requests", C, YESTERDAY, 3)])
    req = row(rep["actions"], "experience_requests")
    assert (req["count"], req["users"], req["feature"], req["feature_label"]) == (4, 2, "experiences", "Experiences")
    assert req["daily"][-2:] == [1, 1]


def test_days_before_a_source_has_data_are_not_counted_rather_than_zero():
    rep = report(opens=[("ar", A, TODAY, 1)], actions=[("neva_messages", A, TODAY, 1)],
                 firsts={"opens": YESTERDAY, "neva_messages": DAYS[2]})
    assert row(rep["screens"], "ar")["daily"] == [None] * 5 + [0, 1]
    assert rep["reporting_daily"] == [None] * 5 + [0, 1]
    assert row(rep["actions"], "neva_messages")["daily"] == [None, None, 0, 0, 0, 0, 1]
    assert row(rep["actions"], "neva_messages")["counted_since"] == DAYS[2].isoformat()


def test_comparison_only_when_the_previous_period_was_counted_in_full():
    opens = [("home", A, LAST_WEEK, 1), ("home", B, TODAY, 1)]
    actions = [("neva_messages", C, LAST_WEEK, 5), ("neva_messages", A, TODAY, 1)]
    full = report(opens=opens, actions=actions)
    assert row(full["screens"], "home")["prev_users"] == 1
    assert (row(full["actions"], "neva_messages")["prev_count"], row(full["actions"], "neva_messages")["prev_users"]) == (5, 1)
    # Counting started inside the previous period: no comparison at all.
    part = report(opens=opens, actions=actions, firsts={"opens": PREV[3], "neva_messages": PREV[1]})
    assert row(part["screens"], "home")["prev_users"] is None
    assert row(part["screens"], "home")["prev_share"] is None
    assert row(part["actions"], "neva_messages")["prev_count"] is None


def test_previous_share_is_of_the_explorers_reporting_then():
    rep = report(opens=[("ar", A, LAST_WEEK, 1), ("home", A, LAST_WEEK, 1), ("home", B, LAST_WEEK, 1), ("ar", C, TODAY, 1)])
    ar = row(rep["screens"], "ar")
    assert (ar["users"], ar["share"], ar["prev_users"], ar["prev_share"]) == (1, 1.0, 1, 0.5)


def test_rows_outside_both_windows_are_ignored():
    old = PREV[0] - timedelta(days=1)
    rep = report(opens=[("home", A, old, 1)], actions=[("discover_runs", A, old, 1)], active=[(A, old)])
    assert (rep["screens"], rep["actions"], rep["active_explorers"], rep["reporting_explorers"]) == ([], [], 0, 0)


def test_an_action_with_only_a_previous_period_still_shows_its_drop():
    rep = report(actions=[("forum_posts", A, LAST_WEEK, 2)])
    assert (row(rep["actions"], "forum_posts")["count"], row(rep["actions"], "forum_posts")["prev_count"]) == (0, 2)
    # ...but not when the previous period was not counted in full.
    assert report(actions=[("forum_posts", A, LAST_WEEK, 2)], firsts={"forum_posts": PREV[2]})["actions"] == []


def test_funnel_counts_openers_who_went_on_to_act():
    rep = report(
        opens=[("experiences", A, TODAY, 1), ("experiences", B, TODAY, 1)],
        actions=[("experience_requests", B, TODAY, 1), ("experience_requests", C, TODAY, 1)],
    )
    assert rep["funnels"] == [{
        "feature": "experiences", "label": "Experiences",
        "action": "experience_requests", "action_label": "sent a booking request",
        "opened": 2, "acted": 1,
    }]


def test_no_funnel_before_any_screens_arrive():
    assert report(actions=[("experience_requests", A, TODAY, 1)])["funnels"] == []


def test_signups_and_active_explorers_with_their_comparisons():
    rep = report(
        active=[(A, TODAY), (B, TODAY), (A, YESTERDAY), (C, LAST_WEEK)],
        signups={TODAY: 3, LAST_WEEK: 2},
    )
    assert rep["active_daily"][-2:] == [1, 2]
    assert (rep["active_explorers"], rep["prev_active_explorers"]) == (2, 1)
    assert (rep["new_signups"], rep["prev_new_signups"]) == (3, 2)
    late = report(active=[(A, TODAY)], signups={TODAY: 1}, firsts={"sessions": PREV[1], "signups": PREV[1]})
    assert (late["prev_active_explorers"], late["prev_new_signups"]) == (None, None)
