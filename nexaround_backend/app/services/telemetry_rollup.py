"""Aggregation of api_events into the tables the dashboard reads.

The dashboard must never scan raw events. At production volume api_events grows
by millions of rows a month, and a 90-day panel query over that would be a
partition-wide sequential scan every time someone opens the tab.

Two rollups are maintained, both idempotent: a bucket is recomputed from its
source rows rather than incremented, so a re-run after a failure produces the
same numbers instead of double-counting.
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app.core.database import async_session

logger = logging.getLogger(__name__)

# How far back each run recomputes. Wide enough to absorb a flusher that fell
# behind or a scheduler that missed a beat, narrow enough to stay cheap.
_LOOKBACK_HOURS = 3


_HOURLY_SQL = text("""
    INSERT INTO api_usage_hourly (
        bucket, provider, operation, served_from, provider_status,
        calls, billable_calls, est_cost_usd,
        p50_latency_ms, p95_latency_ms, error_count, total_tokens
    )
    SELECT
        date_trunc('hour', ts)                                    AS bucket,
        provider,
        operation,
        served_from,
        COALESCE(provider_status, '')                             AS provider_status,
        count(*)                                                  AS calls,
        count(*) FILTER (WHERE billable)                          AS billable_calls,
        COALESCE(sum(est_cost_usd), 0)                            AS est_cost_usd,
        percentile_disc(0.5) WITHIN GROUP (ORDER BY latency_ms)   AS p50_latency_ms,
        percentile_disc(0.95) WITHIN GROUP (ORDER BY latency_ms)  AS p95_latency_ms,
        count(*) FILTER (WHERE error IS NOT NULL OR http_status >= 400) AS error_count,
        COALESCE(sum(total_tokens), 0)                            AS total_tokens
    FROM api_events
    WHERE ts >= :since AND ts < :until
    GROUP BY 1, 2, 3, 4, 5
    ON CONFLICT (bucket, provider, operation, served_from, provider_status)
    DO UPDATE SET
        calls          = EXCLUDED.calls,
        billable_calls = EXCLUDED.billable_calls,
        est_cost_usd   = EXCLUDED.est_cost_usd,
        p50_latency_ms = EXCLUDED.p50_latency_ms,
        p95_latency_ms = EXCLUDED.p95_latency_ms,
        error_count    = EXCLUDED.error_count,
        total_tokens   = EXCLUDED.total_tokens
""")


_USER_DAILY_SQL = text("""
    INSERT INTO api_usage_user_daily (
        day, user_id, provider, operation, served_from,
        calls, billable_calls, est_cost_usd, total_tokens, actions
    )
    SELECT
        ts::date, user_id, provider, operation, served_from,
        count(*),
        count(*) FILTER (WHERE billable),
        COALESCE(sum(est_cost_usd), 0),
        COALESCE(sum(total_tokens), 0),
        count(DISTINCT request_id)
    FROM api_events
    WHERE ts >= :since AND ts < :until AND user_id IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5
    ON CONFLICT (day, user_id, provider, operation, served_from)
    DO UPDATE SET
        calls          = EXCLUDED.calls,
        billable_calls = EXCLUDED.billable_calls,
        est_cost_usd   = EXCLUDED.est_cost_usd,
        total_tokens   = EXCLUDED.total_tokens,
        actions        = EXCLUDED.actions
""")


async def rollup_once(lookback_hours: int = _LOOKBACK_HOURS) -> dict:
    """Recompute recent buckets. Safe to call at any time, any frequency."""
    now = datetime.now(timezone.utc)
    since = (now - timedelta(hours=lookback_hours)).replace(
        minute=0, second=0, microsecond=0
    )
    # Exclude the in-flight hour's tail so a bucket is never written from a
    # partially flushed set and then left stale — the next run covers it.
    until = now

    result = {"hourly": 0, "user_daily": 0}
    try:
        async with async_session() as session:
            res = await session.execute(_HOURLY_SQL, {"since": since, "until": until})
            result["hourly"] = res.rowcount or 0
            res = await session.execute(_USER_DAILY_SQL, {"since": since, "until": until})
            result["user_daily"] = res.rowcount or 0
            await session.commit()
    except Exception as e:
        logger.warning("telemetry rollup failed: %s", e)
    return result


async def rollup_loop(interval_seconds: float = 300.0) -> None:
    """Background rollup. Started once at application startup."""
    logger.info("telemetry rollup started (interval=%ss)", interval_seconds)
    while True:
        try:
            await asyncio.sleep(interval_seconds)
            counts = await rollup_once()
            if counts["hourly"]:
                logger.debug("rollup: %s", counts)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("telemetry rollup loop error: %s", e)


# Retention is read from settings so it can be changed without a deploy, and
# defaults long. A short window here is not a tidy-up, it is data destruction:
# a 30-day default silently dropped two months of imported history the moment
# it first ran.
RETENTION_SETTING = "api_events_retention_days"
DEFAULT_RETENTION_DAYS = 400


async def _retention_days() -> int:
    try:
        from app.services.settings_service import SettingsService
        async with async_session() as db:
            raw = await SettingsService(db).get_setting(RETENTION_SETTING)
        days = int(raw) if raw else DEFAULT_RETENTION_DAYS
        # A floor, so a typo or a stray zero cannot wipe recent history either.
        return max(days, 60)
    except Exception:
        return DEFAULT_RETENTION_DAYS


async def maintenance_once(retention_days: int = None) -> dict:
    """Daily housekeeping: create upcoming partitions, drop expired ones.

    Retention is a partition DROP rather than a DELETE — instantaneous, and it
    leaves no dead tuples for autovacuum to chase. Only whole months strictly
    older than the cutoff are dropped, so the current period is never partial.
    """
    if retention_days is None:
        retention_days = await _retention_days()
    out = {"dropped_partitions": 0}
    try:
        from app.services import telemetry
        await telemetry.ensure_partitions(months_ahead=2)
        async with async_session() as session:
            cutoff = (datetime.now(timezone.utc) - timedelta(days=retention_days)).date()
            res = await session.execute(
                text("SELECT drop_api_events_partitions_before(:cutoff)"),
                {"cutoff": cutoff},
            )
            out["dropped_partitions"] = res.scalar() or 0
            await session.commit()
        if out["dropped_partitions"]:
            logger.info("telemetry retention dropped %d partition(s)",
                        out["dropped_partitions"])
    except Exception as e:
        logger.warning("telemetry maintenance failed: %s", e)
    return out


async def maintenance_loop(interval_seconds: float = 86400.0) -> None:
    """Once a day: partitions forward, retention backward."""
    while True:
        try:
            await maintenance_once()
            await asyncio.sleep(interval_seconds)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("telemetry maintenance loop error: %s", e)
            await asyncio.sleep(interval_seconds)
