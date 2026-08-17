"""The single choke point for recording API operations.

Every outbound call and every cache/database hit goes through `track()`. That is
the whole design: one place that knows how to decide whether something was
billable, what it cost, and where it was served from — so call sites never
compute cost and can never disagree about it.

Two rules this module holds to:

1. **Telemetry never breaks a request.** Every failure path is swallowed and
   counted. If Redis is gone, rows fall back to an in-process buffer; if that
   fills, rows are dropped and a counter increments. An API response is never
   delayed or failed because metrics could not be written.

2. **Never write to Postgres on the request path.** `track()` pushes a small
   JSON blob to Redis and returns. A background task drains the queue in
   batches. The old `api_request_logs` approach — `session.add()` +
   `await commit()` inline — put a database round trip in front of every
   proxied call, which is exactly what this replaces.
"""
import asyncio
import hashlib
import json
import logging
import time
import uuid
from collections import deque
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Optional

import redis.asyncio as aioredis
from sqlalchemy import text

from app.core.config import settings
from app.core import request_context

logger = logging.getLogger(__name__)

# ── Constants ───────────────────────────────────────────────────────────────

QUEUE_KEY = "telemetry:queue"
# Cap the Redis queue so a stalled flusher can't consume all of Redis. At ~350
# bytes a row this is roughly 35 MB worst case.
MAX_QUEUE_LEN = 100_000
# In-process fallback when Redis is unreachable. Deliberately small — this is a
# grace buffer for a blip, not a second queue.
FALLBACK_MAXLEN = 5_000

SERVED_FROM_VALUES = frozenset(
    {"upstream", "redis", "memory", "database", "disk", "negative"}
)

# Provider statuses that return HTTP 200 but are NOT billed. ZERO_RESULTS is
# deliberately absent: Google charges for a well-formed query that matched
# nothing, and treating it as free would understate cost in exactly the case
# where a bad query pattern is generating spend.
NON_BILLABLE_STATUSES = frozenset({
    "REQUEST_DENIED",
    "INVALID_REQUEST",
    "OVER_QUERY_LIMIT",
    "UNKNOWN_ERROR",
})

# Counters exposed on the health endpoint so a silently broken pipeline is
# visible rather than merely absent.
_stats = {
    "emitted": 0,
    "dropped_queue_full": 0,
    "dropped_redis_down": 0,
    "flushed": 0,
    "flush_errors": 0,
}

_redis: Optional[aioredis.Redis] = None
_fallback: deque = deque(maxlen=FALLBACK_MAXLEN)

# SKU rates are read constantly and change almost never, so they are cached in
# process and refreshed on a timer rather than joined per row.
_rate_cache: dict[str, dict] = {}
_rate_cache_loaded_at: float = 0.0
_RATE_TTL_SECONDS = 300


def _get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
    return _redis


def get_stats() -> dict:
    """Pipeline counters. Surfaced by /health so drops are observable."""
    return dict(_stats, fallback_depth=len(_fallback))


# ── Rate resolution ─────────────────────────────────────────────────────────

async def _load_rates(force: bool = False) -> dict[str, dict]:
    """Load api_sku_rates into the process cache."""
    global _rate_cache, _rate_cache_loaded_at
    now = time.time()
    if not force and _rate_cache and (now - _rate_cache_loaded_at) < _RATE_TTL_SECONDS:
        return _rate_cache

    try:
        from app.core.database import async_session
        async with async_session() as session:
            result = await session.execute(
                text("SELECT sku, unit_cost_usd, free_tier_monthly FROM api_sku_rates")
            )
            _rate_cache = {
                row.sku: {
                    "unit_cost_usd": Decimal(str(row.unit_cost_usd)),
                    "free_tier_monthly": row.free_tier_monthly,
                }
                for row in result
            }
            _rate_cache_loaded_at = now
    except Exception as e:
        # An unreachable rate table must not stop events being recorded — a row
        # with cost 0 is still worth far more than no row.
        logger.warning("telemetry: could not load SKU rates: %s", e)
    return _rate_cache


async def refresh_rates() -> int:
    """Force a reload. Called after the admin edits a rate."""
    rates = await _load_rates(force=True)
    return len(rates)


# ── The recorder ────────────────────────────────────────────────────────────

