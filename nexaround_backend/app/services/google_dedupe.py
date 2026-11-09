"""Pay Google once when the same question is asked twice at the same moment.

The caches in front of Google only help once an answer has been stored, and
storing it takes the whole round trip: the Google call, the database writes,
then the cache write. A second identical request arriving inside that window
finds nothing and buys the same answer again. On 3–5 Nov 2026 that was 17% of
all Nearby Search spend (776 of 4,595 calls): the app's home screen sends its
whole set of searches twice in about one open in four, and every pair was the
same user, the same search, usually less than a second apart.

`shared()` closes that window. The first request buys the answer and keeps it
for a couple of minutes; an identical request that arrives meanwhile waits for
that answer instead of buying its own. It works across the API's worker
processes, because the "already buying" note and the answer live in Redis.

Nothing a user sees changes: the same question gets the same answer, just once.
If Redis is unreachable every request simply buys its own, as before.
"""
import asyncio
import hashlib
import json
import logging
from typing import Awaitable, Callable, Optional

from app.services import place_cache_service, telemetry

logger = logging.getLogger(__name__)

# Long enough to cover the slowest real round trip plus the second request's
# gap (all duplicates seen were under 5 s apart); short enough that nothing
# but an immediate repeat ever reads it.
_ANSWER_TTL_S = 120
# Upper bound on one Google round trip. A request that waits longer than this
# for another process's answer stops waiting and buys its own.
_BUYING_TTL_S = 30
_POLL_S = 0.1

# Requests in this process that are buying right now, by key.
_inflight: dict[str, asyncio.Future] = {}


def request_key(kind: str, **parts) -> str:
    """A stable key for one exact Google request."""
    raw = json.dumps(parts, sort_keys=True, default=str)
    return f"gdedupe:{kind}:{hashlib.sha1(raw.encode()).hexdigest()}"


async def _get_answer(key: str) -> Optional[list]:
    try:
        raw = await place_cache_service._get_client().get(f"{key}:answer")
    except Exception as e:
        logger.debug("dedupe answer read failed: %s", e)
        return None
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


async def _put_answer(key: str, answer: list) -> None:
    try:
        await place_cache_service._get_client().set(
            f"{key}:answer", json.dumps(answer), ex=_ANSWER_TTL_S
        )
    except Exception as e:
        logger.debug("dedupe answer write failed: %s", e)


async def _record_shared(operation: str, telemetry_key: Optional[str]) -> None:
    """Log the request that did NOT go to Google, so the cost dashboard counts
    it as served without a purchase."""
    async with telemetry.track("internal", operation, cache_key=telemetry_key) as t:
        t.hit("redis")


async def _buy_or_wait(
    key: str,
    buy: Callable[[], Awaitable[list]],
    operation: str,
    telemetry_key: Optional[str],
) -> list:
    redis = place_cache_service._get_client()
    buying_key = f"{key}:buying"
    try:
        we_buy = await redis.set(buying_key, "1", nx=True, ex=_BUYING_TTL_S)
    except Exception as e:
        logger.debug("dedupe note failed, buying directly: %s", e)
        return await buy()

    if not we_buy:
        # Another worker process is buying this exact answer: wait for it.
        loop = asyncio.get_running_loop()
        deadline = loop.time() + _BUYING_TTL_S
        while loop.time() < deadline:
            await asyncio.sleep(_POLL_S)
            answer = await _get_answer(key)
            if answer is not None:
                await _record_shared(operation, telemetry_key)
                return answer
            try:
                if not await redis.exists(buying_key):
                    break
            except Exception:
                break
        # It finished in the gap between the two reads above, or it failed.
        answer = await _get_answer(key)
        if answer is not None:
            await _record_shared(operation, telemetry_key)
            return answer
        try:
            we_buy = await redis.set(buying_key, "1", nx=True, ex=_BUYING_TTL_S)
        except Exception:
            we_buy = False

    try:
        answer = await buy()
        await _put_answer(key, answer)
        return answer
    finally:
        if we_buy:
            try:
                await redis.delete(buying_key)
            except Exception:
                pass


async def shared(
    key: str,
    buy: Callable[[], Awaitable[list]],
    *,
    operation: str,
    telemetry_key: Optional[str] = None,
) -> list:
    """Return `buy()`'s answer, buying it at most once for identical requests
    that overlap in time. `buy` must return a JSON-serialisable list and do its
    own upstream telemetry; the requests it saves are logged here."""
    # 1. This process is already buying it.
    leader = _inflight.get(key)
    if leader is not None:
        try:
            answer = await asyncio.shield(leader)
        except asyncio.CancelledError:
            if not leader.cancelled():
                raise  # this request itself was cancelled
            answer = None  # the buyer gave up; buy it ourselves below
        if answer is not None:
            await _record_shared(operation, telemetry_key)
            return answer

    # 2. Some process bought it moments ago.
    answer = await _get_answer(key)
    if answer is not None:
        await _record_shared(operation, telemetry_key)
        return answer

    # 3. Buy it (or wait on another process that is), and let identical
    #    requests in this process wait on us.
    future: asyncio.Future = asyncio.get_running_loop().create_future()
    # Retrieve any exception so an unawaited failure is not logged as an
    # "exception never retrieved" warning.
    future.add_done_callback(lambda f: f.cancelled() or f.exception())
    _inflight[key] = future
    try:
        answer = await _buy_or_wait(key, buy, operation, telemetry_key)
    except asyncio.CancelledError:
        future.cancel()
        raise
    except BaseException as e:
        future.set_exception(e)
        raise
    else:
        future.set_result(answer)
        return answer
    finally:
        if _inflight.get(key) is future:
            del _inflight[key]
