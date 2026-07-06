from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.museum import Museum, MuseumMasterpiece


class MuseumRepository:

    @staticmethod
    async def get_all(db: AsyncSession) -> list[Museum]:
        """Return all museums ordered by global rank."""
        result = await db.execute(
            select(Museum).order_by(Museum.rank.asc())
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_by_slug(db: AsyncSession, slug: str) -> Museum | None:
        """Return a single museum with all masterpieces eagerly loaded."""
        result = await db.execute(
            select(Museum)
            .where(Museum.slug == slug)
            .options(selectinload(Museum.masterpieces))
        )
        return result.scalar_one_or_none()

    @staticmethod
    async def get_itinerary(
        db: AsyncSession, slug: str, duration: str
    ) -> tuple[Museum | None, list[MuseumMasterpiece]]:
        """Return masterpieces filtered by duration (5h / 1d / 2d)."""
        museum = await MuseumRepository.get_by_slug(db, slug)
        if museum is None:
            return None, []

        # Map duration string to column
        col_map = {
            "5h": MuseumMasterpiece.included_5h,
            "1d": MuseumMasterpiece.included_1d,
            "2d": MuseumMasterpiece.included_2d,
        }
        col = col_map.get(duration.lower())
        if col is None:
            return museum, []

        result = await db.execute(
            select(MuseumMasterpiece)
            .where(
                MuseumMasterpiece.museum_id == museum.id,
                col == True,
            )
            .order_by(MuseumMasterpiece.rank.asc())
        )
        return museum, list(result.scalars().all())

    @staticmethod
    async def get_masterpiece_count(db: AsyncSession, museum_id) -> int:
        result = await db.execute(
            select(func.count())
            .select_from(MuseumMasterpiece)
            .where(MuseumMasterpiece.museum_id == museum_id)
        )
        return result.scalar_one()
