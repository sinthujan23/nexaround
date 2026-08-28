import uuid
from typing import List, Optional
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.excluded_keyword import ExcludedKeyword


class ExcludedKeywordRepository:
    """Data access layer for ExcludedKeyword operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_all(self) -> List[ExcludedKeyword]:
        result = await self.db.execute(
            select(ExcludedKeyword).order_by(ExcludedKeyword.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_by_keyword(self, keyword: str) -> Optional[ExcludedKeyword]:
        """Case-insensitive, because matching is.

        `place_bands.matches_excluded_keyword` searches with IGNORECASE, so
        "Pigeon" and "pigeon" hide exactly the same places. Comparing exactly
        here let both be stored, leaving the admin list showing two rows that
        do one job — and deleting either one hiding nothing.
        """
        result = await self.db.execute(
            select(ExcludedKeyword).where(
                func.lower(ExcludedKeyword.keyword) == keyword.lower()
            )
        )
        return result.scalar_one_or_none()

    async def create(self, keyword: str) -> ExcludedKeyword:
        row = ExcludedKeyword(keyword=keyword)
        self.db.add(row)
        await self.db.commit()
        await self.db.refresh(row)
        return row

    async def delete(self, keyword_id: uuid.UUID) -> bool:
        result = await self.db.execute(
            select(ExcludedKeyword).where(ExcludedKeyword.id == keyword_id)
        )
        row = result.scalar_one_or_none()
        if row is None:
            return False
        await self.db.delete(row)
        await self.db.commit()
        return True
