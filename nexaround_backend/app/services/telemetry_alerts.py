"""Anomaly detection over api_events.

Three rules, each chosen because it corresponds to a failure this system has
actually had:

  request_denied  An invalid or restricted key. Went unnoticed for four days;
                  every call in that window failed while the app retried.
  cache_collapse  An operation whose cache stops working. Looks identical to
                  organic growth on a call-count chart, which is why it needs
                  its own rule.
  volume_spike    A runaway client loop. One account once made 12,353 Maps
                  calls in an hour and nothing said anything.

Alerts are deduplicated: the same rule for the same subject will not re-fire
while it is still open. An alert channel that repeats itself gets muted, and a
muted channel is the same as no channel.
"""
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app.core.database import async_session

logger = logging.getLogger(__name__)

# Don't alert on tiny samples — three denials out of four calls is noise, not
# an incident.
_MIN_SAMPLE = 30

RULES = {
    "request_denied": {
        "window_minutes": 15,
        "threshold_pct": 5.0,
        "cooldown_minutes": 60,
    },
    "cache_collapse": {
        "window_minutes": 60,
        "drop_points": 20.0,
        "cooldown_minutes": 180,
    },
    "volume_spike": {
        "window_minutes": 60,
        "multiple": 3.0,
        "cooldown_minutes": 120,
    },
    "budget": {
        # Budget state changes slowly; once a day is enough to be useful
        # without becoming background noise.
        "cooldown_minutes": 1440,
    },
}


async def _recent_alert_exists(db, rule: str, subject: str, cooldown_min: int) -> bool:
    since = datetime.now(timezone.utc) - timedelta(minutes=cooldown_min)
    found = (await db.execute(text("""
        SELECT 1 FROM api_alerts
        WHERE rule = :rule AND subject = :subject AND created_at >= :since
        LIMIT 1
    """), {"rule": rule, "subject": subject, "since": since})).scalar()
    return bool(found)


async def _raise_alert(db, rule: str, subject: str, severity: str,
                       message: str, detail: dict) -> bool:
    cooldown = RULES[rule]["cooldown_minutes"]
    if await _recent_alert_exists(db, rule, subject, cooldown):
        return False
    import json
    await db.execute(text("""
        INSERT INTO api_alerts (rule, subject, severity, message, detail)
        VALUES (:rule, :subject, :severity, :message, CAST(:detail AS jsonb))
    """), {"rule": rule, "subject": subject, "severity": severity,
           "message": message, "detail": json.dumps(detail)})
    logger.warning("telemetry alert [%s] %s: %s", severity, subject, message)
    return True


async def _check_request_denied(db) -> list:
    """A provider refusing calls — almost always a key problem."""
    cfg = RULES["request_denied"]
    since = datetime.now(timezone.utc) - timedelta(minutes=cfg["window_minutes"])
    rows = (await db.execute(text("""
        SELECT provider,
               count(*) AS total,
               count(*) FILTER (
                 WHERE provider_status IN ('REQUEST_DENIED','INVALID_REQUEST',
                                           'INVALID_ARGUMENT','OVER_QUERY_LIMIT')
               ) AS denied
        FROM api_events
        WHERE ts >= :since AND served_from = 'upstream'
        GROUP BY 1 HAVING count(*) >= :min_sample
    """), {"since": since, "min_sample": _MIN_SAMPLE})).mappings().all()

    fired = []
    for r in rows:
        pct = 100.0 * r["denied"] / r["total"]
        if pct < cfg["threshold_pct"]:
            continue
        if await _raise_alert(
            db, "request_denied", r["provider"],
            "critical" if pct > 50 else "warning",
            f"{pct:.0f}% of {r['provider']} calls were refused in the last "
            f"{cfg['window_minutes']} minutes ({r['denied']} of {r['total']}). "
            f"Check that the API key is valid, unrestricted and within quota.",
            {"provider": r["provider"], "denied": r["denied"],
             "total": r["total"], "pct": round(pct, 1)},
        ):
            fired.append(("request_denied", r["provider"]))
    return fired


async def _check_cache_collapse(db) -> list:
    """An operation that used to be served locally and suddenly isn't."""
    cfg = RULES["cache_collapse"]
    now = datetime.now(timezone.utc)
    recent_since = now - timedelta(minutes=cfg["window_minutes"])
    base_since = now - timedelta(days=7)

    rows = (await db.execute(text("""
        WITH recent AS (
            SELECT operation, count(*) total,
                   count(*) FILTER (WHERE served_from <> 'upstream') cached
            FROM api_events WHERE ts >= :recent_since
            GROUP BY 1 HAVING count(*) >= :min_sample
        ),
        baseline AS (
            SELECT operation, count(*) total,
                   count(*) FILTER (WHERE served_from <> 'upstream') cached
            FROM api_events
            WHERE ts >= :base_since AND ts < :recent_since
            GROUP BY 1 HAVING count(*) >= :min_sample
        )
        SELECT r.operation,
               100.0 * r.cached / r.total AS recent_pct,
               100.0 * b.cached / b.total AS baseline_pct,
               r.total AS recent_calls
        FROM recent r JOIN baseline b USING (operation)
        WHERE (100.0 * b.cached / b.total) - (100.0 * r.cached / r.total) >= :drop
    """), {"recent_since": recent_since, "base_since": base_since,
           "min_sample": _MIN_SAMPLE, "drop": cfg["drop_points"]})).mappings().all()

    fired = []
    for r in rows:
        drop = float(r["baseline_pct"]) - float(r["recent_pct"])
        if await _raise_alert(
            db, "cache_collapse", r["operation"], "warning",
            f"Cache hit rate for {r['operation']} fell {drop:.0f} points "
            f"({float(r['baseline_pct']):.0f}% → {float(r['recent_pct']):.0f}%) "
            f"over the last hour. Every missed hit is a paid call.",
            {"operation": r["operation"], "recent_pct": round(float(r["recent_pct"]), 1),
             "baseline_pct": round(float(r["baseline_pct"]), 1),
             "recent_calls": r["recent_calls"]},
        ):
            fired.append(("cache_collapse", r["operation"]))
    return fired


