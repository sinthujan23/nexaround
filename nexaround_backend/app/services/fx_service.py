"""Daily currency exchange rates: fetch, store, serve, monitor.

ExchangeRate-API publishes new rates once a day. The worker fetches USD rates
shortly after each publish (about 30 requests a month against the free plan's
1,500), stores them in `fx_rates`, and everything else reads that row: the
app through `GET /api/v1/fx/rates`, Odyssey through `cached_usd_rates()`.

The key lives in Admin > Settings (`exchangerate_api_key`). With no key the
keyless open endpoint is used instead, which works but asks for attribution.
"""
from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session
from app.models.fx_rate import FxRate
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

BASE = "USD"
KEY_SETTING = "exchangerate_api_key"
KEYED_SOURCE = "exchangerate-api"
OPEN_SOURCE = "open-er-api"
_KEYED_URL = "https://v6.exchangerate-api.com/v6/{key}/latest/USD"
_QUOTA_URL = "https://v6.exchangerate-api.com/v6/{key}/quota"
_OPEN_URL = "https://open.er-api.com/v6/latest/USD"

# How often the worker looks; it only fetches when a new publish is due.
CHECK_EVERY_S = 3600
# Fetch this long after the provider's announced next update, so we never ask
# a moment before the new figures exist.
AFTER_PUBLISH = timedelta(minutes=15)
# No good answer for this long and the admin card turns red.
STALE_AFTER = timedelta(hours=48)

# Last good USD rates in this process, for synchronous readers (Odyssey).
_memo: dict = {"rates": {}, "at": 0.0}


# ── Pure rules (tested without a network or a database) ──────────────────────

def _from_unix(value) -> Optional[datetime]:
    try:
        return datetime.fromtimestamp(int(value), tz=timezone.utc)
    except (TypeError, ValueError, OSError):
        return None


def parse_latest(data: dict) -> tuple[Optional[dict], Optional[str]]:
    """`(fields to store, None)` from a good answer, `(None, error)` otherwise.

    The keyed endpoint calls the table `conversion_rates`, the open one `rates`.
    """
    if not isinstance(data, dict):
        return None, "unreadable-response"
    if data.get("result") != "success":
        return None, str(data.get("error-type") or data.get("error") or "unknown-error")
    rates = data.get("conversion_rates") or data.get("rates") or {}
    if not isinstance(rates, dict) or not rates.get(BASE):
        return None, "no-rates-in-response"
    clean = {
        str(code).upper(): float(value)
        for code, value in rates.items()
        if isinstance(value, (int, float)) and value > 0
    }
    return {
        "rates": clean,
        "provider_updated_at": _from_unix(data.get("time_last_update_unix")),
        "provider_next_update_at": _from_unix(data.get("time_next_update_unix")),
    }, None


def is_due(
    fetched_at: Optional[datetime],
    next_update_at: Optional[datetime],
    source: Optional[str],
    wanted_source: str,
    now: datetime,
) -> bool:
    """Whether the worker should fetch now.

    Yes with nothing stored, when the source changed (a key was added or
    removed), once the provider's next publish has passed, or as a safety net
    when the last good fetch is a day old and the provider gave no time.
    """
    if fetched_at is None or source != wanted_source:
        return True
    if next_update_at is not None:
        return now >= next_update_at + AFTER_PUBLISH
    return now - fetched_at >= timedelta(hours=24)


def health(fetched_at: Optional[datetime], last_error: Optional[str], now: datetime) -> str:
    """"ok", "stale" (nothing good for 48 hours) or "error" (the last try failed)."""
    if fetched_at is None:
        return "error" if last_error else "stale"
    if now - fetched_at > STALE_AFTER:
        return "stale"
    return "error" if last_error else "ok"


def mask_key(key: str) -> str:
    key = (key or "").strip()
    return f"••••{key[-4:]}" if len(key) > 4 else ""


# ── Fetching ─────────────────────────────────────────────────────────────────

async def _api_key(db: AsyncSession) -> str:
    # Fresh read: the admin may have just saved a new key in another process.
    return (await SettingsService(db).get_setting_fresh(KEY_SETTING, "")).strip()


async def refresh(db: AsyncSession) -> FxRate:
    """Fetch now and store the result, good or bad. Never raises for a provider
    failure: the error is recorded on the row and the old rates stay."""
    key = await _api_key(db)
    source = KEYED_SOURCE if key else OPEN_SOURCE
    url = _KEYED_URL.format(key=key) if key else _OPEN_URL
    now = datetime.now(timezone.utc)

    fields, error = None, None
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(url)
        try:
            data = response.json()
        except ValueError:
            data = None
        fields, error = parse_latest(data)
        if fields is None and response.status_code == 429:
            error = "rate-limited"
    except httpx.HTTPError as e:
        error = f"network: {type(e).__name__}"

    row = await db.get(FxRate, BASE)
    if row is None:
        row = FxRate(base=BASE, rates={}, source=source)
        db.add(row)
    row.last_attempt_at = now
    if fields is not None:
        row.rates = fields["rates"]
        row.source = source
        row.provider_updated_at = fields["provider_updated_at"]
        row.provider_next_update_at = fields["provider_next_update_at"]
        row.fetched_at = now
        row.last_error = None
        _memo.update(rates=fields["rates"], at=time.time())
    else:
        row.last_error = error
        logger.warning("[fx] refresh from %s failed: %s", source, error)
    await db.commit()
    await db.refresh(row)
    return row


async def get_row(db: AsyncSession) -> Optional[FxRate]:
    return await db.get(FxRate, BASE)


async def quota(db: AsyncSession) -> Optional[dict]:
    """The keyed plan's monthly allowance, or None with no key or on failure.
    Asked only when the admin card is opened."""
    key = await _api_key(db)
    if not key:
        return None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            data = (await client.get(_QUOTA_URL.format(key=key))).json()
    except (httpx.HTTPError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("result") != "success":
        return None
    plan = data.get("plan_quota")
    remaining = data.get("requests_remaining")
    return {
        "plan_quota": plan,
        "requests_remaining": remaining,
        "requests_used": (plan - remaining) if isinstance(plan, int) and isinstance(remaining, int) else None,
        "refresh_day_of_month": data.get("refresh_day_of_month"),
    }


def cached_usd_rates() -> dict:
    """The last good USD rates this process has seen, or {}. Synchronous, for
    callers that cannot await (Odyssey's price conversion)."""
    return _memo["rates"] if _memo["rates"] else {}


async def usd_rates(db: AsyncSession) -> dict:
    """Today's USD rates for a request handler. Only the worker refreshes the
    memo, so an API process reads the stored row, at most once an hour."""
    if not _memo["rates"] or time.time() - _memo["at"] > 3600:
        await load_memo(db)
    return cached_usd_rates()


async def load_memo(db: AsyncSession) -> None:
    row = await get_row(db)
    if row is not None and row.rates:
        _memo.update(rates=row.rates, at=time.time())


async def refresh_loop() -> None:
    """Worker loop: look every hour, fetch only when a new publish is due."""
    while True:
        try:
            async with async_session() as db:
                row = await get_row(db)
                key = await _api_key(db)
                wanted = KEYED_SOURCE if key else OPEN_SOURCE
                now = datetime.now(timezone.utc)
                if row is None or is_due(
                    row.fetched_at, row.provider_next_update_at, row.source, wanted, now
                ):
                    await refresh(db)
                else:
                    await load_memo(db)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("[fx] refresh loop error: %s", e)
        await asyncio.sleep(CHECK_EVERY_S)
