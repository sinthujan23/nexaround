import uuid
from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.discovery_history import DiscoveryHistory


class DiscoveryHistoryRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_user(self, user_id: uuid.UUID) -> List[DiscoveryHistory]:
        result = await self.db.execute(
            select(DiscoveryHistory)
            .where(DiscoveryHistory.user_id == user_id)
            .order_by(DiscoveryHistory.created_at.desc())
            .limit(20)
        )
        return list(result.scalars().all())

    async def create(self, item: DiscoveryHistory) -> DiscoveryHistory:
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        return item
