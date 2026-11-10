"""Subscription plans: who is on which plan, what it allows, what is used.

Explorer (free), Voyager and Globetrotter, as finalised in
`Nexaround_Subscription_Packages.docx` (2026-11-10). Every limit is enforced
here, on the server — the app only displays what `/billing/plan` reports.

Nothing is limited until `plans_enforce` is switched on (Admin › Settings), so
the code can ship ahead of the app release that lets people buy a plan. Before
that, `plans_enforce_users` (comma-separated emails) applies the limits to
named test accounts only.

Limit numbers can be changed without a release: the `plan_limits` setting is a
JSON object merged over DEFAULT_LIMITS, e.g. {"explorer": {"neva_per_day": 30}}.
"""
from __future__ import annotations

import calendar
import json
import logging
import time
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Iterable, Optional

logger = logging.getLogger(__name__)

EXPLORER, VOYAGER, GLOBETROTTER = "explorer", "voyager", "globetrotter"
PLAN_RANK = {EXPLORER: 0, VOYAGER: 1, GLOBETROTTER: 2}
PLAN_NAMES = {EXPLORER: "Explorer", VOYAGER: "Voyager", GLOBETROTTER: "Globetrotter"}

# Safety first: hospitals and clinics are never range-limited, on any plan.
UNCAPPED_CATEGORIES = {"Medical", "Hospital"}

DEFAULT_LIMITS: dict[str, dict] = {
    EXPLORER: {
        "odyssey_per_period": 1,
        "odyssey_max_days": 5,
        "odyssey_lite": True,          # ratings and opening hours hidden
        "neva_per_day": 20,
        "ar_radius_m": 2000,
        "nearby_max_radius_m": 25000,  # Around You / Discover: nearest 2 bands
        "banded_max_bands": 2,
        "map_day_usd": 0.15,           # live map data limit
        "map_month_usd": 0.50,
        "priority_queue": False,
    },
    VOYAGER: {
        "odyssey_per_period": 8,
        "odyssey_max_days": 10,
        "odyssey_lite": False,
        "neva_per_day": 100,
        "ar_radius_m": 10000,
        "nearby_max_radius_m": 50000,
        "banded_max_bands": 3,
        "map_day_usd": 0,
        "map_month_usd": 2.00,
        "priority_queue": False,
    },
    GLOBETROTTER: {
        "odyssey_per_period": 15,
        "odyssey_max_days": 14,
        "odyssey_lite": False,
        "neva_per_day": 300,
        "ar_radius_m": 10000,
        "nearby_max_radius_m": 50000,
        "banded_max_bands": 3,
        "map_day_usd": 0,
        "map_month_usd": 4.00,
        "priority_queue": True,
    },
}

K_ENFORCE = "plans_enforce"
K_ENFORCE_USERS = "plans_enforce_users"
K_LIMITS = "plan_limits"
K_MIN_APP_VERSION = "min_app_version"

_CONFIG_TTL = 60.0
_PLAN_CACHE_TTL = 60
_TRUE = ("1", "true", "yes", "on")


class PlanLimitExceeded(Exception):
    """A plan limit stops this request. Rendered as HTTP 429 by main.py.

    `message` is written for people on an old app build, which shows the
    server's text as-is and has no plans screen yet.
    """

    def __init__(self, feature: str, message: str, *, plan: str = EXPLORER,
                 limit: Optional[int] = None, resets_at: Optional[datetime] = None):
        super().__init__(message)
        self.feature = feature
        self.message = message
        self.plan = plan
        self.limit = limit
        self.resets_at = resets_at

    def body(self) -> dict:
        return {
            "detail": self.message,
            "code": "plan_limit",
            "feature": self.feature,
            "plan": self.plan,
            "limit": self.limit,
            "resets_at": self.resets_at.isoformat() if self.resets_at else None,
        }


@dataclass
class PlanInfo:
    plan: str = EXPLORER
    period: Optional[str] = None
    store: Optional[str] = None
    status: Optional[str] = None
    source: Optional[str] = None
    period_start: Optional[datetime] = None
    period_end: Optional[datetime] = None
    auto_renew: bool = False

    def to_json(self) -> str:
        d = asdict(self)
        for k in ("period_start", "period_end"):
            if d[k] is not None:
                d[k] = d[k].isoformat()
        return json.dumps(d)

    @classmethod
    def from_json(cls, raw: str) -> "PlanInfo":
        d = json.loads(raw)
        for k in ("period_start", "period_end"):
            if d.get(k):
                d[k] = datetime.fromisoformat(d[k])
        return cls(**d)


