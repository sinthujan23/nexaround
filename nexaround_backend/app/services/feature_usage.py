"""What explorers use in the app: the admin's Feature usage page.

Everything is counted as unique explorers per Sri Lanka day, from two sources:

- Feature opens (`feature_opens`): screens the app saw on screen for a few
  seconds with the app in the foreground. Only builds from November 2026
  report them, so they start empty and fill in as explorers update.
- Actions: things explorers finished that are saved anyway, such as an Odyssey
  plan requested, a Discover search, a NEVA message, a City Guide trip started,
  an experience request or a story posted. These go back to the start of each
  table.

API requests are deliberately not a source. The app loads data in the
background (the hidden AR tab, the home map), and Experiences, City Guides,
Stories and Museums leave no row in api_events at all, so request counts both
overstate and miss real use.
"""
from datetime import date, datetime, time, timedelta, timezone
from typing import Iterable, Optional
from zoneinfo import ZoneInfo

from sqlalchemy import text

# The features the app may report, key -> label. Anything else is dropped.
FEATURES = {
    "home": "Home",
    "ar": "AR camera",
    "neva": "NEVA assistant",
    "discover": "Discover",
    "plans": "My plans",
    "odyssey_planner": "Odyssey planner",
    "mini_tour": "Mini tours",
    "city_guides": "City Guides",
    "experiences": "Experiences",
    "museums": "Museums",
    "travel_stories": "Travel Stories",
    "travel_journal": "Travel journal",
    "forum": "Forum",
    "place_details": "Place details",
    "full_map": "Full map",
    "directions": "Directions",
    "profile": "Profile",
    "subscription_plans": "Subscription plans",
}

# Saved actions, key -> (label, the feature it belongs to).
ACTIONS = {
    "odyssey_plans": ("Odyssey plans requested", "odyssey_planner"),
    "mini_tours": ("Mini tours made", "mini_tour"),
    "discover_runs": ("Discover searches", "discover"),
    "neva_messages": ("NEVA chat messages", "neva"),
    "neva_voice": ("NEVA voice questions", "neva"),
    "city_guide_trips": ("City Guide trips started", "city_guides"),
    "experience_requests": ("Experience requests sent", "experiences"),
    "experience_reviews": ("Experience reviews", "experiences"),
    "stories_posted": ("Travel stories posted", "travel_stories"),
    "story_comments": ("Story comments", "travel_stories"),
    "journal_entries": ("Journal entries", "travel_journal"),
    "place_reviews": ("Place reviews", "place_details"),
    "forum_posts": ("Forum posts", "forum"),
}

