"""What explorers use in the app: the admin's Feature usage page.

Everything counts people (unique explorers) per Sri Lanka day, from two
sources kept apart, because they cover different groups of explorers:

- Screens (`feature_opens`): screens the app saw on screen for 5+ seconds with
  the app in the foreground. Only builds from November 2026 report them, so
  shares are taken of the explorers whose app reports screens, a fair sample
  that grows as people update.
- Actions: things explorers finished that are saved anyway (an Odyssey plan,
  a Discover search, a NEVA message, a City Guide trip started, an experience
  request, a story posted). These cover every explorer.

Each source only counts from its first saved row (NEVA messages from 1 Oct
2026, screens from the app update), so a day before that is "not counted yet",
never zero, and a comparison with the previous period is only given when that
period was counted in full.

API requests are deliberately not a source. The app loads data in the
background (the hidden AR tab, the home map), and Experiences, City Guides,
Stories and Museums leave no row in api_events at all, so request counts both
overstate and miss real use.
"""
from datetime import date, datetime, time, timedelta, timezone
from typing import Iterable, Optional
from zoneinfo import ZoneInfo

from sqlalchemy import text

# The screens the app may report, key -> label. Anything else is dropped. The
# app mirrors the keys in its AppFeature class; labels can change freely.
FEATURES = {
    "home": "Home",
    "ar": "AR camera",
    "neva": "NEVA assistant",
    "discover": "Discover (browse places)",
    "plans": "My plans",
    "odyssey_planner": "Odyssey trip planner",
    "mini_tour": "Walking Challenge",
    "city_guides": "City Guides",
    "experiences": "Experiences",
    "museums": "Museums",
    "travel_stories": "Travel Stories",
    "travel_journal": "Travel journal",
    "forum": "Forum",
    "place_details": "Place details",
    "full_map": "Full-screen map",
    "directions": "Directions",
    "profile": "Profile",
    "subscription_plans": "Subscription plans",
    # The "Where should I go?" banner on Home opens a sheet over it, so the app
    # reports Home for it; its plans are counted as an action instead.
    "where_should_i_go": "Where Should I Go?",
}

# Saved actions, key -> (label, the screen it belongs to).
ACTIONS = {
    "odyssey_plans": ("Odyssey trip plans requested", "odyssey_planner"),
    "mini_tours": ("Walking Challenges started", "mini_tour"),
    "discover_runs": ("Where Should I Go? plans", "where_should_i_go"),
    "neva_messages": ("Messages to NEVA", "neva"),
    "neva_voice": ("Voice questions to NEVA", "neva"),
    "city_guide_trips": ("City Guide trips started", "city_guides"),
    "experience_requests": ("Experience booking requests", "experiences"),
    "experience_reviews": ("Experience reviews", "experiences"),
    "stories_posted": ("Travel stories posted", "travel_stories"),
    "story_comments": ("Comments on stories", "travel_stories"),
    "journal_entries": ("Journal entries", "travel_journal"),
    "place_reviews": ("Place reviews", "place_details"),
    "forum_posts": ("Forum posts", "forum"),
}

# Screen -> (the action that shows someone who opened it went on to use it,
# how the page words it after a number: "14 sent a message").
FUNNELS = {
    "neva": ("neva_messages", "sent a message"),
    "odyssey_planner": ("odyssey_plans", "requested a plan"),
    "city_guides": ("city_guide_trips", "started a trip"),
    "experiences": ("experience_requests", "sent a booking request"),
}

# A report resent later than this is dropped rather than back-dated, the same
# rule as /auth/me/session.
MAX_REPORT_AGE = timedelta(days=7)
MAX_REPORT_ITEMS = 100


def clean_opens(items: Iterable[dict], now: datetime) -> list[dict]:
    """The opens of one report worth keeping: known features only, times no
    later than now and no older than MAX_REPORT_AGE, one per visit and feature
    (the earliest)."""
    kept: dict = {}
    for item in items:
        feature = item.get("feature")
        visit_id = item.get("visit_id")
        if feature not in FEATURES or visit_id is None:
            continue
        at = item.get("opened_at") or now
        if at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        if at < now - MAX_REPORT_AGE:
            continue
        at = min(at, now)
        key = (visit_id, feature)
        if key not in kept or at < kept[key]["opened_at"]:
            kept[key] = {"visit_id": visit_id, "feature": feature, "opened_at": at}
    return list(kept.values())