# ── Pure rules (unit-tested) ────────────────────────────────────────────────

def merge_limits(overrides: Optional[dict]) -> dict[str, dict]:
    """DEFAULT_LIMITS with the admin's `plan_limits` JSON laid over it.
    Unknown plans and keys are ignored, so a typo cannot invent a limit."""
    merged = {p: dict(v) for p, v in DEFAULT_LIMITS.items()}
    for plan, values in (overrides or {}).items():
        if plan in merged and isinstance(values, dict):
            for k, v in values.items():
                if k in merged[plan]:
                    merged[plan][k] = v
    return merged


def best_plan(rows: Iterable, now: Optional[datetime] = None) -> PlanInfo:
    """The highest plan among the user's still-valid subscription rows."""
    now = now or datetime.now(timezone.utc)
    far = datetime.max.replace(tzinfo=timezone.utc)
    live = [
        r for r in rows
        if getattr(r, "plan", None) in PLAN_RANK
        and (r.period_end is None or r.period_end > now)
    ]
    if not live:
        return PlanInfo()
    r = max(live, key=lambda r: (PLAN_RANK[r.plan], r.period_end or far))
    return PlanInfo(
        plan=r.plan, period=r.period, store=r.store, status=r.status,
        source=r.source, period_start=r.period_start, period_end=r.period_end,
        auto_renew=bool(r.auto_renew),
    )


def _add_months(dt: datetime, months: int) -> datetime:
    y, m = divmod(dt.month - 1 + months, 12)
    year, month = dt.year + y, m + 1
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


def odyssey_window(info: PlanInfo, now: Optional[datetime] = None) -> tuple[datetime, datetime]:
    """[start, reset) of the current Odyssey allowance.

    Explorer: the calendar month (UTC). Paid: monthly cycles anchored on the
    purchase date — a yearly plan gets the same monthly allowance, renewing on
    the same day each month.
    """
    now = now or datetime.now(timezone.utc)
    anchor = info.period_start if info.plan != EXPLORER else None
    if anchor is None or anchor > now:
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        return start, _add_months(start, 1)
    # Counted from the anchor each time, so a plan bought on the 31st renews
    # on the 28th in February and on the 31st again in March.
    k = (now.year - anchor.year) * 12 + (now.month - anchor.month)
    if _add_months(anchor, k) > now:
        k -= 1
    return _add_months(anchor, k), _add_months(anchor, k + 1)


def day_window(now: Optional[datetime] = None) -> tuple[datetime, datetime]:
    """Neva's day: 00:00 UTC to 00:00 UTC."""
    now = now or datetime.now(timezone.utc)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return start, start + timedelta(days=1)


def radius_cap(limits: dict, category: Optional[str], ctx: Optional[str]) -> Optional[int]:
    """Largest radius this plan may search, or None for no cap."""
    if category in UNCAPPED_CATEGORIES:
        return None
    if ctx == "ar":
        return int(limits["ar_radius_m"])
    return int(limits["nearby_max_radius_m"])


# ── Config ──────────────────────────────────────────────────────────────────

_config: dict = {}
_config_at = 0.0


async def _load_config(force: bool = False) -> dict:
    """Settings, re-read every minute: the API runs two worker processes and
    the admin's edit only lands in one of them directly."""
    global _config, _config_at
    now = time.time()
    if not force and _config and (now - _config_at) < _CONFIG_TTL:
        return _config
    try:
        from sqlalchemy import func, select
        from app.core.database import async_session
        from app.models.user import User
        from app.services.settings_service import SettingsService

        async with async_session() as db:
            svc = SettingsService(db)
            await svc.load_settings()
            enforce = (await svc.get_setting(K_ENFORCE) or "false").strip().lower() in _TRUE
            try:
                overrides = json.loads(await svc.get_setting(K_LIMITS) or "{}")
            except ValueError:
                logger.warning("plan_limits setting is not valid JSON; using defaults")
                overrides = {}
            emails = [
                e.strip().lower()
                for e in (await svc.get_setting(K_ENFORCE_USERS) or "").split(",")
                if e.strip()
            ]
            test_ids: set[str] = set()
            if emails:
                rows = await db.execute(
                    select(User.id).where(func.lower(User.email).in_(emails))
                )
                test_ids = {str(r[0]) for r in rows.all()}
            _config = {
                "enforce": enforce,
                "test_ids": test_ids,
                "limits": merge_limits(overrides),
                "min_app_version": (await svc.get_setting(K_MIN_APP_VERSION) or "").strip(),
            }
            _config_at = now
    except Exception as e:
        logger.warning("plan_service: could not load config: %s", e)
        _config = _config or {
            "enforce": False, "test_ids": set(),
            "limits": merge_limits(None), "min_app_version": "",
        }
    return _config