# Feature -> (the action that shows an explorer who opened it went on to use
# it, how the page words it after a number: "14 sent a message").
FUNNELS = {
    "neva": ("neva_messages", "sent a message"),
    "discover": ("discover_runs", "ran a search"),
    "odyssey_planner": ("odyssey_plans", "requested a plan"),
    "city_guides": ("city_guide_trips", "started a trip"),
    "experiences": ("experience_requests", "sent a request"),
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
    opens_since: Optional[date],
) -> dict:
    """The Feature usage page's figures.

    `opens` and `actions` are (key, user_id, day, count) rows, `active` is
    (user_id, day) for each day an explorer had a long enough visit, `signups`
    maps a day to new accounts. Rows outside both windows are ignored.
    """
    current, previous = set(days), set(prev_days)
    index = {d: i for i, d in enumerate(days)}

    feats = {
        key: {
            "users": set(), "prev_users": set(), "open_users": set(), "opens": 0,
            "action_users": set(), "daily": [set() for _ in days],
        }
        for key in FEATURES
    }
    acts = {
        key: {"count": 0, "users": set(), "prev_count": 0, "prev_users": set(), "daily": [0] * len(days)}
        for key in ACTIONS
    }
    explorers: set = set()
    reporting: set = set()

    for key, uid, day, count in opens:
        f = feats.get(key)
        if f is None:
            continue
        if day in current:
            f["users"].add(uid)
            f["open_users"].add(uid)
            f["opens"] += int(count)
            f["daily"][index[day]].add(uid)
            explorers.add(uid)
            reporting.add(uid)
        elif day in previous:
            f["prev_users"].add(uid)

    for key, uid, day, count in actions:
        a = acts.get(key)
        if a is None:
            continue
        f = feats[ACTIONS[key][1]]
        if day in current:
            a["count"] += int(count)
            a["users"].add(uid)
            a["daily"][index[day]] += int(count)
            f["users"].add(uid)
            f["action_users"].add(uid)
            f["daily"][index[day]].add(uid)
            explorers.add(uid)
        elif day in previous:
            a["prev_count"] += int(count)
            a["prev_users"].add(uid)
            f["prev_users"].add(uid)

    active_now: set = set()
    active_before: set = set()
    active_daily = [set() for _ in days]
    for uid, day in active:
        if day in current:
            active_now.add(uid)
            active_daily[index[day]].add(uid)
        elif day in previous:
            active_before.add(uid)
    explorers |= active_now

    total = len(explorers)
    features = [
        {
            "key": key,
            "label": FEATURES[key],
            "users": len(f["users"]),
            "prev_users": len(f["prev_users"]),
            "share": round(len(f["users"]) / total, 4) if total else 0,
            "open_users": len(f["open_users"]),
            "opens": f["opens"],
            "action_users": len(f["action_users"]),
            "daily": [len(s) for s in f["daily"]],
        }
        for key, f in feats.items()
        if f["users"] or f["prev_users"]
    ]
    features.sort(key=lambda f: (f["users"], f["opens"], f["prev_users"]), reverse=True)

    funnels = []
    for feature, (action, phrase) in FUNNELS.items():
        opened = feats[feature]["open_users"]
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
        "explorers": total,
        "active_explorers": len(active_now),
        "prev_active_explorers": len(active_before),
        "active_daily": [len(s) for s in active_daily],
        "new_signups": sum(signups.get(d, 0) for d in days),
        "prev_new_signups": sum(signups.get(d, 0) for d in prev_days),
        "reporting_explorers": len(reporting),
        "opens_since": opens_since.isoformat() if opens_since else None,
        "features": features,
        "actions": [
            {
                "key": key,
                "label": ACTIONS[key][0],
                "feature": ACTIONS[key][1],
                "count": a["count"],
                "users": len(a["users"]),
                "prev_count": a["prev_count"],
                "prev_users": len(a["prev_users"]),
                "daily": a["daily"],
            }
            for key, a in acts.items()
        ],
        "funnels": funnels,
    }


# Explorers whose rows count: not suspended, not the official stories account.
_COUNTED_USER = "coalesce(u.is_active, true) AND u.id <> :excluded"

# Requests from our own machines (load tests, the containers) are not explorers.
_NOT_LOCAL = """NOT (e.client_ip IS NOT NULL AND (
    e.client_ip << inet '127.0.0.0/8' OR e.client_ip << inet '10.0.0.0/8'
    OR e.client_ip << inet '172.16.0.0/12' OR e.client_ip << inet '192.168.0.0/16'))"""

_OPENS_SQL = f"""
    SELECT o.feature, o.user_id, (o.opened_at AT TIME ZONE :tz)::date AS day, count(*) AS n
    FROM feature_opens o JOIN users u ON u.id = o.user_id
    WHERE o.opened_at >= :since AND {_COUNTED_USER}
    GROUP BY 1, 2, 3
"""

_ACTIONS_SQL = f"""
    SELECT a.key, a.user_id, a.day, sum(a.n) AS n FROM (
        SELECT CASE WHEN (i.items -> 0 ->> 'kind') = 'odyssey_meta' THEN 'odyssey_plans' ELSE 'mini_tours' END AS key,
               i.user_id, (i.created_at AT TIME ZONE :tz)::date AS day, count(*) AS n
        FROM itineraries i
        WHERE i.created_at >= :since AND (i.items -> 0 ->> 'kind') IN ('odyssey_meta', 'mini_tour_meta')
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
        SELECT CASE WHEN coalesce(s.is_journal, false) THEN 'journal_entries' ELSE 'stories_posted' END,
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
    first_open = await db.scalar(text("SELECT min(opened_at) FROM feature_opens"))

    result = build_report(
        current, previous, opens, actions, active, signups,
        first_open.astimezone(tz).date() if first_open else None,
    )
    result["min_visit_seconds"] = min_visit_seconds
    result["generated_at"] = datetime.now(timezone.utc).isoformat()
    return result
