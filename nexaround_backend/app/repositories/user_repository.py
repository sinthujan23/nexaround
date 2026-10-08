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

    async def list_users(
        self,
        skip: int = 0,
        limit: int = 20,
        search_query: Optional[str] = None,
        status: Optional[str] = None,
        verification: Optional[str] = None,
        date_filter: Optional[str] = None,
        start_from: Optional[str] = None,
        end_to: Optional[str] = None,
        sort_order: Optional[str] = "desc"
    ) -> tuple[list[User], int]:
        """List users with pagination, optional search, and filters."""
        from datetime import datetime, timezone, timedelta, date as d_date
        from sqlalchemy import func
        
        query = select(User)
        count_query = select(func.count()).select_from(User)
        
        if search_query:
            search = f"%{search_query}%"
            query = query.where(User.email.ilike(search) | User.display_name.ilike(search))
            count_query = count_query.where(User.email.ilike(search) | User.display_name.ilike(search))

        if status == "active":
            query = query.where(User.is_active.is_(True))
            count_query = count_query.where(User.is_active.is_(True))
        elif status == "suspended":
            query = query.where(User.is_active.is_(False))
            count_query = count_query.where(User.is_active.is_(False))

        if verification == "verified":
            query = query.where(User.is_verified.is_(True))
            count_query = count_query.where(User.is_verified.is_(True))
        elif verification == "unverified":
            query = query.where(User.is_verified.is_(False))
            count_query = count_query.where(User.is_verified.is_(False))

        # Sri Lanka Standard Time (Asia/Colombo, UTC+5:30)
        try:
            from zoneinfo import ZoneInfo
            tz_sl = ZoneInfo("Asia/Colombo")
        except Exception:
            tz_sl = timezone(timedelta(hours=5, minutes=30))

        if date_filter:
            now_sl = datetime.now(tz_sl)
            if date_filter == "today":
                d_start = now_sl.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
                query = query.where(User.created_at >= d_start)
                count_query = count_query.where(User.created_at >= d_start)
            elif date_filter == "this_week":
                d_start = (now_sl - timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
                query = query.where(User.created_at >= d_start)
                count_query = count_query.where(User.created_at >= d_start)
            elif date_filter == "this_month":
                d_start = (now_sl - timedelta(days=30)).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
                query = query.where(User.created_at >= d_start)
                count_query = count_query.where(User.created_at >= d_start)

        if start_from:
            try:
                s_date = d_date.fromisoformat(start_from.strip())
                s_dt = datetime(s_date.year, s_date.month, s_date.day, 0, 0, 0, tzinfo=tz_sl).astimezone(timezone.utc)
                query = query.where(User.created_at >= s_dt)
                count_query = count_query.where(User.created_at >= s_dt)
            except (ValueError, TypeError):
                pass

        if end_to:
            try:
                e_date = d_date.fromisoformat(end_to.strip())
                e_dt = datetime(e_date.year, e_date.month, e_date.day, 23, 59, 59, 999999, tzinfo=tz_sl).astimezone(timezone.utc)
                query = query.where(User.created_at <= e_dt)
                count_query = count_query.where(User.created_at <= e_dt)
            except (ValueError, TypeError):
                pass
            
        # Get total count
        total_result = await self.db.execute(count_query)
        total = total_result.scalar_one_or_none() or 0
        
        # Order and paginate
        order_clause = User.created_at.asc() if sort_order == "asc" else User.created_at.desc()
        query = query.order_by(order_clause).offset(skip).limit(limit)
        result = await self.db.execute(query)
        users = list(result.scalars().all())
        
        return users, total