async def _check_volume_spike(db) -> list:
    """Upstream volume well above its own recent normal — a client loop."""
    cfg = RULES["volume_spike"]
    now = datetime.now(timezone.utc)
    recent_since = now - timedelta(minutes=cfg["window_minutes"])

    rows = (await db.execute(text("""
        WITH recent AS (
            SELECT operation, count(*) AS calls
            FROM api_events
            WHERE ts >= :recent_since AND served_from = 'upstream'
            GROUP BY 1 HAVING count(*) >= :min_sample
        ),
        hourly AS (
            SELECT operation, date_trunc('hour', ts) h, count(*) c
            FROM api_events
            WHERE ts >= :base_since AND ts < :recent_since
              AND served_from = 'upstream'
            GROUP BY 1, 2
        ),
        med AS (
            SELECT operation,
                   percentile_cont(0.5) WITHIN GROUP (ORDER BY c) AS median_hourly
            FROM hourly GROUP BY 1
        )
        SELECT r.operation, r.calls, m.median_hourly
        FROM recent r JOIN med m USING (operation)
        WHERE m.median_hourly > 0 AND r.calls >= m.median_hourly * :multiple
    """), {"recent_since": recent_since,
           "base_since": now - timedelta(days=7),
           "min_sample": _MIN_SAMPLE, "multiple": cfg["multiple"]})).mappings().all()

    fired = []
    for r in rows:
        ratio = r["calls"] / float(r["median_hourly"])
        if await _raise_alert(
            db, "volume_spike", r["operation"],
            "critical" if ratio > 10 else "warning",
            f"{r['operation']} made {r['calls']} paid calls in the last hour, "
            f"{ratio:.1f}× its 7-day median of {float(r['median_hourly']):.0f}. "
            f"Check for a retry loop or an uncached path.",
            {"operation": r["operation"], "calls": r["calls"],
             "median_hourly": float(r["median_hourly"]), "ratio": round(ratio, 1)},
        ):
            fired.append(("volume_spike", r["operation"]))
    return fired


async def _check_budget(db) -> list:
    """Approaching or past the configured monthly ceiling."""
    from app.services import spend_guard
    st = await spend_guard.status()
    if not st["monthly_budget_usd"]:
        return []
    pct = st["pct_consumed"] or 0
    if pct < 80:
        return []
    severity = "critical" if pct >= 100 else "warning"
    subject = "monthly_budget"
    fired = []
    if await _raise_alert(
        db, "budget", subject, severity,
        f"API spend is at {pct:.0f}% of the ${st['monthly_budget_usd']:.2f} "
        f"monthly budget (${st['month_to_date_usd']:.2f} so far)."
        + ("" if st["enforcing"] else " Enforcement is OFF — calls are still being paid for."),
        st,
    ):
        fired.append(("budget", subject))
    return fired


async def run_checks() -> dict:
    """Evaluate every rule. Safe to call on a timer."""
    fired = []
    try:
        async with async_session() as db:
            for fn in (_check_request_denied, _check_cache_collapse,
                       _check_volume_spike, _check_budget):
                try:
                    fired += await fn(db)
                except Exception as e:
                    logger.warning("alert rule %s failed: %s", fn.__name__, e)
            await db.commit()
    except Exception as e:
        logger.warning("telemetry alert run failed: %s", e)
    if fired:
        await _notify(fired)
    return {"fired": fired, "count": len(fired)}


async def _notify(fired: list) -> None:
    """Deliver newly raised alerts.

    Email only, and only for critical ones. An alert nobody reads is not a
    control, but an inbox full of warnings is the same thing.
    """
    try:
        async with async_session() as db:
            rows = (await db.execute(text("""
                SELECT rule, subject, severity, message FROM api_alerts
                WHERE severity = 'critical' AND notified_at IS NULL
                ORDER BY created_at DESC LIMIT 10
            """))).mappings().all()
            if not rows:
                return

            from app.services.settings_service import SettingsService
            to_addr = await SettingsService(db).get_setting("contact_email")
            if to_addr:
                try:
                    from app.services.email_service import send_email
                    body = "\n\n".join(f"[{r['severity'].upper()}] {r['subject']}\n{r['message']}"
                                       for r in rows)
                    await send_email(
                        to_addr,
                        f"NexAround: {len(rows)} critical API alert(s)",
                        body,
                    )
                except Exception as e:
                    logger.warning("alert email failed: %s", e)

            await db.execute(text("""
                UPDATE api_alerts SET notified_at = now()
                WHERE severity = 'critical' AND notified_at IS NULL
            """))
            await db.commit()
    except Exception as e:
        logger.warning("alert notify failed: %s", e)


async def alert_loop(interval_seconds: float = 300.0) -> None:
    """Background evaluation, on the same cadence as the rollup."""
    import asyncio
    logger.info("telemetry alerts started (interval=%ss)", interval_seconds)
    while True:
        try:
            await asyncio.sleep(interval_seconds)
            await run_checks()
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("alert loop error: %s", e)
