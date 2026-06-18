import asyncio
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.models.travel_story import TravelStory

async def check_stories():
    db_url = "postgresql+asyncpg://nexaround:nexaround@localhost:5432/nexaround"
    engine = create_async_engine(db_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        result = await session.execute(select(TravelStory))
        stories = result.scalars().all()
        print(f"Total stories in database: {len(stories)}")
        for s in stories:
            print(f"- ID: {s.id}, Location: {s.location_name}, Category: {s.category}, Desc: {s.description}")

if __name__ == "__main__":
    asyncio.run(check_stories())
