import uuid
from typing import List, Optional
from sqlalchemy import select
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
        result = await self.db.execute(
            select(ExcludedKeyword).where(ExcludedKeyword.keyword == keyword)
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
