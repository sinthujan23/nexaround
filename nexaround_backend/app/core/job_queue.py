"""A small reliable job queue on the Redis instance the app already runs.

Odyssey generation takes 35–120 s of waiting on Gemini and SerpApi. It used to
run as a FastAPI BackgroundTask, which has three problems that only show up in
production:

  * It lives in the API process's memory. `docker compose restart api` — every
    deploy — drops any generation in flight, and the itinerary sits at
    "generating" forever. The app polls a spinner that never ends.
  * It shares the API's event loop and CPU cap. A burst of generations slows
    every other endpoint on the box.
  * Nothing bounds how many run at once, so twenty taps are twenty concurrent
    Gemini chains.

The queue here is the Redis "reliable queue" pattern, the same idiom the
telemetry pipeline already uses for its event buffer:

    enqueue:  LPUSH  pending
    worker:   BLMOVE pending → processing        (atomic; job is never lost)
              run it
              LREM   processing                   (done, in either direction)
    startup:  LMOVE  processing → pending, repeat (crash/deploy recovery)

Not arq or Celery: arq pins `redis<6` and this image runs redis-py 8, and
Celery brings a broker abstraction that is pure overhead for one job type on
one box. This is ~100 lines and every line is visible.

Payloads are JSON, not pickle, so a job written by one version of the code can
be read by the next without an unpickling surprise mid-deploy. Anything that
is not JSON-native (UUIDs, dates) arrives at the job as a string, and the job
coerces what it needs.
"""
import asyncio
import json
import logging
import time
import uuid
from typing import Any, Awaitable, Callable, Optional

import redis.asyncio as aioredis

from app.core import request_context
from app.core.config import settings

logger = logging.getLogger(__name__)

# One namespace for the whole queue so a `KEYS jobs:*` shows everything, and
# keyed by database name for the same reason telemetry's keys are: a test run
# pointed at a scratch database must not have its jobs picked up by the
# production worker.
def _ns() -> str:
    try:
        name = settings.DATABASE_URL.rsplit("/", 1)[-1].split("?")[0]
        return name or "default"
    except Exception:
        return "default"


def pending_key() -> str:
    return f"jobs:{_ns()}:pending"


def processing_key() -> str:
    return f"jobs:{_ns()}:processing"


def heartbeat_key() -> str:
    return f"jobs:{_ns()}:worker:heartbeat"


HEARTBEAT_TTL_SECONDS = 30
# How long one BLMOVE waits for a job before returning empty and looping. Also
# how long a SIGTERM can take to be noticed, so keep it short.
POLL_TIMEOUT_SECONDS = 5

_redis: Optional[aioredis.Redis] = None


def _get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True,
            # redis-py 8 defaults socket_timeout to 5 s — the same as the
            # blocking poll below, so the client gave up on the socket a
            # moment before the server sent its empty reply and every idle
            # poll logged a timeout. The socket must outlast the server-side
            # block.
            socket_timeout=POLL_TIMEOUT_SECONDS + 10,
        )
    return _redis


# ── Producer side (called from the API) ─────────────────────────────────────

def encode(name: str, kwargs: dict, ctx: Optional[dict] = None) -> str:
    """Serialise a job. `ctx` is the request context to restore in the worker,
    so the worker's telemetry rows carry the same request_id, user and route
    as the API call that caused them — the api_events grouping that makes an
    Odyssey's cost attributable stays intact across the process boundary."""
    return json.dumps({
        "id": str(uuid.uuid4()),
        "name": name,
        "kwargs": kwargs,
        "ctx": ctx if ctx is not None else request_context.snapshot(),
        "enqueued_at": time.time(),
    }, default=str)


def decode(raw: str) -> dict:
    return json.loads(raw)


async def enqueue(name: str, **kwargs: Any) -> str:
    """Queue a job. Returns the job id. Raises if Redis is unreachable — the
    caller decides whether to fall back to running in-process."""
    payload = encode(name, kwargs)
    await _get_redis().lpush(pending_key(), payload)
    return decode(payload)["id"]


async def stats() -> dict:
    """Depths plus how long since the worker last checked in. Surfaced by
    /health: a growing `pending` with a stale heartbeat means the worker is
    down and Odysseys are queuing, not generating."""
    try:
        r = _get_redis()
        pending, processing, beat = await asyncio.gather(
            r.llen(pending_key()), r.llen(processing_key()), r.get(heartbeat_key()),
        )
        seen = round(time.time() - float(beat), 1) if beat else None
        return {"pending": pending, "processing": processing,
                "worker_seen_seconds_ago": seen}
    except Exception as e:
        return {"error": str(e)[:120]}


# ── Consumer side (the worker process) ──────────────────────────────────────

JobFn = Callable[..., Awaitable[None]]


