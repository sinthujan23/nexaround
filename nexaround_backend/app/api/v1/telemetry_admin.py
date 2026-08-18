"""Admin API for the API Usage dashboard.

Every endpoint takes the same window (`from`/`to`) plus optional filters, and
follows one rule: **wide ranges read the rollup, never raw events.** The
`_use_rollup()` helper decides, so no panel can accidentally put a
partition-wide scan behind a date picker.

Costs returned here are estimates from `api_sku_rates` and are labelled as such
in the UI. They are for spotting which operation is expensive and which cache is
failing — not for reconciling an invoice. `/export.csv` exists for that.
"""
import csv
import io
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.v1.admin import verify_admin_token
from app.services import telemetry, telemetry_rollup, telemetry_alerts, spend_guard

router = APIRouter(prefix="/admin/telemetry", tags=["Admin Telemetry"])


# Ranges longer than this read api_usage_hourly instead of api_events.
_RAW_WINDOW_HOURS = 48
_MAX_RANGE_DAYS = 400


def _window(frm: Optional[datetime], to: Optional[datetime]) -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc)
    end = to or now
    start = frm or (end - timedelta(days=7))
    if start.tzinfo is None:
        start = start.replace(tzinfo=timezone.utc)
    if end.tzinfo is None:
        end = end.replace(tzinfo=timezone.utc)
    if start >= end:
        raise HTTPException(400, "`from` must be earlier than `to`")
    if (end - start).days > _MAX_RANGE_DAYS:
        raise HTTPException(400, f"Range exceeds {_MAX_RANGE_DAYS} days")
    return start, end


def _use_rollup(start: datetime, end: datetime) -> bool:
    return (end - start) > timedelta(hours=_RAW_WINDOW_HOURS)


def _filters(provider, operation, served_from, platform, alias="e") -> tuple[str, dict]:
    """Build a shared WHERE fragment. Values are always bound, never formatted in."""
    clauses, params = [], {}
    for col, val in (("provider", provider), ("operation", operation),
                     ("served_from", served_from)):
        if val:
            clauses.append(f"AND {alias}.{col} = :{col}")
            params[col] = val
    if platform and alias == "e":  # only raw events carry platform
        clauses.append("AND e.platform = :platform")
        params["platform"] = platform
    return " ".join(clauses), params


# ── Schemas ─────────────────────────────────────────────────────────────────

class SummaryResponse(BaseModel):
    requests: int
    billable_calls: int
    est_cost_usd: float
    served_free_pct: float
    error_pct: float
    prev_requests: int
    prev_est_cost_usd: float
    source: str


class BudgetSettings(BaseModel):
    monthly_budget_usd: float
    alert_at_pct: int


# ── Endpoints ───────────────────────────────────────────────────────────────

