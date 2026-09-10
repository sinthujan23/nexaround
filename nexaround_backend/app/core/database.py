import os

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings

# SQLAlchemy's defaults (pool_size=5, max_overflow=10) cap the app at 15
# connections, which the request fan-out overruns: every request authenticates,
# so every request holds a connection for its whole life, and a single AR screen
# opens seven category calls plus the banded ones at once. Past 15 the rest
# queue for pool_timeout and then fail with
# "QueuePool limit of size 5 overflow 10 reached" — seen as intermittent 500s.
#
# The budget is for the *application as a whole*, not per process. Uvicorn runs
# one event loop per worker and each worker builds its own engine, so a pool
# sized per process silently multiplies by the worker count: the 20+30 that fit
# comfortably under Postgres's max_connections of 100 became 100 the moment a
# second worker existed, and pool timeouts would have turned into hard
# "FATAL: too many connections" refusals — strictly worse than what they
# replaced. Dividing a fixed budget means worker count can change without
# anyone remembering to re-derive this.
#
# 80 of the 97 usable connections (100 less the 3 reserved for superusers),
# leaving room for psql, alembic and the admin panel.
#
# The budget is split between containers by DB_CONNECTION_BUDGET, set in
# docker-compose.yml: the API gets 70, the background worker 10. The worker
# runs at most a few jobs at once and each one touches Postgres only at its
# start and end, so 10 is generous; without the override a second container
# would build its own 80 and the two together would exceed max_connections.
_WORKERS = max(1, int(os.getenv("WEB_CONCURRENCY", "1")))
_CONNECTION_BUDGET = max(10, int(os.getenv("DB_CONNECTION_BUDGET", "80")))
_per_worker = max(10, _CONNECTION_BUDGET // _WORKERS)
# Steady pool vs burst headroom. The overflow half absorbs the fan-out spikes;
# the steady half is what stays connected between them.
_POOL_SIZE = max(5, int(_per_worker * 0.4))
_MAX_OVERFLOW = _per_worker - _POOL_SIZE

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    pool_size=_POOL_SIZE,
    max_overflow=_MAX_OVERFLOW,
    pool_timeout=30,
    # Recycle below any idle-connection reaper, and check liveness on checkout,
    # so a connection dropped while idle surfaces as a retry rather than an error.
    pool_recycle=1800,
    pool_pre_ping=True,
)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    """Dependency that provides a database session per request."""
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