async def refresh_config() -> dict:
    return await _load_config(force=True)


async def limits_for(plan: str) -> dict:
    cfg = await _load_config()
    return cfg["limits"].get(plan) or cfg["limits"][EXPLORER]


async def enforced_for(user_id) -> bool:
    if not user_id:
        return False
    cfg = await _load_config()
    return cfg["enforce"] or str(user_id) in cfg["test_ids"]


async def min_app_version() -> str:
    return (await _load_config())["min_app_version"]


async def is_enforcing() -> bool:
    return (await _load_config())["enforce"]


# ── Plan lookup ─────────────────────────────────────────────────────────────

def _redis():
    from app.services import telemetry
    return telemetry._get_redis()


def _ns() -> str:
    from app.services import telemetry
    return telemetry._NS


def _plan_key(user_id) -> str:
    return f"plans:{_ns()}:user:{user_id}"


async def get_plan(user_id) -> PlanInfo:
    """The user's current plan; Explorer when they have none. Cached a minute,
    and the cache is dropped whenever a webhook or admin changes the plan."""
    if not user_id:
        return PlanInfo()
    try:
        raw = await _redis().get(_plan_key(user_id))
        if raw:
            return PlanInfo.from_json(raw)
    except Exception:
        pass
    from sqlalchemy import select
    from app.core.database import async_session
    from app.models.subscription import Subscription
    try:
        async with async_session() as db:
            rows = (await db.execute(
                select(Subscription).where(Subscription.user_id == user_id)
            )).scalars().all()
        info = best_plan(rows)
    except Exception as e:
        logger.warning("plan_service: plan lookup failed for %s: %s", user_id, e)
        return PlanInfo()
    try:
        await _redis().set(_plan_key(user_id), info.to_json(), ex=_PLAN_CACHE_TTL)
    except Exception:
        pass
    return info


async def invalidate(user_id) -> None:
    try:
        await _redis().delete(_plan_key(user_id))
    except Exception:
        pass


# ── Odyssey ─────────────────────────────────────────────────────────────────

async def odyssey_used(user_id, start: datetime) -> int:
    """Odyssey plans made since `start`. One itinerary is one plan however
    many times it is retried; a plan that failed on our side does not count."""
    from sqlalchemy import text
    from app.core.database import async_session
    async with async_session() as db:
        n = (await db.execute(text(
            "SELECT count(*) FROM itineraries "
            "WHERE user_id = :uid AND created_at >= :start AND status <> 'failed' "
            "AND CAST(items AS jsonb) @> CAST(:meta AS jsonb)"
        ), {"uid": user_id, "start": start,
            "meta": json.dumps([{"kind": "odyssey_meta"}])})).scalar()
    return int(n or 0)


@dataclass
class OdysseyGrant:
    lite: bool = False
    priority: bool = False


async def check_odyssey(user_id, days: int, *, new_plan: bool = True) -> OdysseyGrant:
    """Allow or refuse one Odyssey generation. `new_plan=False` is a retry of
    an itinerary that already counts, which only needs the day check."""
    info = await get_plan(user_id)
    limits = await limits_for(info.plan)
    grant = OdysseyGrant(lite=bool(limits["odyssey_lite"]),
                         priority=bool(limits["priority_queue"]))
    if not await enforced_for(user_id):
        return OdysseyGrant()
    max_days = int(limits["odyssey_max_days"])
    if days > max_days:
        raise PlanLimitExceeded(
            "odyssey_days",
            f"Trips longer than {max_days} days need a bigger plan. "
            "Please update the app to see the plans.",
            plan=info.plan, limit=max_days,
        )
    if new_plan:
        start, resets = odyssey_window(info)
        allowed = int(limits["odyssey_per_period"])
        if await odyssey_used(user_id, start) >= allowed:
            noun = "plan" if allowed == 1 else "plans"
            raise PlanLimitExceeded(
                "odyssey",
                f"You have used your {allowed} Odyssey {noun} for this month. "
                "Please update the app to choose a plan with more.",
                plan=info.plan, limit=allowed, resets_at=resets,
            )
    return grant


