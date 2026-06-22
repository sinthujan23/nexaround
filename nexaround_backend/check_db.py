import asyncio
import sys
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.models.travel_story import TravelStory

async def check():
    db_url = "postgresql+asyncpg://nexaround:nexaround@db:5432/nexaround"
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        result = await session.execute(
            select(TravelStory).order_by(TravelStory.created_at.desc()).limit(5)
        )
        stories = result.scalars().all()
        for s in stories:
            print(f"Story ID: {s.id}")
            print(f"  Location: {s.location_name}")
            print(f"  Category: {s.category}")
            print(f"  Desc: {s.description}")
            print(f"  Image URL: {s.image_url}")
            print(f"  Image URLs: {s.image_urls}")
            print("-" * 40)

if __name__ == "__main__":
    asyncio.run(check())
