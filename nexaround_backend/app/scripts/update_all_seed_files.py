"""
Script to update all individual museum seed scripts with their cached Google Places API photo URLs.
"""
import asyncio
import os
import sys
from sqlalchemy import select

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine
from app.models.museum import Museum

async def main():
    async with async_session() as session:
        result = await session.execute(select(Museum.slug, Museum.image_url))
        mapping = dict(result.all())
        print("Current DB Image URLs:")
        for k, v in mapping.items():
            print(f"  {k}: {v[:60]}...")

if __name__ == "__main__":
    asyncio.run(main())
