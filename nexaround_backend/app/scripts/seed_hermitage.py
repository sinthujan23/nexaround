"""
Seed the Hermitage Museum masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_hermitage

This script:
  1. Creates the Museum row for "State Hermitage Museum" if it doesn't exist.
  2. Reads hermitage_reconstructed.xlsx (place it next to manage.py or pass path).
  3. Inserts all 100 masterpieces with their duration flags.

Requires: openpyxl, pandas
    pip install openpyxl pandas
"""

import asyncio
import os
import sys
import uuid

import pandas as pd
from sqlalchemy import select

# ── Bootstrap the app so models / settings are importable ────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base  # noqa: E402
from app.models.museum import Museum, MuseumMasterpiece  # noqa: E402


EXCEL_PATH = os.environ.get(
    "HERMITAGE_XLSX",
    os.path.join(os.path.dirname(__file__), "..", "..", "hermitage_reconstructed.xlsx"),
)

MUSEUM_META = {
    "slug": "state-hermitage-museum",
    "name": "State Hermitage Museum",
    "city": "Saint Petersburg",
    "country": "Russia",
    "annual_visitors": 3_846_375,
    "rank": 19,
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Winter_Palace_Panorama_3.jpg/1280px-Winter_Palace_Panorama_3.jpg",
    "ticket_url": "https://www.hermitageshop.org/tickets/",
    "latitude": 59.9398,
    "longitude": 30.3146,
}


async def seed():
    # Ensure tables exist (in case migration hasn't been run yet)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        # 1. Upsert museum
        result = await session.execute(
            select(Museum).where(Museum.slug == MUSEUM_META["slug"])
        )
        museum = result.scalar_one_or_none()
        if museum is None:
            museum = Museum(id=uuid.uuid4(), **MUSEUM_META)
            session.add(museum)
            await session.flush()
            print(f"✅ Created museum: {museum.name} (id={museum.id})")
        else:
            print(f"ℹ️  Museum already exists: {museum.name} (id={museum.id})")

        # 2. Read Excel
        if not os.path.exists(EXCEL_PATH):
            print(f"❌ Excel file not found at: {EXCEL_PATH}")
            print("   Set HERMITAGE_XLSX env var or place the file next to manage.py")
            return

        df = pd.read_excel(EXCEL_PATH)
        print(f"📄 Read {len(df)} rows from {EXCEL_PATH}")

        # 3. Clear existing masterpieces for idempotence
        existing = await session.execute(
            select(MuseumMasterpiece).where(
                MuseumMasterpiece.museum_id == museum.id
            )
        )
        for old in existing.scalars().all():
            await session.delete(old)
        await session.flush()

        # 4. Insert masterpieces
        count = 0
        for _, row in df.iterrows():
            mp = MuseumMasterpiece(
                id=uuid.uuid4(),
                museum_id=museum.id,
                rank=int(row["Rank"]),
                building=str(row.get("Building", "")),
                room_gallery=str(row.get("Room / Gallery", "")),
                must_see_item=str(row.get("Must-See Item", "")),
                artist=str(row.get("Artist / Creator", "")) or None,
                category=str(row.get("Category", "")),
                description=str(row.get("Why It's in the Top 100", "")) or None,
                included_5h=row.get("5h") == "✓",
                included_1d=row.get("1D") == "✓",
                included_2d=row.get("2D") == "✓",
            )
            session.add(mp)
            count += 1

        await session.commit()
        print(f"✅ Inserted {count} masterpieces for {museum.name}")


if __name__ == "__main__":
    asyncio.run(seed())
