from typing import List
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.category_repository import CategoryRepository
from app.schemas.category import CategoryResponse


class CategoryService:
    """Business logic for Category management."""

    def __init__(self, db: AsyncSession):
        self.repo = CategoryRepository(db)

    async def get_categories(self) -> List[CategoryResponse]:
        """Get all active categories."""
        categories = await self.repo.get_all()
        return [CategoryResponse.model_validate(c) for c in categories]