@router.get("/summary", response_model=SummaryResponse)
async def summary(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    provider: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Header tiles, with a delta against the immediately preceding window."""
    start, end = _window(frm, to)
    prev_start = start - (end - start)
    pfilter = "AND provider = :provider" if provider else ""
    params = {"start": start, "end": end, "prev_start": prev_start}
    if provider:
        params["provider"] = provider

    if _use_rollup(start, end):
        sql = f"""
            SELECT COALESCE(sum(calls),0) requests,
                   COALESCE(sum(billable_calls),0) billable,
                   COALESCE(sum(est_cost_usd),0) cost,
                   COALESCE(sum(calls) FILTER (WHERE served_from <> 'upstream'),0) free,
                   COALESCE(sum(error_count),0) errors
            FROM api_usage_hourly
            WHERE bucket >= :start AND bucket < :end {pfilter}
        """
        prev_sql = f"""
            SELECT COALESCE(sum(calls),0) requests, COALESCE(sum(est_cost_usd),0) cost
            FROM api_usage_hourly
            WHERE bucket >= :prev_start AND bucket < :start {pfilter}
        """
        source = "rollup"
    else:
        sql = f"""
            SELECT count(*) requests,
                   count(*) FILTER (WHERE billable) billable,
                   COALESCE(sum(est_cost_usd),0) cost,
                   count(*) FILTER (WHERE served_from <> 'upstream') free,
                   count(*) FILTER (WHERE error IS NOT NULL OR http_status >= 400) errors
            FROM api_events
            WHERE ts >= :start AND ts < :end {pfilter}
        """
        prev_sql = f"""
            SELECT count(*) requests, COALESCE(sum(est_cost_usd),0) cost
            FROM api_events
            WHERE ts >= :prev_start AND ts < :start {pfilter}
        """
        source = "raw"

    row = (await db.execute(text(sql), params)).mappings().one()
    prev = (await db.execute(text(prev_sql), params)).mappings().one()

    total = row["requests"] or 0
    return SummaryResponse(
        requests=total,
        billable_calls=row["billable"] or 0,
        est_cost_usd=float(row["cost"] or 0),
        served_free_pct=round(100.0 * (row["free"] or 0) / total, 2) if total else 0.0,
        error_pct=round(100.0 * (row["errors"] or 0) / total, 2) if total else 0.0,
        prev_requests=prev["requests"] or 0,
        prev_est_cost_usd=float(prev["cost"] or 0),
        source=source,
    )


@router.get("/timeseries")
async def timeseries(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    group_by: str = Query("served_from", pattern="^(served_from|provider|operation)$"),
    provider: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Bucketed counts for the main chart, stacked by `group_by`."""
    start, end = _window(frm, to)
    span_hours = (end - start).total_seconds() / 3600
    # Keep the series to a sane number of points regardless of range.
    bucket = "day" if span_hours > 24 * 14 else ("hour" if span_hours > 6 else "minute")
    pfilter = "AND provider = :provider" if provider else ""
    params = {"start": start, "end": end}
    if provider:
        params["provider"] = provider

    if _use_rollup(start, end):
        sql = f"""
            SELECT date_trunc('{bucket}', bucket) t, {group_by} k,
                   sum(calls) calls, sum(est_cost_usd) cost
            FROM api_usage_hourly
            WHERE bucket >= :start AND bucket < :end {pfilter}
            GROUP BY 1,2 ORDER BY 1,2
        """
    else:
        sql = f"""
            SELECT date_trunc('{bucket}', ts) t, {group_by} k,
                   count(*) calls, sum(est_cost_usd) cost
            FROM api_events
            WHERE ts >= :start AND ts < :end {pfilter}
            GROUP BY 1,2 ORDER BY 1,2
        """
    rows = (await db.execute(text(sql), params)).mappings().all()
    return {
        "bucket": bucket,
        "group_by": group_by,
        "points": [
            {"t": r["t"], "key": r["k"], "calls": r["calls"],
             "cost": float(r["cost"] or 0)}
            for r in rows
        ],
    }


@router.get("/breakdown")
async def breakdown(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Per-SKU cost table, with free-tier consumption for the current month.

    The free-tier figure is what tells you how close an operation is to
    starting to cost real money — the number a raw call count hides.
    """
    start, end = _window(frm, to)
    src = "api_usage_hourly" if _use_rollup(start, end) else "api_events"
    tcol, ccol = ("bucket", "sum(calls)") if src == "api_usage_hourly" else ("ts", "count(*)")
    bcol = "sum(billable_calls)" if src == "api_usage_hourly" else "count(*) FILTER (WHERE billable)"

    rows = (await db.execute(text(f"""
        SELECT provider, operation,
               {ccol} calls, {bcol} billable, COALESCE(sum(est_cost_usd),0) cost
        FROM {src}
        WHERE {tcol} >= :start AND {tcol} < :end
        GROUP BY 1,2 ORDER BY cost DESC, calls DESC
    """), {"start": start, "end": end})).mappings().all()

    # Month-to-date billable volume per SKU, against its free allowance.
    month_start = datetime.now(timezone.utc).replace(
        day=1, hour=0, minute=0, second=0, microsecond=0)
    tiers = (await db.execute(text("""
        SELECT r.sku, r.provider, r.free_tier_monthly, r.unit_cost_usd,
               COALESCE(count(e.id), 0) AS used
        FROM api_sku_rates r
        LEFT JOIN api_events e
               ON e.sku = r.sku AND e.billable AND e.ts >= :month_start
        GROUP BY r.sku, r.provider, r.free_tier_monthly, r.unit_cost_usd
        ORDER BY used DESC
    """), {"month_start": month_start})).mappings().all()

    return {
        "operations": [
            {"provider": r["provider"], "operation": r["operation"],
             "calls": r["calls"], "billable_calls": r["billable"],
             "est_cost_usd": float(r["cost"] or 0)}
            for r in rows
        ],
        "free_tier": [
            {"sku": t["sku"], "provider": t["provider"],
             "used_this_month": t["used"], "free_tier_monthly": t["free_tier_monthly"],
             "unit_cost_usd": float(t["unit_cost_usd"]),
             "pct_consumed": round(100.0 * t["used"] / t["free_tier_monthly"], 1)
                             if t["free_tier_monthly"] else None}
            for t in tiers
        ],
    }


@router.get("/funnel")
async def funnel(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Where each operation was served from — the cache-effectiveness panel.

    An operation at 0% here with meaningful volume is an uncached paid path,
    which is the single most actionable signal in this dashboard.
    """
    start, end = _window(frm, to)
    src = "api_usage_hourly" if _use_rollup(start, end) else "api_events"
    tcol = "bucket" if src == "api_usage_hourly" else "ts"
    ccol = "sum(calls)" if src == "api_usage_hourly" else "count(*)"

    rows = (await db.execute(text(f"""
        SELECT operation, served_from, {ccol} calls,
               COALESCE(sum(est_cost_usd),0) cost
        FROM {src}
        WHERE {tcol} >= :start AND {tcol} < :end
        GROUP BY 1,2
    """), {"start": start, "end": end})).mappings().all()

    ops: dict[str, dict] = {}
    for r in rows:
        op = ops.setdefault(r["operation"], {
            "operation": r["operation"], "total": 0, "upstream": 0,
            "est_cost_usd": 0.0, "sources": {},
        })
        op["sources"][r["served_from"]] = r["calls"]
        op["total"] += r["calls"]
        op["est_cost_usd"] += float(r["cost"] or 0)
        if r["served_from"] == "upstream":
            op["upstream"] += r["calls"]

    out = []
    for op in ops.values():
        op["served_free_pct"] = round(
            100.0 * (op["total"] - op["upstream"]) / op["total"], 1) if op["total"] else 0.0
        out.append(op)
    out.sort(key=lambda o: o["est_cost_usd"], reverse=True)
    return {"operations": out}


@router.get("/duplicates")
async def duplicates(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    limit: int = Query(50, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Cache keys paid for more than once — a ranked to-do list.

    `recoverable_usd` is what a working cache would have saved: everything after
    the first paid call for a given key.
    """
    start, end = _window(frm, to)
    rows = (await db.execute(text("""
        SELECT cache_key, operation, count(*) paid_times,
               COALESCE(sum(est_cost_usd),0) spent,
               COALESCE(sum(est_cost_usd),0) * (count(*) - 1) / count(*) recoverable
        FROM api_events
        WHERE ts >= :start AND ts < :end
          AND served_from = 'upstream' AND cache_key IS NOT NULL
        GROUP BY 1,2 HAVING count(*) > 1
        ORDER BY recoverable DESC, paid_times DESC
        LIMIT :limit
    """), {"start": start, "end": end, "limit": limit})).mappings().all()

    return {
        "keys": [
            {"cache_key": r["cache_key"], "operation": r["operation"],
             "paid_times": r["paid_times"], "spent_usd": float(r["spent"]),
             "recoverable_usd": round(float(r["recoverable"]), 6)}
            for r in rows
        ],
        "total_recoverable_usd": round(sum(float(r["recoverable"]) for r in rows), 4),
    }


@router.get("/users")
async def top_users(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    order: str = Query("cost", pattern="^(cost|calls)$"),
    limit: int = Query(25, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Attribution: who is generating the spend."""
    start, end = _window(frm, to)
    order_col = "cost DESC" if order == "cost" else "calls DESC"
    rows = (await db.execute(text(f"""
        SELECT d.user_id, u.email, u.display_name,
               sum(d.calls) calls, sum(d.billable_calls) billable,
               COALESCE(sum(d.est_cost_usd),0) cost
        FROM api_usage_user_daily d
        LEFT JOIN users u ON u.id = d.user_id
        -- CAST(...) rather than ::date: SQLAlchemy's text() reads ':' as the
        -- start of a bind parameter, so `:start::date` parses as garbage.
        WHERE d.day >= CAST(:start AS date) AND d.day <= CAST(:end AS date)
        GROUP BY 1,2,3 ORDER BY {order_col}
        LIMIT :limit
    """), {"start": start, "end": end, "limit": limit})).mappings().all()
    return {
        "users": [
            {"user_id": str(r["user_id"]), "email": r["email"],
             "display_name": r["display_name"], "calls": r["calls"],
             "billable_calls": r["billable"], "est_cost_usd": float(r["cost"])}
            for r in rows
        ]
    }


@router.get("/errors")
async def errors(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Provider health. A REQUEST_DENIED share above a few percent means a key
    is invalid or restricted — the failure mode that went unnoticed for days."""
    start, end = _window(frm, to)
    src = "api_usage_hourly" if _use_rollup(start, end) else "api_events"
    tcol = "bucket" if src == "api_usage_hourly" else "ts"
    ccol = "sum(calls)" if src == "api_usage_hourly" else "count(*)"

    statuses = (await db.execute(text(f"""
        SELECT provider, COALESCE(NULLIF(provider_status,''),'(none)') status, {ccol} calls
        FROM {src} WHERE {tcol} >= :start AND {tcol} < :end
        GROUP BY 1,2 ORDER BY calls DESC
    """), {"start": start, "end": end})).mappings().all()

    latency = (await db.execute(text(f"""
        SELECT provider, operation,
               max(p95_latency_ms) p95
        FROM api_usage_hourly WHERE bucket >= :start AND bucket < :end
        GROUP BY 1,2 ORDER BY p95 DESC NULLS LAST LIMIT 20
    """), {"start": start, "end": end})).mappings().all()

    recent = (await db.execute(text("""
        SELECT ts, provider, operation, http_status, provider_status, error
        FROM api_events
        WHERE ts >= :start AND ts < :end
          AND (error IS NOT NULL OR http_status >= 400
               OR provider_status IN ('REQUEST_DENIED','OVER_QUERY_LIMIT','INVALID_REQUEST'))
        ORDER BY ts DESC LIMIT 50
    """), {"start": start, "end": end})).mappings().all()

    return {
        "by_status": [dict(r) for r in statuses],
        "slowest": [dict(r) for r in latency],
        "recent_failures": [dict(r) for r in recent],
    }


@router.get("/events")
async def events(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    provider: Optional[str] = None,
    operation: Optional[str] = None,
    served_from: Optional[str] = None,
    platform: Optional[str] = None,
    request_id: Optional[str] = None,
    user_id: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Raw event stream for the live tail and drill-down.

    Filtering by `request_id` expands one client action into every upstream call
    it caused — the view that makes fan-out patterns obvious.
    """
    start, end = _window(frm, to)
    where, params = _filters(provider, operation, served_from, platform)
    if request_id:
        where += " AND e.request_id = :request_id"
        params["request_id"] = request_id
    if user_id:
        where += " AND e.user_id = :user_id"
        params["user_id"] = user_id
    params |= {"start": start, "end": end,
               "limit": page_size, "offset": (page - 1) * page_size}

    rows = (await db.execute(text(f"""
        SELECT e.ts, e.request_id, e.provider, e.operation, e.sku, e.served_from,
               e.billable, e.est_cost_usd, e.http_status, e.provider_status,
               e.latency_ms, e.user_id, e.app_version, e.platform, e.cache_key,
               e.error, e.route, e.ingest,
               e.prompt_tokens, e.completion_tokens, e.total_tokens
        FROM api_events e
        WHERE e.ts >= :start AND e.ts < :end {where}
        ORDER BY e.ts DESC LIMIT :limit OFFSET :offset
    """), params)).mappings().all()

    total = (await db.execute(text(f"""
        SELECT count(*) FROM api_events e
        WHERE e.ts >= :start AND e.ts < :end {where}
    """), params)).scalar() or 0

    return {
        "events": [
            dict(r) | {"est_cost_usd": float(r["est_cost_usd"] or 0)} for r in rows
        ],
        "total": total, "page": page, "page_size": page_size,
    }


@router.get("/export.csv")
async def export_csv(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    provider: Optional[str] = None,
    include_ip: bool = False,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Raw events as CSV, for reconciling against the provider's invoice.

    Client IP is excluded unless explicitly requested — it is the one column
    here that is personal data, and a billing export rarely needs it.
    """
    start, end = _window(frm, to)
    pfilter = "AND provider = :provider" if provider else ""
    params = {"start": start, "end": end}
    if provider:
        params["provider"] = provider

    cols = ["ts", "provider", "operation", "sku", "served_from", "billable",
            "est_cost_usd", "http_status", "provider_status", "latency_ms",
            "user_id", "app_version", "platform", "cache_key"]
    if include_ip:
        cols.append("client_ip")

    rows = (await db.execute(text(f"""
        SELECT {', '.join(cols)} FROM api_events
        WHERE ts >= :start AND ts < :end {pfilter}
        ORDER BY ts
    """), params)).mappings().all()

    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=cols, extrasaction="ignore")
    writer.writeheader()
    for r in rows:
        writer.writerow({c: r[c] for c in cols})
    buf.seek(0)

    stamp = start.strftime("%Y%m%d")
    return StreamingResponse(
        iter([buf.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition":
                 f'attachment; filename="api_events_{stamp}.csv"'},
    )


@router.get("/budget", response_model=BudgetSettings)
async def get_budget(
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    from app.services.settings_service import SettingsService
    svc = SettingsService(db)
    return BudgetSettings(
        monthly_budget_usd=float(await svc.get_setting("api_monthly_budget_usd") or 0),
        alert_at_pct=int(await svc.get_setting("api_budget_alert_pct") or 80),
    )


@router.put("/budget", response_model=BudgetSettings)
async def set_budget(
    body: BudgetSettings,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    if body.monthly_budget_usd < 0:
        raise HTTPException(400, "Budget must not be negative")
    if not 1 <= body.alert_at_pct <= 100:
        raise HTTPException(400, "Alert threshold must be between 1 and 100")
    from app.services.settings_service import SettingsService
    svc = SettingsService(db)
    await svc.set_setting("api_monthly_budget_usd", str(body.monthly_budget_usd))
    await svc.set_setting("api_budget_alert_pct", str(body.alert_at_pct))
    return body


@router.get("/rates")
async def get_rates(
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Editable SKU pricing. Exposed so estimates can be corrected against a
    real invoice without a deploy."""
    rows = (await db.execute(text("""
        SELECT sku, provider, unit_cost_usd, free_tier_monthly, effective_from, notes
        FROM api_sku_rates ORDER BY provider, unit_cost_usd DESC
    """))).mappings().all()
    return {"rates": [dict(r) | {"unit_cost_usd": float(r["unit_cost_usd"])}
                      for r in rows]}


@router.put("/rates/{sku}")
async def update_rate(
    sku: str,
    unit_cost_usd: float = Query(..., ge=0),
    free_tier_monthly: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    res = await db.execute(text("""
        UPDATE api_sku_rates
        SET unit_cost_usd = :cost, free_tier_monthly = :tier, updated_at = now()
        WHERE sku = :sku
    """), {"cost": unit_cost_usd, "tier": free_tier_monthly, "sku": sku})
    if not res.rowcount:
        raise HTTPException(404, f"Unknown SKU: {sku}")
    await db.commit()
    # Rates are cached in process for 5 minutes; drop it so the change is live.
    await telemetry.refresh_rates()
    return {"sku": sku, "unit_cost_usd": unit_cost_usd,
            "free_tier_monthly": free_tier_monthly}


@router.get("/pipeline")
async def pipeline_health(_=Depends(verify_admin_token)):
    """Telemetry's own counters. Rising drop counts mean the dashboard is
    under-reporting, which is worse than it showing nothing."""
    return telemetry.get_stats()


@router.post("/rollup")
async def force_rollup(_=Depends(verify_admin_token)):
    """Recompute recent buckets now, rather than waiting for the 5-minute tick."""
    return await telemetry_rollup.rollup_once()


# ── Alerts and spend control ────────────────────────────────────────────────

@router.get("/alerts")
async def list_alerts(
    only_open: bool = True,
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Anomalies raised over api_events, newest first."""
    where = "WHERE acknowledged_at IS NULL" if only_open else ""
    rows = (await db.execute(text(f"""
        SELECT id, created_at, rule, subject, severity, message, detail,
               acknowledged_at, notified_at
        FROM api_alerts {where}
        ORDER BY created_at DESC LIMIT :limit
    """), {"limit": limit})).mappings().all()
    counts = (await db.execute(text("""
        SELECT severity, count(*) c FROM api_alerts
        WHERE acknowledged_at IS NULL GROUP BY 1
    """))).mappings().all()
    return {
        "alerts": [dict(r) for r in rows],
        "open_counts": {c["severity"]: c["c"] for c in counts},
    }


@router.post("/alerts/{alert_id}/ack")
async def acknowledge_alert(
    alert_id: int,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    res = await db.execute(text("""
        UPDATE api_alerts SET acknowledged_at = now()
        WHERE id = :id AND acknowledged_at IS NULL
    """), {"id": alert_id})
    await db.commit()
    if not res.rowcount:
        raise HTTPException(404, "Alert not found or already acknowledged")
    return {"id": alert_id, "acknowledged": True}


@router.post("/alerts/run")
async def run_alert_checks(_=Depends(verify_admin_token)):
    """Evaluate every rule now rather than waiting for the timer."""
    return await telemetry_alerts.run_checks()


@router.get("/spend")
async def spend_status(_=Depends(verify_admin_token)):
    """Live spend against the configured limits, from the real-time counters."""
    return await spend_guard.status()


class SpendLimits(BaseModel):
    monthly_budget_usd: float
    user_daily_cap_usd: float
    enforce: bool


@router.put("/spend")
async def set_spend_limits(
    body: SpendLimits,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Update the ceilings.

    `enforce` is the switch that makes them real: with it off the limits only
    raise alerts, with it on paid calls are refused past the ceiling and callers
    fall back to cached results.
    """
    if body.monthly_budget_usd < 0 or body.user_daily_cap_usd < 0:
        raise HTTPException(400, "Limits must not be negative")
    from app.services.settings_service import SettingsService
    svc = SettingsService(db)
    await svc.set_setting(spend_guard.K_MONTHLY_BUDGET, str(body.monthly_budget_usd))
    await svc.set_setting(spend_guard.K_USER_DAILY_CAP, str(body.user_daily_cap_usd))
    await svc.set_setting(spend_guard.K_ENFORCE, "true" if body.enforce else "false")
    await spend_guard.refresh_config()
    return await spend_guard.status()


# ── Per-request and per-user detail ─────────────────────────────────────────

@router.get("/request/{request_id}")
async def request_detail(
    request_id: str,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Everything one inbound request caused.

    This is the view that makes fan-out legible: a single tap on a category
    tile used to produce fifteen paid Find Place calls, and nothing in the old
    logging could show that they belonged together.
    """
    rows = (await db.execute(text("""
        SELECT ts, provider, operation, sku, served_from, billable, est_cost_usd,
               http_status, provider_status, latency_ms, cache_key, error,
               prompt_tokens, completion_tokens, total_tokens, route,
               user_id, app_version, platform, client_ip
        FROM api_events WHERE request_id = :rid ORDER BY ts
    """), {"rid": request_id})).mappings().all()
    if not rows:
        raise HTTPException(404, "No events for that request id")

    first = rows[0]
    return {
        "request_id": request_id,
        "route": first["route"],
        "user_id": str(first["user_id"]) if first["user_id"] else None,
        "app_version": first["app_version"],
        "platform": first["platform"],
        "client_ip": str(first["client_ip"]) if first["client_ip"] else None,
        "started_at": first["ts"],
        "upstream_calls": sum(1 for r in rows if r["served_from"] == "upstream"),
        "cached_calls": sum(1 for r in rows if r["served_from"] != "upstream"),
        "total_cost_usd": float(sum(r["est_cost_usd"] or 0 for r in rows)),
        "total_tokens": sum(r["total_tokens"] or 0 for r in rows) or None,
        "total_latency_ms": sum(r["latency_ms"] or 0 for r in rows),
        "calls": [dict(r) | {"est_cost_usd": float(r["est_cost_usd"] or 0),
                             "user_id": None, "client_ip": None} for r in rows],
    }


@router.get("/user/{user_id}")
async def user_detail(
    user_id: str,
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """One account's behaviour: what they used, how it was served, what it cost."""
    start, end = _window(frm, to)
    p = {"uid": user_id, "start": start, "end": end}

    profile = (await db.execute(text("""
        SELECT u.email, u.display_name, u.created_at, u.is_active
        FROM users u WHERE u.id = CAST(:uid AS uuid)
    """), {"uid": user_id})).mappings().first()

    totals = (await db.execute(text("""
        SELECT count(*) requests,
               count(*) FILTER (WHERE billable) billable,
               COALESCE(sum(est_cost_usd),0) cost,
               COALESCE(sum(total_tokens),0) tokens,
               count(DISTINCT request_id) actions,
               count(DISTINCT ts::date) active_days,
               min(ts) first_seen, max(ts) last_seen
        FROM api_events
        WHERE user_id = CAST(:uid AS uuid) AND ts >= :start AND ts < :end
    """), p)).mappings().one()

    by_operation = (await db.execute(text("""
        SELECT operation, served_from, count(*) calls,
               COALESCE(sum(est_cost_usd),0) cost
        FROM api_events
        WHERE user_id = CAST(:uid AS uuid) AND ts >= :start AND ts < :end
        GROUP BY 1,2 ORDER BY calls DESC LIMIT 40
    """), p)).mappings().all()

    # Which screens this account actually uses, ranked by what they cost.
    by_route = (await db.execute(text("""
        SELECT COALESCE(route,'(unknown)') route, count(*) calls,
               count(DISTINCT request_id) actions,
               COALESCE(sum(est_cost_usd),0) cost
        FROM api_events
        WHERE user_id = CAST(:uid AS uuid) AND ts >= :start AND ts < :end
        GROUP BY 1 ORDER BY cost DESC, calls DESC LIMIT 25
    """), p)).mappings().all()

    daily = (await db.execute(text("""
        SELECT ts::date d, count(*) calls, COALESCE(sum(est_cost_usd),0) cost
        FROM api_events
        WHERE user_id = CAST(:uid AS uuid) AND ts >= :start AND ts < :end
        GROUP BY 1 ORDER BY 1
    """), p)).mappings().all()

    recent = (await db.execute(text("""
        SELECT request_id, route, min(ts) ts, count(*) calls,
               COALESCE(sum(est_cost_usd),0) cost
        FROM api_events
        WHERE user_id = CAST(:uid AS uuid) AND ts >= :start AND ts < :end
        GROUP BY 1,2 ORDER BY ts DESC LIMIT 25
    """), p)).mappings().all()

    return {
        "user": dict(profile) if profile else {"email": None, "display_name": None},
        "totals": dict(totals) | {"cost": float(totals["cost"] or 0)},
        "by_operation": [dict(r) | {"cost": float(r["cost"])} for r in by_operation],
        "by_route": [dict(r) | {"cost": float(r["cost"])} for r in by_route],
        "daily": [dict(r) | {"cost": float(r["cost"])} for r in daily],
        "recent_actions": [dict(r) | {"cost": float(r["cost"])} for r in recent],
    }


@router.get("/routes")
async def routes_breakdown(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Which inbound endpoints generate the upstream work.

    Fan-out is the number to watch: calls per action. A screen that fires
    fifteen paid lookups per tap is a design problem, not a traffic problem.
    """
    start, end = _window(frm, to)
    rows = (await db.execute(text("""
        SELECT COALESCE(route,'(unknown)') route,
               count(*) calls,
               count(DISTINCT request_id) actions,
               count(*) FILTER (WHERE served_from = 'upstream') upstream,
               COALESCE(sum(est_cost_usd),0) cost,
               COALESCE(sum(total_tokens),0) tokens
        FROM api_events
        WHERE ts >= :start AND ts < :end AND route IS NOT NULL
        GROUP BY 1 ORDER BY cost DESC, calls DESC LIMIT 40
    """), {"start": start, "end": end})).mappings().all()
    return {"routes": [
        dict(r) | {
            "cost": float(r["cost"]),
            "fan_out": round(r["calls"] / r["actions"], 2) if r["actions"] else None,
        } for r in rows
    ]}


@router.get("/tokens")
async def token_usage(
    frm: Optional[datetime] = Query(None, alias="from"),
    to: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """AI token accounting. Token-metered providers cannot be understood from
    a call count — one long prompt can outweigh a hundred short ones."""
    start, end = _window(frm, to)
    rows = (await db.execute(text("""
        SELECT provider, operation,
               count(*) calls,
               COALESCE(sum(prompt_tokens),0) prompt_tokens,
               COALESCE(sum(completion_tokens),0) completion_tokens,
               COALESCE(sum(total_tokens),0) total_tokens,
               COALESCE(sum(est_cost_usd),0) cost,
               COALESCE(round(avg(total_tokens)),0) avg_tokens
        FROM api_events
        WHERE ts >= :start AND ts < :end AND total_tokens IS NOT NULL
        GROUP BY 1,2 ORDER BY total_tokens DESC
    """), {"start": start, "end": end})).mappings().all()
    return {"usage": [dict(r) | {"cost": float(r["cost"])} for r in rows],
            "total_tokens": sum(r["total_tokens"] for r in rows)}


@router.get("/coverage")
async def data_coverage(
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """What the dashboard can and cannot tell you, by period.

    Legacy rows were reconstructed from api_request_logs, which logged before
    the HTTP call and never saw a cache. They carry real volume and nothing
    else. Saying so here stops a reconstructed number being read as a measured
    one.
    """
    rows = (await db.execute(text("""
        SELECT ingest, count(*) rows, min(ts) lo, max(ts) hi,
               count(*) FILTER (WHERE served_from <> 'upstream') cached,
               COALESCE(sum(est_cost_usd),0) cost
        FROM api_events GROUP BY 1
    """))).mappings().all()
    return {"sources": [
        dict(r) | {
            "cost": float(r["cost"]),
            "has_cache_data": r["ingest"] == "live",
            "has_cost_data": r["ingest"] == "live",
        } for r in rows
    ]}