def window(today: date, days: int) -> tuple[list[date], list[date]]:
    """The last `days` days up to today, and the same number of days before."""
    current = [today - timedelta(days=i) for i in range(days - 1, -1, -1)]
    previous = [current[0] - timedelta(days=i) for i in range(days, 0, -1)]
    return current, previous


def build_report(
    days: list[date],
    prev_days: list[date],
    opens: Iterable[tuple],
    actions: Iterable[tuple],
    active: Iterable[tuple],
    signups: dict,
    firsts: dict,
) -> dict:
    """The Feature usage page's figures.

    `opens` and `actions` are (key, user_id, day, count) rows, `active` is
    (user_id, day) for each day an explorer had a long enough visit, `signups`
    maps a day to new accounts. `firsts` maps a source ("opens", "sessions",
    "signups" or an action key) to the first day it has data; days before it
    are reported as None (not counted), and a previous-period figure is only
    given when the whole previous period was counted. Rows outside both
    windows are ignored.
    """
    current, previous = set(days), set(prev_days)
    index = {d: i for i, d in enumerate(days)}

    def full_prev(source: str) -> bool:
        first = firsts.get(source)
        return first is not None and first <= prev_days[0]

    def per_day(source: str, values: list) -> list:
        first = firsts.get(source)
        return [v if first is not None and d >= first else None for d, v in zip(days, values)]

    def iso(d: Optional[date]) -> Optional[str]:
        return d.isoformat() if d else None

    # Screens, among the explorers whose app reports them.
    screens = {k: {"users": set(), "prev": set(), "opens": 0, "daily": [set() for _ in days]} for k in FEATURES}
    reporting, reporting_prev = set(), set()
    reporting_daily = [set() for _ in days]
    for key, uid, day, count in opens:
        s = screens.get(key)
        if s is None:
            continue
        if day in current:
            s["users"].add(uid)
            s["opens"] += int(count)
            s["daily"][index[day]].add(uid)
            reporting.add(uid)
            reporting_daily[index[day]].add(uid)
        elif day in previous:
            s["prev"].add(uid)
            reporting_prev.add(uid)

    acts = {k: {"count": 0, "users": set(), "prev_count": 0, "prev": set(), "daily": [set() for _ in days]} for k in ACTIONS}
    for key, uid, day, count in actions:
        a = acts.get(key)
        if a is None:
            continue
        if day in current:
            a["count"] += int(count)
            a["users"].add(uid)
            a["daily"][index[day]].add(uid)
        elif day in previous:
            a["prev_count"] += int(count)
            a["prev"].add(uid)

    active_now, active_before = set(), set()
    active_daily = [set() for _ in days]
    for uid, day in active:
        if day in current:
            active_now.add(uid)
            active_daily[index[day]].add(uid)
        elif day in previous:
            active_before.add(uid)

    screens_compare = full_prev("opens")
    screen_rows = [
        {
            "key": key,
            "label": FEATURES[key],
            "users": len(s["users"]),
            "share": round(len(s["users"]) / len(reporting), 4) if reporting else 0,
            "visits": s["opens"],
            "prev_users": len(s["prev"]) if screens_compare else None,
            "prev_share": round(len(s["prev"]) / len(reporting_prev), 4) if screens_compare and reporting_prev else None,
            "daily": per_day("opens", [len(x) for x in s["daily"]]),
        }
        for key, s in screens.items()
        if s["users"]
    ]
    screen_rows.sort(key=lambda r: (r["users"], r["visits"]), reverse=True)

    action_rows = []
    for key, a in acts.items():
        compare = full_prev(key)
        if not (a["count"] or (compare and a["prev_count"])):
            continue
        label, feature = ACTIONS[key]
        action_rows.append({
            "key": key,
            "label": label,
            "feature": feature,
            "feature_label": FEATURES[feature],
            "count": a["count"],
            "users": len(a["users"]),
            "prev_count": a["prev_count"] if compare else None,
            "prev_users": len(a["prev"]) if compare else None,
            "counted_since": iso(firsts.get(key)),
            "daily": per_day(key, [len(x) for x in a["daily"]]),
        })
    action_rows.sort(key=lambda r: (r["users"], r["count"]), reverse=True)

    funnels = []
    for feature, (action, phrase) in FUNNELS.items():
        opened = screens[feature]["users"]
        if opened:
            funnels.append({
                "feature": feature,
                "label": FEATURES[feature],
                "action": action,
                "action_label": phrase,
                "opened": len(opened),
                "acted": len(opened & acts[action]["users"]),
            })

    return {
        "days": [d.isoformat() for d in days],
        "active_explorers": len(active_now),
        "prev_active_explorers": len(active_before) if full_prev("sessions") else None,
        "active_daily": per_day("sessions", [len(x) for x in active_daily]),
        "new_signups": sum(signups.get(d, 0) for d in days),
        "prev_new_signups": sum(signups.get(d, 0) for d in prev_days) if full_prev("signups") else None,
        "reporting_explorers": len(reporting),
        "reporting_daily": per_day("opens", [len(x) for x in reporting_daily]),
        "screens_since": iso(firsts.get("opens")),
        "screens": screen_rows,
        "actions": action_rows,
        "funnels": funnels,
    }


