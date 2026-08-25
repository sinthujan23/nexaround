from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings

# SQLAlchemy's defaults (pool_size=5, max_overflow=10) cap the app at 15
# connections, which the request fan-out overruns: every request authenticates,
# so every request holds a connection for its whole life, and a single AR screen
# opens seven category calls plus the banded ones at once. Past 15 the rest
# queue for pool_timeout and then fail with
# "QueuePool limit of size 5 overflow 10 reached" — seen as intermittent 500s.
# 50 is comfortable against Postgres's max_connections of 100.
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    pool_size=20,
    max_overflow=30,
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
