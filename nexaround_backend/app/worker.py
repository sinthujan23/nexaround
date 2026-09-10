"""The background process. Runs alongside the API from the same image:

    python -m app.worker

It owns two kinds of work that do not belong on a request path:

  * Queued jobs — today, Odyssey generation. Pulled from Redis via
    `app.core.job_queue`, at most `ODYSSEY_MAX_JOBS` at a time.
  * The telemetry singleton loops (rollup, partition maintenance, alerts).
    These used to run in whichever uvicorn worker won an advisory-lock
    election at startup. A dedicated process *is* the singleton, so the
    election is kept only as a guard against someone scaling this service to
    two replicas — the second one simply runs jobs and not loops.

What it does not do: create tables or seed settings. That stays with the API's
startup, which is what runs first on a fresh deploy (`depends_on` is not
ordering enough for that, but the API blocks serving until it is done, and
the worker's first job cannot arrive before the API is serving).

Shutdown is a SIGTERM from compose. Jobs in flight are cancelled and left in
the `processing` list; `recover_orphans` puts them back at the front of the
queue on the next start, so a deploy mid-generation costs the user a restart
of that generation rather than a spinner that never ends.
"""
import asyncio
import logging
import os
import signal

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("app.worker")


async def main() -> None:
    # Every model module must be imported before any query runs, or
    # relationship targets referenced by string fail to resolve.
    import app.models  # noqa: F401
    from app.core import job_queue, leader
    from app.core.database import engine
    from app.services import (
        google_places_client,
        odyssey_jobs,
        telemetry,
        telemetry_alerts,
        telemetry_rollup,
    )

    max_jobs = max(1, int(os.getenv("ODYSSEY_MAX_JOBS", "3")))

    # Same guard as the API: the flusher below writes to this month's
    # partition, and two processes creating it at once race.
    async with leader.guard():
        await telemetry.ensure_partitions()

    tasks: list[asyncio.Task] = []
    # The worker emits telemetry (every Gemini/SerpApi call inside a job goes
    # through telemetry.track) and holds its own in-process grace buffer for
    # when Redis is down, so it drains like the API does.
    tasks.append(asyncio.create_task(telemetry.flusher_loop()))

    if await leader.try_become_leader():
        tasks.extend([
            asyncio.create_task(telemetry_rollup.rollup_loop()),
            asyncio.create_task(telemetry_rollup.maintenance_loop()),
            asyncio.create_task(telemetry_alerts.alert_loop()),
        ])
        logger.info("telemetry singleton loops started")
    else:
        logger.warning("another worker holds the leader lock; running jobs only")

    await job_queue.recover_orphans()

    consumer = asyncio.create_task(job_queue.run_worker(
        {odyssey_jobs.JOB_NAME: odyssey_jobs.run_job},
        max_jobs=max_jobs,
    ))

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    await stop.wait()
    logger.info("shutting down")

    consumer.cancel()
    for t in tasks:
        t.cancel()
    await asyncio.gather(consumer, *tasks, return_exceptions=True)
    # Whatever the flusher had buffered when it was cancelled.
    await telemetry.flush_once()
    await leader.release_leadership()
    await google_places_client.aclose_http_client()
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