# Explorers whose rows count: not suspended, not the official stories account.
_COUNTED_USER = "coalesce(u.is_active, true) AND u.id <> :excluded"

# Requests from our own machines (load tests, the containers) are not explorers.
_NOT_LOCAL = """NOT (e.client_ip IS NOT NULL AND (
    e.client_ip << inet '127.0.0.0/8' OR e.client_ip << inet '10.0.0.0/8'
    OR e.client_ip << inet '172.16.0.0/12' OR e.client_ip << inet '192.168.0.0/16'))"""

_ODYSSEY = "(i.items -> 0 ->> 'kind') = 'odyssey_meta'"
_MINI_TOUR = "(i.items -> 0 ->> 'kind') = 'mini_tour_meta'"
_JOURNAL = "coalesce(s.is_journal, false)"

_OPENS_SQL = f"""
    SELECT o.feature, o.user_id, (o.opened_at AT TIME ZONE :tz)::date AS day, count(*) AS n
    FROM feature_opens o JOIN users u ON u.id = o.user_id
    WHERE o.opened_at >= :since AND {_COUNTED_USER}
    GROUP BY 1, 2, 3
"""

_ACTIONS_SQL = f"""
    SELECT a.key, a.user_id, a.day, sum(a.n) AS n FROM (
        SELECT CASE WHEN {_ODYSSEY} THEN 'odyssey_plans' ELSE 'mini_tours' END AS key,
               i.user_id, (i.created_at AT TIME ZONE :tz)::date AS day, count(*) AS n
        FROM itineraries i
        WHERE i.created_at >= :since AND ({_ODYSSEY} OR {_MINI_TOUR})
        GROUP BY 1, 2, 3
      UNION ALL
        SELECT 'discover_runs', d.user_id, (d.created_at AT TIME ZONE :tz)::date, count(*)
        FROM discovery_histories d WHERE d.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT CASE WHEN e.route = '/api/v1/neva/chat' THEN 'neva_messages' ELSE 'neva_voice' END,
               e.user_id, (e.ts AT TIME ZONE :tz)::date, count(DISTINCT e.request_id)
        FROM api_events e
        WHERE e.ts >= :since AND e.route IN ('/api/v1/neva/chat', '/api/v1/neva/voice')
          AND e.user_id IS NOT NULL AND e.ingest = 'live' AND {_NOT_LOCAL}
        GROUP BY 1, 2, 3
      UNION ALL
        SELECT 'city_guide_trips', t.user_id, (t.started_at AT TIME ZONE :tz)::date, count(*)
        FROM city_tour_trips t WHERE t.started_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT 'experience_requests', q.user_id, (q.created_at AT TIME ZONE :tz)::date, count(*)
        FROM experience_enquiries q WHERE q.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT 'experience_reviews', r.user_id, (r.created_at AT TIME ZONE :tz)::date, count(*)
        FROM experience_reviews r WHERE r.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT CASE WHEN {_JOURNAL} THEN 'journal_entries' ELSE 'stories_posted' END,
               s.user_id, (s.created_at AT TIME ZONE :tz)::date, count(*)
        FROM travel_stories s
        WHERE s.created_at >= :since AND NOT coalesce(s.is_official, false)
        GROUP BY 1, 2, 3
      UNION ALL
        SELECT 'story_comments', c.user_id, (c.created_at AT TIME ZONE :tz)::date, count(*)
        FROM travel_story_comments c WHERE c.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT 'place_reviews', r.user_id, (r.created_at AT TIME ZONE :tz)::date, count(*)
        FROM reviews r WHERE r.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT 'forum_posts', t.user_id, (t.created_at AT TIME ZONE :tz)::date, count(*)
        FROM forum_topics t WHERE t.created_at >= :since
        GROUP BY 2, 3
      UNION ALL
        SELECT 'forum_posts', p.user_id, (p.created_at AT TIME ZONE :tz)::date, count(*)
        FROM forum_posts p WHERE p.created_at >= :since AND NOT coalesce(p.is_ai_generated, false)
        GROUP BY 2, 3
    ) a
    JOIN users u ON u.id = a.user_id
    WHERE {_COUNTED_USER}
    GROUP BY 1, 2, 3
"""

