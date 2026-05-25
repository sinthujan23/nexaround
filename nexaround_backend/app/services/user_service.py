import uuid
from typing import List, Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.user_repository import UserRepository
from app.models.user import User
from app.core.exceptions import NotFoundException


class UserService:
    """Business logic for User management."""

    def __init__(self, db: AsyncSession):
        self.repo = UserRepository(db)

    async def list_users(
        self, 
        page: int = 1, 
        page_size: int = 20, 
        search_query: Optional[str] = None
    ) -> Tuple[List[User], int]:
        """List users with pagination."""
        skip = (page - 1) * page_size
        users, total = await self.repo.list_users(
            skip=skip, 
            limit=page_size, 
            search_query=search_query
        )
        return users, total
        
    async def get_user(self, user_id: uuid.UUID) -> User:
        """Get a user by ID."""
        user = await self.repo.get_by_id(user_id)
        if not user:
            raise NotFoundException(detail="User not found")
        return user

    async def toggle_active_status(self, user_id: uuid.UUID) -> User:
        """Toggle user's active status."""
        user = await self.get_user(user_id)
        user.is_active = not user.is_active
        return await self.repo.update(user)
        
    async def verify_user(self, user_id: uuid.UUID) -> User:
        """Set user as verified."""
        user = await self.get_user(user_id)
        user.is_verified = True
        return await self.repo.update(user)
