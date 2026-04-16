import uuid
from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.category import Category


class CategoryRepository:
    """Data access layer for Category operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_all(self, only_active: bool = True) -> List[Category]:
        """Get all categories sorted by sort_order."""
        query = select(Category).order_by(Category.sort_order)
        if only_active:
            query = query.where(Category.is_active == True)
        
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_by_id(self, category_id: uuid.UUID) -> Optional[Category]:
        """Get a category by ID."""
        result = await self.db.execute(
            select(Category).where(Category.id == category_id)
        )
        return result.scalar_one_or_none()
