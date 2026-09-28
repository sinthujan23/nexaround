"""The one fetch engine every travel-data provider goes through.

An Odyssey waits on Gemini for 35–63 s and on Google Flights and Hotels for
5–17 s before that. A provider is only worth adding if it never makes that
wait longer and never makes a plan fail, so every call through `fetch()` gets,
in order:

1. **Redis first.** A fresh answer is served without calling out, and so is a
   remembered "nothing here" (a city with no tours), for its own shorter time.
2. **A circuit breaker.** A provider that keeps failing, or answers 429, is
   skipped for a while — shared through Redis, so every process stops together.
3. **Stale-while-revalidate.** An answer past its fresh time but inside its
   stale time is served at once while a new one is fetched in the background.
4. **Single-flight.** Identical requests in flight at the same moment share one
   upstream call.
5. **A hard time limit.** A slow provider returns nothing rather than holding
   the plan up.
6. **A pooled connection** per provider, kept open between calls, and a
   telemetry row for every call, hit or miss.

`fetch()` never raises. Every failure comes back as a `Fetched` with no data,
and the caller falls back to whatever the plan had without it.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
import weakref
from dataclasses import dataclass
from typing import Any, Callable, Optional

import httpx

from app.services import place_cache_service, telemetry

logger = logging.getLogger(__name__)

_KEY_PREFIX = "prov:v1"
_BREAKER_PREFIX = "prov:breaker"

# Consecutive failures that open the breaker, and how long it stays open.
BREAKER_FAILURES = 5
BREAKER_COOLDOWN_S = 10 * 60
# A 429 names its own wait in Retry-After; never believe more than an hour.
_MAX_RETRY_AFTER_S = 60 * 60

# Answers that are facts about the request, not failures of the provider:
# GetTransfer says 422 for a route it cannot serve, a catalogue 404s on a city
# it does not have. Remembered like any other empty answer.
EMPTY_STATUSES = frozenset({404, 422})


# ── Results ──────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Fetched:
    """What one `fetch()` produced.

    `source` is where the data came from: "redis" (fresh), "stale" (old, a new
    copy is on its way), "upstream" (just fetched), "negative" (a remembered
    empty answer) or "none" (nothing — see `error`).
    """
    data: Any = None
    source: str = "none"
    fetched_at: Optional[float] = None
    error: str = ""

    @property
    def ok(self) -> bool:
        return self.data is not None

    @property
    def empty(self) -> bool:
        """The provider answered, and the answer was "nothing here"."""
        return self.data is None and not self.error and self.source in ("upstream", "negative")


LIVE, RECENT, ESTIMATE = "live", "recent", "estimate"

# The app's three labels (odyssey.dart `priceConfidence`).
_CONFIDENCE = {LIVE: "Fixed", RECENT: "Typical", ESTIMATE: "Estimated"}


@dataclass(frozen=True)
class PriceQuote:
    """One price, in the shape every provider hands back.

    `freshness` says how far to trust it: LIVE is bookable now, RECENT was seen
    on the provider in the last few days, ESTIMATE is no provider's price.
    """
    amount: float
    currency: str
    source: str
    freshness: str
    basis: str = ""
    booking_url: str = ""
    fetched_at: Optional[float] = None

    def activity_fields(self) -> dict:
        """The fields an itinerary stop already carries.

        Written onto a stop, these show in every app build that exists today —
        no new model, no app release.
        """
        fields = {
            "cost": f"{self.currency.upper()} {self.amount:,.0f}",
            "price_source": self.source,
            "price_basis": self.basis,
            "price_confidence": _CONFIDENCE.get(self.freshness, "Estimated"),
        }
        if self.booking_url:
            fields["booking_url"] = self.booking_url
        return fields


# ── Connections ─────────────────────────────────────────────────────────────
# One client per provider per event loop. A client is bound to the loop it was
# made on, and the test suite runs each test on a fresh loop, so a single
# module-wide client would be handed to a loop that is already closed.

_clients: "weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, dict[str, httpx.AsyncClient]]" = (
    weakref.WeakKeyDictionary()
)


def _new_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        limits=httpx.Limits(max_connections=20, max_keepalive_connections=10, keepalive_expiry=60),
        headers={"User-Agent": "NexAround/1.0 (+https://nexaround.com)"},
        follow_redirects=True,
    )


def client_for(provider: str) -> httpx.AsyncClient:
    """The kept-open client for `provider` on the running loop."""
    per_loop = _clients.setdefault(asyncio.get_running_loop(), {})
    client = per_loop.get(provider)
    if client is None or client.is_closed:
        client = per_loop[provider] = _new_client()
    return client


# ── Circuit breaker ─────────────────────────────────────────────────────────

_open_until: dict[str, float] = {}
_failures: dict[str, int] = {}


def _breaker_key(provider: str) -> str:
    return f"{_BREAKER_PREFIX}:{provider}"


async def breaker_open(provider: str) -> bool:
    now = time.time()
    if now < _open_until.get(provider, 0.0):
        return True
    try:
        raw = await place_cache_service.get_raw(_breaker_key(provider))
        if raw:
            until = float(raw)
            if now < until:
                _open_until[provider] = until
                return True
    except Exception:
        pass
    return False


async def _trip(provider: str, cooldown_s: float, why: str) -> None:
    until = time.time() + cooldown_s
    _open_until[provider] = until
    _failures[provider] = 0
    logger.warning("[%s] %s — skipping it for %d s.", provider, why, int(cooldown_s))
    try:
        await place_cache_service.set_raw(_breaker_key(provider), f"{until:.0f}", ttl=int(cooldown_s))
    except Exception:
        pass


async def _failed(provider: str, why: str) -> None:
    n = _failures.get(provider, 0) + 1
    _failures[provider] = n
    if n >= BREAKER_FAILURES:
        await _trip(provider, BREAKER_COOLDOWN_S, f"{n} failures in a row ({why})")


def _succeeded(provider: str) -> None:
    _failures[provider] = 0


def _retry_after(resp: httpx.Response) -> float:
    try:
        seconds = float(resp.headers.get("Retry-After", ""))
    except ValueError:
        return BREAKER_COOLDOWN_S
    return max(1.0, min(seconds, _MAX_RETRY_AFTER_S))


# ── Cache ────────────────────────────────────────────────────────────────────
# Stored as {"at": epoch, "empty": bool, "data": ...} so the age of an answer
# is known when it is read, which is what lets one entry be fresh, then stale,
# then gone.

def cache_key(provider: str, operation: str, cache_params: dict) -> str:
    return f"{_KEY_PREFIX}:{provider}:{operation}:{telemetry._digest(cache_params)}"


async def _read(key: str) -> Optional[dict]:
    try:
        raw = await place_cache_service.get_raw(key)
        env = json.loads(raw) if raw else None
        return env if isinstance(env, dict) and "at" in env else None
    except Exception:
        return None


async def _write(key: str, data: Any, *, empty: bool, ttl: int) -> None:
    if ttl <= 0:
        return
    try:
        env = {"at": time.time(), "empty": empty, "data": None if empty else data}
        await place_cache_service.set_raw(key, json.dumps(env), ttl=int(ttl))
    except Exception as e:
        logger.debug("providers: cache write failed for %s: %s", key, e)


# ── Single-flight and background refresh ────────────────────────────────────

_inflight: "weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, dict[str, asyncio.Future]]" = (
    weakref.WeakKeyDictionary()
)
_background: set[asyncio.Task] = set()


async def _single_flight(key: str, factory: Callable[[], Any]) -> Fetched:
    flights = _inflight.setdefault(asyncio.get_running_loop(), {})
    waiting = flights.get(key)
    if waiting is not None:
        return await asyncio.shield(waiting)
    future: asyncio.Future = asyncio.get_running_loop().create_future()
    flights[key] = future
    try:
        result = await factory()
        future.set_result(result)
        return result
    finally:
        if not future.done():
            future.set_result(Fetched(error="cancelled"))
        flights.pop(key, None)


def _in_background(coro) -> None:
    task = asyncio.get_running_loop().create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)


# ── The fetch ────────────────────────────────────────────────────────────────

async def _record_hit(provider: str, operation: str, sku: Optional[str], key: str,
                      cache_params: dict, source: str) -> None:
    async with telemetry.track(provider, operation, sku=sku, cache_key=key,
                               params=cache_params) as t:
        t.hit(source)


async def fetch(
    provider: str,
    operation: str,
    *,
    url: str,
    cache_params: dict,
    fresh_ttl: int,
    stale_ttl: int = 0,
    empty_ttl: int = 0,
    timeout_s: float = 3.0,
    method: str = "GET",
    params: Any = None,
    headers: Optional[dict] = None,
    json_body: Any = None,
    parse: str = "json",
    transform: Optional[Callable[[Any], Any]] = None,
    is_empty: Optional[Callable[[Any], bool]] = None,
    sku: Optional[str] = None,
) -> Fetched:
    """Fetch through the cache, the breaker and the time limit. Never raises.

    `cache_params` names the answer: two requests with the same cache_params
    share it, so leave out anything that does not change the answer (the
    currency when it is converted locally, the minute of a pickup time) and
    never put a secret in it. `transform` turns the raw body into what is kept
    — make it small; it is what Redis stores. `is_empty` says when a kept
    answer means "nothing here", which is remembered for `empty_ttl`.
    """
    key = cache_key(provider, operation, cache_params)
    now = time.time()
    stale: Optional[dict] = None

    env = await _read(key)
    if env is not None:
        age = now - float(env["at"])
        if env.get("empty"):
            if age < empty_ttl:
                await _record_hit(provider, operation, sku, key, cache_params, "negative")
                return Fetched(source="negative", fetched_at=env["at"])
        elif age < fresh_ttl:
            await _record_hit(provider, operation, sku, key, cache_params, "redis")
            return Fetched(env.get("data"), "redis", env["at"])
        elif stale_ttl and age < stale_ttl:
            stale = env

    async def _go() -> Fetched:
        return await _upstream(
            provider, operation, key=key, url=url, cache_params=cache_params,
            fresh_ttl=fresh_ttl, stale_ttl=stale_ttl, empty_ttl=empty_ttl,
            timeout_s=timeout_s, method=method, params=params, headers=headers,
            json_body=json_body, parse=parse, transform=transform,
            is_empty=is_empty, sku=sku,
        )

    if await breaker_open(provider):
        if stale is not None:
            return Fetched(stale.get("data"), "stale", stale["at"])
        return Fetched(error="breaker_open")

    if stale is not None:
        await _record_hit(provider, operation, sku, key, cache_params, "redis")
        _in_background(_single_flight(key, _go))
        return Fetched(stale.get("data"), "stale", stale["at"])

    return await _single_flight(key, _go)


async def _upstream(
    provider: str, operation: str, *, key: str, url: str, cache_params: dict,
    fresh_ttl: int, stale_ttl: int, empty_ttl: int, timeout_s: float,
    method: str, params: Any, headers: Optional[dict], json_body: Any,
    parse: str, transform: Optional[Callable[[Any], Any]],
    is_empty: Optional[Callable[[Any], bool]], sku: Optional[str],
) -> Fetched:
    client = client_for(provider)
    try:
        async with telemetry.track(provider, operation, sku=sku, cache_key=key,
                                   params=cache_params) as t:
            # httpx's own timeout covers each phase; wait_for caps the whole.
            resp = await asyncio.wait_for(
                client.request(method, url, params=params, headers=headers,
                               json=json_body, timeout=timeout_s),
                timeout=timeout_s,
            )
            t.upstream(resp)
    except Exception as e:
        why = type(e).__name__
        await _failed(provider, why)
        logger.info("[%s] %s failed: %s%s", provider, operation, why, f": {e}" if str(e) else "")
        return Fetched(error="timeout" if isinstance(e, asyncio.TimeoutError) else why)

    status = resp.status_code
    if status == 429:
        await _trip(provider, _retry_after(resp), "rate limited (429)")
        return Fetched(error="rate_limited")
    if status in EMPTY_STATUSES:
        _succeeded(provider)
        await _write(key, None, empty=True, ttl=empty_ttl)
        return Fetched(source="upstream", fetched_at=time.time())
    if status != 200:
        # 401/403 is a bad or revoked key and will not fix itself; 5xx is the
        # provider having a bad minute. Either way, stop asking soon.
        await _failed(provider, f"HTTP {status}")
        logger.info("[%s] %s returned HTTP %s: %s", provider, operation, status, resp.text[:200])
        return Fetched(error=f"http_{status}")

    try:
        body = resp.json() if parse == "json" else resp.text
        data = transform(body) if transform else body
    except Exception as e:
        await _failed(provider, "unreadable response")
        logger.warning("[%s] %s: could not read the response: %s", provider, operation, e)
        return Fetched(error="bad_payload")

    _succeeded(provider)
    fetched_at = time.time()
    if data is None or (is_empty is not None and is_empty(data)):
        await _write(key, None, empty=True, ttl=empty_ttl)
        return Fetched(source="upstream", fetched_at=fetched_at)
    await _write(key, data, empty=False, ttl=max(fresh_ttl, stale_ttl))
    return Fetched(data, "upstream", fetched_at)