# The first moment each source has data, over all time. NEVA messages are only
# recorded under their own route since 1 Oct 2026, screens since the app update.
_FIRSTS_SQL = f"""
    SELECT key, (first AT TIME ZONE :tz)::date AS day FROM (
        SELECT 'odyssey_plans' AS key, min(i.created_at) AS first FROM itineraries i WHERE {_ODYSSEY}
        UNION ALL SELECT 'mini_tours', min(i.created_at) FROM itineraries i WHERE {_MINI_TOUR}
        UNION ALL SELECT 'discover_runs', min(created_at) FROM discovery_histories
        UNION ALL SELECT 'neva_messages', min(ts) FROM api_events WHERE route = '/api/v1/neva/chat'
        UNION ALL SELECT 'neva_voice', min(ts) FROM api_events WHERE route = '/api/v1/neva/voice'
        UNION ALL SELECT 'city_guide_trips', min(started_at) FROM city_tour_trips
        UNION ALL SELECT 'experience_requests', min(created_at) FROM experience_enquiries
        UNION ALL SELECT 'experience_reviews', min(created_at) FROM experience_reviews
        UNION ALL SELECT 'stories_posted', min(s.created_at) FROM travel_stories s WHERE NOT {_JOURNAL}
        UNION ALL SELECT 'journal_entries', min(s.created_at) FROM travel_stories s WHERE {_JOURNAL}
        UNION ALL SELECT 'story_comments', min(created_at) FROM travel_story_comments
        UNION ALL SELECT 'place_reviews', min(created_at) FROM reviews
        UNION ALL SELECT 'forum_posts', least((SELECT min(created_at) FROM forum_topics),
                                              (SELECT min(created_at) FROM forum_posts))
        UNION ALL SELECT 'sessions', min(created_at) FROM user_sessions
        UNION ALL SELECT 'signups', min(created_at) FROM users
        UNION ALL SELECT 'opens', min(opened_at) FROM feature_opens
    ) f WHERE first IS NOT NULL
"""

# The same rule as the Users page: a day counts when one visit lasted long enough.
_ACTIVE_SQL = f"""
    SELECT s.user_id, (s.created_at AT TIME ZONE :tz)::date AS day
    FROM user_sessions s JOIN users u ON u.id = s.user_id
    WHERE s.created_at >= :since AND {_COUNTED_USER}
    GROUP BY 1, 2
    HAVING max(s.duration_seconds) >= :min_visit
"""

_SIGNUPS_SQL = f"""
    SELECT (u.created_at AT TIME ZONE :tz)::date AS day, count(*) AS n
    FROM users u WHERE u.created_at >= :since AND {_COUNTED_USER}
    GROUP BY 1
"""


async def report(db, days: int, *, tz_name: str, min_visit_seconds: int, excluded_user_id) -> dict:
    """The page's figures for the last `days` Sri Lanka days."""
    tz = ZoneInfo(tz_name)
    today = datetime.now(tz).date()
    current, previous = window(today, days)
    params = {
        "tz": tz_name,
        "since": datetime.combine(previous[0], time.min, tzinfo=tz),
        "excluded": excluded_user_id,
    }

    opens = (await db.execute(text(_OPENS_SQL), params)).all()
    actions = (await db.execute(text(_ACTIONS_SQL), params)).all()
    active = (await db.execute(text(_ACTIVE_SQL), {**params, "min_visit": min_visit_seconds})).all()
    signups = {r.day: int(r.n) for r in (await db.execute(text(_SIGNUPS_SQL), params)).all()}
    firsts = {r.key: r.day for r in (await db.execute(text(_FIRSTS_SQL), {"tz": tz_name})).all()}

    result = build_report(current, previous, opens, actions, active, signups, firsts)
    result["min_visit_seconds"] = min_visit_seconds
    result["generated_at"] = datetime.now(timezone.utc).isoformat()
    return result
