"""Budget and quota enforcement for paid provider calls.

Detection is not the point — prevention is. A dashboard that shows you spent
too much is a report; this module is the control that stops it.

Two limits, both soft by design:

  * a monthly cost ceiling for the whole platform
  * a daily cost ceiling per user

Breaching either does not fail the request. It degrades it: the caller is told
to serve whatever it already has — a cached list, a PostGIS result, an empty
set — rather than buying more. A runaway client should get worse results, not a
bigger invoice, and a real user should never see an error because somebody
else's loop misbehaved.

Both limits read the real-time Redis counters that `telemetry._emit` maintains,
not the hourly rollup. The rollup lags by up to five minutes, and five minutes
is long enough for a loop to spend real money.
"""
import logging
import time
from datetime import datetime, timezone
from typing import Optional

from app.core.config import settings

logger = logging.getLogger(__name__)

# Settings keys, editable from the admin panel.
K_MONTHLY_BUDGET = "api_monthly_budget_usd"
K_USER_DAILY_CAP = "api_user_daily_cap_usd"
K_ENFORCE = "api_budget_enforce"

# Limits are re-read from the database at most this often. Without the cache a
# per-request budget check would put a settings query in front of every paid
# call — precisely the pattern this project exists to remove.
_CONFIG_TTL = 60.0
_config: dict = {}
_config_at: float = 0.0

# Counters for observability: how often did the guard actually stop something.
_stats = {"budget_blocks": 0, "quota_blocks": 0, "checks": 0}


class SpendBlocked(Exception):
    """Raised when a paid call would exceed a limit.

    Carries `reason` so the caller can decide how to degrade, and so the
    response can say something truer than 'error'.
    """

    def __init__(self, reason: str, detail: str):
        super().__init__(detail)
        self.reason = reason
        self.detail = detail


def get_stats() -> dict:
    return dict(_stats)


async def _load_config(force: bool = False) -> dict:
    global _config, _config_at
    now = time.time()
    if not force and _config and (now - _config_at) < _CONFIG_TTL:
        return _config
    try:
        from app.core.database import async_session
        from app.services.settings_service import SettingsService
        async with async_session() as db:
            svc = SettingsService(db)
            await svc.load_settings()
            _config = {
                "monthly_budget": float(await svc.get_setting(K_MONTHLY_BUDGET) or 0),
                "user_daily_cap": float(await svc.get_setting(K_USER_DAILY_CAP) or 0),
                # Off by default. Enabling a spend cap is a deliberate act, not
                # something that starts happening because the code shipped.
                "enforce": (await svc.get_setting(K_ENFORCE) or "false").lower()
                           in ("1", "true", "yes", "on"),
            }
            _config_at = now
    except Exception as e:
        logger.warning("spend_guard: could not load config: %s", e)
        _config = _config or {"monthly_budget": 0, "user_daily_cap": 0, "enforce": False}
    return _config


async def refresh_config() -> dict:
    """Force a reload after the admin edits a limit."""
    return await _load_config(force=True)


async def _redis():
    from app.services import telemetry
    return telemetry._get_redis()


async def _read_float(key: str) -> float:
    try:
        client = await _redis()
        val = await client.get(key)
        return float(val) if val else 0.0
    except Exception:
        # Redis unreachable: report zero spend. Failing open is deliberate —
        # a metrics outage must not take the product down with it.
        return 0.0


async def month_to_date_usd() -> float:
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    return await _read_float(f"spend:month:{month}")


async def today_usd() -> float:
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return await _read_float(f"spend:day:{day}")


async def user_today_usd(user_id) -> float:
    if not user_id:
        return 0.0
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return await _read_float(f"spend:user:{user_id}:{day}")


async def status() -> dict:
    """Current spend against the configured limits — for the dashboard banner."""
    cfg = await _load_config()
    mtd = await month_to_date_usd()
    budget = cfg["monthly_budget"]
    return {
        "enforcing": cfg["enforce"],
        "monthly_budget_usd": budget,
        "month_to_date_usd": round(mtd, 4),
        "pct_consumed": round(100.0 * mtd / budget, 1) if budget else None,
        "over_budget": bool(budget and mtd >= budget),
        "user_daily_cap_usd": cfg["user_daily_cap"],
        "today_usd": round(await today_usd(), 4),
        **_stats,
    }


async def check(user_id=None) -> None:
    """Raise SpendBlocked if this call should not be paid for.

    Call this immediately before a billable provider request. It is a no-op
    unless enforcement is switched on and a limit is actually configured.
    """
    _stats["checks"] += 1
    cfg = await _load_config()
    if not cfg["enforce"]:
        return

    budget = cfg["monthly_budget"]
    if budget:
        mtd = await month_to_date_usd()
        if mtd >= budget:
            _stats["budget_blocks"] += 1
            raise SpendBlocked(
                "monthly_budget",
                f"Monthly API budget reached (${mtd:.2f} of ${budget:.2f}). "
                f"Serving cached results only.",
            )

    cap = cfg["user_daily_cap"]
    if cap and user_id:
        spent = await user_today_usd(user_id)
        if spent >= cap:
            _stats["quota_blocks"] += 1
            raise SpendBlocked(
                "user_daily_cap",
                f"Daily API quota reached for this account "
                f"(${spent:.2f} of ${cap:.2f}). Serving cached results only.",
            )


async def allowed(user_id=None) -> tuple[bool, Optional[str]]:
    """Non-raising form, for call sites that would rather branch than catch."""
    try:
        await check(user_id)
        return True, None
    except SpendBlocked as e:
        return False, e.detail
