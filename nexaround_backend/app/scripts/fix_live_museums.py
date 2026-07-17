"""
One-off script to delete 6 museums and fix Acropolis museum image in production.

Usage:
    python -m app.scripts.fix_live_museums
"""

import asyncio
import os
import sys

# Bootstrap the app
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
from app.core.database import async_session, engine
from sqlalchemy import delete, update
from app.models.museum import Museum

MUSEUMS_TO_REMOVE = [
    "21st-century-museum-of-contemporary-art",
    "national-science-and-technology-museum",
    "national-museum-in-krakow",
    "louis-vuitton-foundation",
    "kaohsiung-museum-of-fine-arts",
    "palacio-de-cristal-del-retiro"
]

NEW_ACROPOLIS_IMAGE = "https://images.unsplash.com/photo-1555992828-ca4dbe41d294?q=80&w=1200"

async def fix_db():
    async with async_session() as session:
        # 1. Delete the museums
        print(f"Deleting the following museums: {MUSEUMS_TO_REMOVE}")
        await session.execute(
            delete(Museum).where(Museum.slug.in_(MUSEUMS_TO_REMOVE))
        )
        print("Museums deleted (if they existed).")

        # 2. Update Acropolis image
        print("Updating Acropolis image...")
        await session.execute(
            update(Museum)
            .where(Museum.slug == "acropolis-museum")
            .values(image_url=NEW_ACROPOLIS_IMAGE)
        )
        print("Acropolis image updated.")

        # Commit changes
        await session.commit()
        print("✅ Database successfully fixed!")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(fix_db())