class _Recorder:
    """Collects the outcome of one operation. Callers touch only the three
    marker methods; everything else is derived."""

    __slots__ = (
        "provider", "operation", "sku", "cache_key", "params_digest",
        "_started", "served_from", "http_status", "provider_status",
        "latency_ms", "error", "_ctx", "_finalised",
    )

    def __init__(self, provider, operation, sku, cache_key, params_digest, ctx):
        self.provider = provider
        self.operation = operation
        self.sku = sku
        self.cache_key = cache_key
        self.params_digest = params_digest
        self._ctx = ctx
        self._started = time.perf_counter()
        self.served_from: Optional[str] = None
        self.http_status: Optional[int] = None
        self.provider_status: Optional[str] = None
        self.latency_ms: Optional[int] = None
        self.error: Optional[str] = None
        self._finalised = False

    # -- markers -------------------------------------------------------------

    def hit(self, source: str) -> None:
        """Served without calling the provider: redis | memory | database |
        disk | negative."""
        if source not in SERVED_FROM_VALUES or source == "upstream":
            raise ValueError(f"invalid cache source: {source!r}")
        self.served_from = source
        self._stop_clock()

    def upstream(self, response: Any = None, *, provider_status: str = None) -> None:
        """Called the provider. Pass the httpx.Response and the status is read
        from it, including provider-level errors returned inside a 200 body."""
        self.served_from = "upstream"
        if response is not None:
            self.http_status = getattr(response, "status_code", None)
            if provider_status is None:
                provider_status = _extract_provider_status(response)
        self.provider_status = provider_status
        self._stop_clock()

    def failed(self, exc: BaseException) -> None:
        """Transport-level failure — timeout, DNS, connection reset. Nothing was
        billed because nothing completed."""
        if self.served_from is None:
            self.served_from = "upstream"
        self.error = f"{type(exc).__name__}: {exc}"[:500]
        self._stop_clock()

    def _stop_clock(self) -> None:
        if self.latency_ms is None:
            self.latency_ms = int((time.perf_counter() - self._started) * 1000)

    # -- derivation ----------------------------------------------------------

    def _is_billable(self) -> bool:
        if self.served_from != "upstream":
            return False
        if self.error is not None:
            return False
        if self.http_status is not None and self.http_status >= 400:
            return False
        if self.provider_status in NON_BILLABLE_STATUSES:
            return False
        return self.sku is not None

    async def _to_row(self) -> dict:
        billable = self._is_billable()
        cost = Decimal("0")
        if billable:
            rates = await _load_rates()
            rate = rates.get(self.sku)
            if rate:
                cost = rate["unit_cost_usd"]
        ctx = self._ctx
        return {
            "ts": datetime.now(timezone.utc).isoformat(),
            "request_id": str(ctx["request_id"]) if ctx.get("request_id") else None,
            "provider": self.provider,
            "operation": self.operation,
            "sku": self.sku,
            "served_from": self.served_from or "upstream",
            "billable": billable,
            "est_cost_usd": str(cost),
            "http_status": self.http_status,
            "provider_status": self.provider_status,
            "latency_ms": self.latency_ms,
            "user_id": str(ctx["user_id"]) if ctx.get("user_id") else None,
            "client_ip": ctx.get("client_ip"),
            "app_version": ctx.get("app_version"),
            "platform": ctx.get("platform"),
            "cache_key": (self.cache_key or None) and self.cache_key[:255],
            "params_digest": self.params_digest,
            "error": self.error,
        }


def _extract_provider_status(response: Any) -> Optional[str]:
    """Read the provider's own status out of a response body.

    Google returns HTTP 200 with `"status": "REQUEST_DENIED"` for an invalid
    key, so HTTP status alone would mark a failed call as billable. Places API
    (New) instead returns an `error` object.
    """
    try:
        body = response.json()
    except Exception:
        return None
    if not isinstance(body, dict):
        return None
    if "status" in body and isinstance(body["status"], str):
        return body["status"][:32]
    err = body.get("error")
    if isinstance(err, dict):
        return str(err.get("status") or err.get("code") or "ERROR")[:32]
    return None


