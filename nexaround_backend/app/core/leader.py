"""Cross-worker coordination, for work that must not happen twice.

Uvicorn runs `WEB_CONCURRENCY` independent processes. Each one imports this
application from scratch, so everything in the startup path — creating tables,
seeding settings, starting the telemetry loops — runs once per worker unless
something stops it. Most of that is harmless when repeated; some of it is not:

  * `create_all` in two processes at once can race on CREATE TABLE and leave a
    half-built schema behind.
  * The rollup loop aggregates `api_events` into hourly buckets. Two of them
    double-count.
  * The alert loop notifies. Two of them notify twice.

Postgres advisory locks are used rather than a flag in a table because they are
tied to the connection: a worker that dies releases its lock without having to
clean up after itself.

Two shapes, because the two problems are different:

  [serialised]  `guard()` — a blocking lock around one-off startup work. Every
                worker runs the work, one at a time. Correct when the work is
                idempotent but not concurrency-safe, which is exactly what
                `create_all` and the settings seeding are.

  [elected]     `try_become_leader()` — a lock held for the life of the process.
                Exactly one worker wins and runs the singleton loops; the losers
                skip them. If the winner dies, its connection drops, the lock is
                released, and the worker uvicorn respawns in its place acquires
                it on startup.
"""
import logging
from contextlib import asynccontextmanager
from typing import Optional

from sqlalchemy import text

from app.core.database import engine

logger = logging.getLogger(__name__)

# Advisory lock keys share one namespace per database, so these are arbitrary
# but must stay fixed and distinct from anything else that uses the mechanism.
_STARTUP_LOCK_KEY = 8410572301
_LEADER_LOCK_KEY = 8410572302

# The elected worker's connection. Module-level because the lock lasts only as
# long as the session holding it — letting this be garbage-collected would hand
# leadership to whichever worker asked next.
_leader_conn = None


@asynccontextmanager
async def guard(key: int = _STARTUP_LOCK_KEY):
    """Run a block with every other worker held at the door.

    Blocking, not `try_`: the point is that the second worker proceeds *after*
    the first has finished, not that it skips the work. On a fresh database the
    loser still needs the schema to exist before it serves traffic.
    """
    async with engine.begin() as conn:
        await conn.execute(text("SELECT pg_advisory_lock(:k)"), {"k": key})
        try:
            yield
        finally:
            await conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": key})


async def try_become_leader() -> bool:
    """Claim the singleton role for this process, without waiting.

    Returns True at most once per database. The connection is deliberately
    never returned to the pool: a session-level advisory lock lives on its
    session, so releasing the connection would release the lock.
    """
    global _leader_conn
    if _leader_conn is not None:
        return True
    conn = await engine.connect()
    try:
        won = await conn.scalar(
            text("SELECT pg_try_advisory_lock(:k)"), {"k": _LEADER_LOCK_KEY}
        )
    except Exception:
        await conn.close()
        raise
    if not won:
        await conn.close()
        return False
    _leader_conn = conn
    return True


async def release_leadership() -> None:
    """Drop the lock on shutdown so a restarting worker can take it at once.

    Without this the lock still goes when the connection does, but only once
    Postgres notices the socket is gone — long enough that a fast restart can
    come up leaderless.
    """
    global _leader_conn
    conn, _leader_conn = _leader_conn, None
    if conn is None:
        return
    try:
        await conn.execute(
            text("SELECT pg_advisory_unlock(:k)"), {"k": _LEADER_LOCK_KEY}
        )
    except Exception as e:  # a dying connection has already released it
        logger.debug("leader unlock failed, connection likely gone: %s", e)
    finally:
        await conn.close()


def is_leader() -> bool:
    return _leader_conn is not None