# ── Neva ────────────────────────────────────────────────────────────────────

def _neva_key(user_id, now: Optional[datetime] = None) -> str:
    now = now or datetime.now(timezone.utc)
    return f"plans:{_ns()}:neva:{user_id}:{now.strftime('%Y%m%d')}"


async def neva_used(user_id) -> int:
    try:
        return int(await _redis().get(_neva_key(user_id)) or 0)
    except Exception:
        return 0


async def check_neva(user_id) -> None:
    if not await enforced_for(user_id):
        return
    info = await get_plan(user_id)
    allowed = int((await limits_for(info.plan))["neva_per_day"])
    if await neva_used(user_id) >= allowed:
        _, resets = day_window()
        raise PlanLimitExceeded(
            "neva",
            f"You have used today's {allowed} Neva messages. They reset at "
            "midnight UTC, or update the app to choose a plan with more.",
            plan=info.plan, limit=allowed, resets_at=resets,
        )


async def count_neva(user_id) -> None:
    """Called after a reply is delivered: a failed reply is not a message."""
    try:
        r = _redis()
        key = _neva_key(user_id)
        await r.incr(key)
        await r.expire(key, 2 * 86400)
    except Exception:
        pass


# ── Map data ────────────────────────────────────────────────────────────────

async def radius_cap_for(user_id, category: Optional[str], ctx: Optional[str]) -> Optional[int]:
    if not await enforced_for(user_id):
        return None
    info = await get_plan(user_id)
    return radius_cap(await limits_for(info.plan), category, ctx)


async def max_bands_for(user_id, category: Optional[str]) -> Optional[int]:
    if category in UNCAPPED_CATEGORIES or not await enforced_for(user_id):
        return None
    info = await get_plan(user_id)
    n = int((await limits_for(info.plan))["banded_max_bands"])
    return n if n < 3 else None


async def map_caps(user_id) -> tuple[float, float]:
    """(daily, monthly) live-map spending caps in USD; 0 means no cap."""
    if not await enforced_for(user_id):
        return 0.0, 0.0
    info = await get_plan(user_id)
    limits = await limits_for(info.plan)
    return float(limits["map_day_usd"] or 0), float(limits["map_month_usd"] or 0)


# ── What the app shows ──────────────────────────────────────────────────────

async def plan_summary(user_id) -> dict:
    """Everything the app's plan screen and counters need, in one answer."""
    from app.services import spend_guard

    info = await get_plan(user_id)
    cfg = await _load_config()
    limits = cfg["limits"][info.plan]
    enforced = await enforced_for(user_id)
    now = datetime.now(timezone.utc)

    o_start, o_reset = odyssey_window(info, now)
    try:
        o_used = await odyssey_used(user_id, o_start)
    except Exception:
        o_used = 0
    n_used = await neva_used(user_id)
    _, n_reset = day_window(now)
    day_cap, month_cap = float(limits["map_day_usd"] or 0), float(limits["map_month_usd"] or 0)
    d_spent, m_spent = await spend_guard.user_map_spend(user_id)
    map_limited = enforced and (
        (day_cap and d_spent >= day_cap) or (month_cap and m_spent >= month_cap)
    )

    return {
        "plan": info.plan,
        "plan_name": PLAN_NAMES[info.plan],
        "period": info.period,
        "store": info.store,
        "status": info.status,
        "source": info.source,
        "period_end": info.period_end.isoformat() if info.period_end else None,
        "auto_renew": info.auto_renew,
        "enforced": enforced,
        "limits": limits,
        "usage": {
            "odyssey_used": o_used,
            "odyssey_left": max(0, int(limits["odyssey_per_period"]) - o_used),
            "odyssey_resets_at": o_reset.isoformat(),
            "neva_used": n_used,
            "neva_left": max(0, int(limits["neva_per_day"]) - n_used),
            "neva_resets_at": n_reset.isoformat(),
            "map_limited": bool(map_limited),
        },
        # Every plan's limits, so the plans screen renders from the server and
        # a limit the TL changes in the admin panel shows without a release.
        "catalog": [
            {"plan": p, "plan_name": PLAN_NAMES[p], "limits": cfg["limits"][p]}
            for p in (EXPLORER, VOYAGER, GLOBETROTTER)
        ],
    }