@asynccontextmanager
async def track(
    provider: str,
    operation: str,
    *,
    sku: Optional[str] = None,
    cache_key: Optional[str] = None,
    params: Optional[dict] = None,
):
    """Record one API operation.

        async with telemetry.track("google_maps", "findplacefromtext",
                                   sku="find_place_atmosphere",
                                   cache_key=key) as t:
            hit = await cache.get(key)
            if hit is not None:
                t.hit("redis")
                return hit
            resp = await client.get(url, params=params)
            t.upstream(resp)
            return resp

    Identity (user, request_id, app version) is read from the request context,
    so it never needs passing in. If the block exits without a marker being set
    the row is still written, marked upstream with no status — an unmarked call
    is a bug and should be visible rather than silently absent.
    """
    digest = _digest(params) if params else None
    rec = _Recorder(provider, operation, sku, cache_key, digest,
                    request_context.snapshot())
    try:
        yield rec
    except BaseException as exc:
        rec.failed(exc)
        raise
    finally:
        try:
            await _emit(await rec._to_row())
        except Exception as e:  # never propagate out of telemetry
            _stats["dropped_redis_down"] += 1
            logger.debug("telemetry emit failed: %s", e)


@contextmanager
def track_sync(
    provider: str,
    operation: str,
    *,
    sku: Optional[str] = None,
    cache_key: Optional[str] = None,
):
    """Synchronous counterpart to `track()`, for blocking call sites.

    `google_lens_service` uses a sync `httpx.Client` inside plain `def`
    methods, so it cannot enter an async context manager. Rather than leave a
    whole service uninstrumented, this variant writes straight to the
    in-process buffer that the async flusher already drains first on every
    cycle — no sync Redis client, no reaching for a running event loop.

    Cost is not resolved here: `_load_rates()` needs a database round trip.
    Sync call sites are currently unbilled scraping endpoints, so the row
    carries volume and outcome with `est_cost_usd = 0`. Give a sync call site a
    real SKU and the cost would need resolving in the flusher instead.
    """
    rec = _Recorder(provider, operation, sku, cache_key, None,
                    request_context.snapshot())
    try:
        yield rec
    except BaseException as exc:
        rec.failed(exc)
        raise
    finally:
        try:
            billable = rec._is_billable()
            ctx = rec._ctx
            row = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "request_id": str(ctx["request_id"]) if ctx.get("request_id") else None,
                "provider": rec.provider,
                "operation": rec.operation,
                "sku": rec.sku,
                "served_from": rec.served_from or "upstream",
                "billable": billable,
                "est_cost_usd": "0",
                "http_status": rec.http_status,
                "provider_status": rec.provider_status,
                "latency_ms": rec.latency_ms,
                "user_id": str(ctx["user_id"]) if ctx.get("user_id") else None,
                "client_ip": ctx.get("client_ip"),
                "app_version": ctx.get("app_version"),
                "platform": ctx.get("platform"),
                "cache_key": (rec.cache_key or None) and rec.cache_key[:255],
                "params_digest": None,
                "error": rec.error,
            }
            if len(_fallback) == _fallback.maxlen:
                _stats["dropped_queue_full"] += 1
            _fallback.append(json.dumps(row, default=str))
            _stats["emitted"] += 1
        except Exception as e:
            logger.debug("telemetry sync emit failed: %s", e)


def _digest(params: dict) -> str:
    """Stable hash of normalised params, for grouping identical calls."""
    try:
        clean = {k: v for k, v in sorted(params.items()) if k not in ("key", "apiKey", "access_token")}
        return hashlib.sha256(
            json.dumps(clean, sort_keys=True, default=str).encode()
        ).hexdigest()
    except Exception:
        return ""


# ── Write path ──────────────────────────────────────────────────────────────

def _spend_keys(row: dict) -> list[tuple[str, int]]:
    """Redis counter keys to bump for a billable row, with their TTLs.

    Spend has to be readable *now* to enforce a budget — the hourly rollup lags
    by up to five minutes, and a runaway client can spend a lot in five minutes.
    These counters are the real-time view; the rollups remain the reportable one.
    """
    day = row["ts"][:10]                 # YYYY-MM-DD
    month = row["ts"][:7]                # YYYY-MM
    keys = [
        (f"spend:day:{day}", 3 * 86400),
        (f"spend:month:{month}", 40 * 86400),
    ]
    if row.get("user_id"):
        keys.append((f"spend:user:{row['user_id']}:{day}", 2 * 86400))
    return keys


