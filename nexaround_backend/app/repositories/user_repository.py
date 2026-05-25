import uuid
from typing import Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import User


class UserRepository:
    """Data access layer for User operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        """Get a user by their UUID."""
        result = await self.db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()

    async def get_by_email(self, email: str) -> Optional[User]:
        """Get a user by their email address."""
        result = await self.db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    async def create(self, user: User) -> User:
        """Create a new user."""
        self.db.add(user)
        await self.db.flush()
        await self.db.refresh(user)
        return user

    async def update(self, user: User) -> User:
        """Update an existing user."""
        await self.db.flush()
        await self.db.refresh(user)
        return user

    async def delete(self, user: User) -> None:
        """Delete a user."""
        await self.db.delete(user)
        await self.db.flush()

    async def list_users(self, skip: int = 0, limit: int = 20, search_query: Optional[str] = None) -> tuple[list[User], int]:
        """List users with pagination and optional search."""
        from sqlalchemy import func
        
        query = select(User)
        count_query = select(func.count()).select_from(User)
        
        if search_query:
            search = f"%{search_query}%"
            query = query.where(User.email.ilike(search) | User.display_name.ilike(search))
            count_query = count_query.where(User.email.ilike(search) | User.display_name.ilike(search))
            
        # Get total count
        total_result = await self.db.execute(count_query)
        total = total_result.scalar_one_or_none() or 0
        
        # Get users
        query = query.order_by(User.created_at.desc()).offset(skip).limit(limit)
        result = await self.db.execute(query)
        users = list(result.scalars().all())
        
        return users, total
