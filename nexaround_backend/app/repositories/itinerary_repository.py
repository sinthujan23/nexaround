import uuid
from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.itinerary import Itinerary

class ItineraryRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_user(self, user_id: uuid.UUID) -> List[Itinerary]:
        result = await self.db.execute(
            select(Itinerary).where(Itinerary.user_id == user_id).order_by(Itinerary.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_by_id(self, itinerary_id: uuid.UUID, user_id: uuid.UUID) -> Optional[Itinerary]:
        result = await self.db.execute(
            select(Itinerary).where(Itinerary.id == itinerary_id, Itinerary.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def create(self, itinerary: Itinerary) -> Itinerary:
        self.db.add(itinerary)
        await self.db.commit()
        await self.db.refresh(itinerary)
        return itinerary

    async def update(self, itinerary: Itinerary) -> Itinerary:
        await self.db.commit()
        await self.db.refresh(itinerary)
        return itinerary

    async def delete(self, itinerary: Itinerary) -> None:
        await self.db.delete(itinerary)
        await self.db.commit()