async def _emit(row: dict) -> None:
    """Queue a row. Redis first, in-process deque as a grace buffer."""
    payload = json.dumps(row, default=str)
    try:
        client = _get_redis()
        depth = await client.lpush(QUEUE_KEY, payload)
        _stats["emitted"] += 1

        # Bump the live spend counters in the same round trip as the enqueue.
        if row.get("billable") and float(row.get("est_cost_usd") or 0) > 0:
            cost = float(row["est_cost_usd"])
            pipe = client.pipeline()
            for key, ttl in _spend_keys(row):
                pipe.incrbyfloat(key, cost)
                pipe.expire(key, ttl)
            await pipe.execute()
        if depth > MAX_QUEUE_LEN:
            # Trim from the tail: keep the newest, drop the oldest. A backed-up
            # queue means the flusher is stuck, and recent data is worth more.
            await client.ltrim(QUEUE_KEY, 0, MAX_QUEUE_LEN - 1)
            _stats["dropped_queue_full"] += 1
    except Exception:
        if len(_fallback) == _fallback.maxlen:
            _stats["dropped_redis_down"] += 1
        _fallback.append(payload)


_INSERT_SQL = text("""
    INSERT INTO api_events (
        ts, request_id, provider, operation, sku, served_from, billable,
        est_cost_usd, http_status, provider_status, latency_ms, user_id,
        client_ip, app_version, platform, cache_key, params_digest, error
    ) VALUES (
        :ts, :request_id, :provider, :operation, :sku, :served_from, :billable,
        :est_cost_usd, :http_status, :provider_status, :latency_ms, :user_id,
        :client_ip, :app_version, :platform, :cache_key, :params_digest, :error
    )
""")


def _coerce_row(row: dict) -> dict:
    """Restore native types lost to the JSON round trip.

    Rows are serialised to JSON for the Redis queue, which flattens datetimes,
    UUIDs and Decimals to strings. asyncpg binds parameters by type and rejects
    strings for timestamptz/uuid/numeric columns, so they are rebuilt here —
    once, in the flusher, rather than at every call site.
    """
    row["ts"] = datetime.fromisoformat(row["ts"])
    for key in ("request_id", "user_id"):
        value = row.get(key)
        row[key] = uuid.UUID(value) if value else None
    row["est_cost_usd"] = Decimal(row.get("est_cost_usd") or "0")
    return row


async def flush_once(batch_size: int = 500) -> int:
    """Drain up to `batch_size` rows into Postgres. Returns rows written."""
    rows: list[dict] = []

    # Drain the in-process fallback first so ordering stays roughly intact.
    while _fallback and len(rows) < batch_size:
        rows.append(json.loads(_fallback.popleft()))

    if len(rows) < batch_size:
        try:
            client = _get_redis()
            raw = await client.rpop(QUEUE_KEY, batch_size - len(rows))
            if raw:
                for item in (raw if isinstance(raw, list) else [raw]):
                    try:
                        rows.append(json.loads(item))
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            logger.debug("telemetry: redis drain failed: %s", e)

    if not rows:
        return 0

    prepared = []
    for row in rows:
        try:
            prepared.append(_coerce_row(row))
        except Exception as e:
            # A single malformed row must not cost us the whole batch.
            _stats["flush_errors"] += 1
            logger.debug("telemetry: dropping unparseable row: %s", e)

    if not prepared:
        return 0

    try:
        from app.core.database import async_session
        async with async_session() as session:
            await session.execute(_INSERT_SQL, prepared)
            await session.commit()
        _stats["flushed"] += len(prepared)
        return len(prepared)
    except Exception as e:
        _stats["flush_errors"] += 1
        logger.warning("telemetry: flush failed, %d rows lost: %s", len(prepared), e)
        return 0


async def flusher_loop(interval_seconds: float = 5.0) -> None:
    """Background drain. Started once at application startup."""
    logger.info("telemetry flusher started (interval=%ss)", interval_seconds)
    while True:
        try:
            written = await flush_once()
            # Queue is backed up — keep draining rather than sleeping.
            if written >= 500:
                continue
        except asyncio.CancelledError:
            await flush_once()  # best-effort drain on shutdown
            raise
        except Exception as e:
            logger.warning("telemetry flusher error: %s", e)
        await asyncio.sleep(interval_seconds)


async def ensure_partitions(months_ahead: int = 2) -> None:
    """Create this month's partition and the next few.

    Without a partition an INSERT fails outright, so this runs at startup and
    is cheap enough to leave in the daily maintenance path.
    """
    try:
        from app.core.database import async_session
        async with async_session() as session:
            for offset in range(months_ahead + 1):
                await session.execute(
                    text(
                        "SELECT ensure_api_events_partition("
                        "(date_trunc('month', now()) + make_interval(months => :m))::date)"
                    ),
                    {"m": offset},
                )
            await session.commit()
    except Exception as e:
        logger.warning("telemetry: partition check failed: %s", e)