def restore_context(ctx: dict) -> None:
    """Rebuild the request ContextVars from the enqueued snapshot."""
    def _uuid(v):
        try:
            return uuid.UUID(str(v)) if v else None
        except ValueError:
            return None
    request_context.request_id_var.set(_uuid(ctx.get("request_id")) or uuid.uuid4())
    request_context.user_id_var.set(_uuid(ctx.get("user_id")))
    request_context.client_ip_var.set(ctx.get("client_ip"))
    request_context.app_version_var.set(ctx.get("app_version"))
    request_context.platform_var.set(ctx.get("platform"))
    request_context.route_var.set(ctx.get("route"))


async def recover_orphans() -> int:
    """Move anything left in `processing` back to `pending`.

    Called once at worker start. A job is in `processing` only while a worker
    is running it, so on startup that list can only hold what the previous
    worker was killed in the middle of. There is one worker, so nothing else
    could be racing us for these.
    """
    r = _get_redis()
    moved = 0
    # Pushed onto the *consuming* end of `pending`, so an interrupted job runs
    # before anything that was queued while the worker was down. Its user has
    # already waited once.
    while await r.lmove(processing_key(), pending_key(), "LEFT", "RIGHT"):
        moved += 1
    if moved:
        logger.warning("job_queue: requeued %d job(s) interrupted by the last shutdown", moved)
    return moved


async def _heartbeat_loop() -> None:
    r = _get_redis()
    while True:
        try:
            await r.set(heartbeat_key(), str(time.time()), ex=HEARTBEAT_TTL_SECONDS)
        except Exception as e:
            logger.debug("job_queue: heartbeat failed: %s", e)
        await asyncio.sleep(HEARTBEAT_TTL_SECONDS // 3)


async def run_worker(
    handlers: dict[str, JobFn],
    *,
    max_jobs: int = 3,
    poll_timeout: int = POLL_TIMEOUT_SECONDS,
) -> None:
    """Consume jobs until cancelled.

    `max_jobs` is the whole point of moving this out of the API: it is the
    number of Odyssey chains in flight at once, and therefore the ceiling on
    concurrent Gemini/SerpApi spend. Jobs beyond it wait in Redis rather than
    fan out.

    A job that raises is logged and dropped from `processing`; it is not
    retried here. Every handler already writes its own failure state
    (`status="failed"` with a reason) so the user sees an outcome either way,
    and re-running a job that just failed deterministically would only spend
    the same money twice. Interrupted jobs — the worker dying mid-run — are the
    case that *is* retried, via `recover_orphans` on the next start.
    """
    r = _get_redis()
    sem = asyncio.Semaphore(max_jobs)
    running: set[asyncio.Task] = set()
    beat = asyncio.create_task(_heartbeat_loop())

    async def _run(raw: str) -> None:
        cancelled = False
        async with sem:
            try:
                job = decode(raw)
                fn = handlers.get(job.get("name"))
                if fn is None:
                    logger.error("job_queue: no handler for %r, dropping", job.get("name"))
                    return
                restore_context(job.get("ctx") or {})
                waited = time.time() - float(job.get("enqueued_at") or time.time())
                logger.info("job %s %s starting (queued %.1fs)", job["name"], job["id"], waited)
                t0 = time.monotonic()
                await fn(**job["kwargs"])
                logger.info("job %s %s done in %.1fs", job["name"], job["id"], time.monotonic() - t0)
            except asyncio.CancelledError:
                # Shutdown. Leave the entry in `processing` so the next start
                # requeues it — this is the deploy-mid-generation case.
                cancelled = True
                raise
            except Exception:
                logger.exception("job_queue: job failed")
            finally:
                if not cancelled:
                    # Finished, in either direction: the entry is done with.
                    try:
                        await r.lrem(processing_key(), 1, raw)
                    except Exception as e:
                        logger.warning("job_queue: could not clear processing entry: %s", e)

    logger.info("job worker started (max_jobs=%d, queue=%s)", max_jobs, pending_key())
    try:
        while True:
            # Do not pull more than we can run: leaving the job in `pending`
            # while all slots are busy keeps the queue depth honest in /health.
            if sem.locked():
                await asyncio.sleep(0.5)
                continue
            try:
                raw = await r.blmove(
                    pending_key(), processing_key(), poll_timeout, "RIGHT", "LEFT",
                )
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.warning("job_queue: redis poll failed, retrying: %s", e)
                await asyncio.sleep(2)
                continue
            if raw is None:
                continue
            task = asyncio.create_task(_run(raw))
            running.add(task)
            task.add_done_callback(running.discard)
    finally:
        beat.cancel()
        for t in running:
            t.cancel()
        if running:
            await asyncio.gather(*running, return_exceptions=True)
