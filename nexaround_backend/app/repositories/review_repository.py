import uuid
from typing import List, Tuple
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.review import Review
from app.models.user import User

class ReviewRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_attraction(self, attraction_id: uuid.UUID) -> List[Review]:
        result = await self.db.execute(
            select(Review).where(Review.attraction_id == attraction_id).order_by(Review.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_rating_summary(self, attraction_id: uuid.UUID) -> Tuple[float, int]:
        result = await self.db.execute(
            select(
                func.avg(Review.rating).label("average"),
                func.count(Review.id).label("count")
            ).where(Review.attraction_id == attraction_id)
        )
        row = result.one()
        return float(row.average or 0.0), int(row.count or 0)

    async def create(self, review: Review) -> Review:
        self.db.add(review)
        await self.db.commit()
        await self.db.refresh(review)
        return review

    async def delete(self, review: Review) -> None:
        await self.db.delete(review)
        await self.db.commit()
