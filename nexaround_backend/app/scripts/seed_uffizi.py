"""
Seed the Uffizi Gallery masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_uffizi
"""

import asyncio
import os
import sys
import uuid
import pandas as pd
from sqlalchemy import select

# Bootstrap the app so models / settings are importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base
from app.models.museum import Museum, MuseumMasterpiece

UFFIZI_XLSX = os.environ.get(
    "UFFIZI_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Uffizi_Gallery_5-Hour_and_1-Day_Itineraries.xlsx"))
)

def guess_category_uffizi(item_name, hall, artist):
    item_lower = item_name.lower()
    hall_lower = (hall or "").lower()
    artist_lower = (artist or "").lower()
    
    if "sculpture" in item_lower or "statue" in item_lower or "bust" in item_lower or "venus de' medici" in item_lower:
        return "Classical Sculpture"
    if "botticelli" in artist_lower or "da vinci" in artist_lower or "michelangelo" in artist_lower or "raphael" in artist_lower or "lippi" in artist_lower or "angelico" in artist_lower or "giotto" in artist_lower or "cimabue" in artist_lower or "duccio" in artist_lower or "pier" in artist_lower or "uccello" in artist_lower:
        return "Renaissance Painting"
    if "caravaggio" in artist_lower or "gentileschi" in artist_lower or "baroque" in hall_lower:
        return "Baroque Painting"
    if "titian" in artist_lower or "tintoretto" in artist_lower or "veronese" in artist_lower:
        return "Renaissance Painting"
    if "painting" in item_lower or "portrait" in item_lower or "madonna" in item_lower or "tondo" in item_lower:
        return "Renaissance Painting"
    return "Renaissance Painting"

def process_uffizi(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Uffizi Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    if "5-Hour Itinerary" in xl.sheet_names:
        df = pd.read_excel(xl, "5-Hour Itinerary")
        for idx, row in df.iterrows():
            item_name = str(row["Masterpiece"]).strip()
            artist_val = str(row.get("Artist", "")).strip()
            if artist_val == "\u2014" or not artist_val or artist_val == "nan":
                artist_val = None
            room_gallery_val = str(row.get("Hall / Gallery", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("#", idx + 1)),
                "building": "Uffizi Gallery",
                "room_gallery": room_gallery_val,
                "must_see_item": item_name,
                "artist": artist_val,
                "category": guess_category_uffizi(item_name, room_gallery_val, artist_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    if "1-Day Top 40" in xl.sheet_names:
        df = pd.read_excel(xl, "1-Day Top 40")
        for idx, row in df.iterrows():
            item_name = str(row["Masterpiece"]).strip()
            artist_val = str(row.get("Artist", "")).strip()
            if artist_val == "\u2014" or not artist_val or artist_val == "nan":
                artist_val = None
            room_gallery_val = str(row.get("Hall / Gallery", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("#", idx + 1)),
                    "building": "Uffizi Gallery",
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": artist_val,
                    "category": guess_category_uffizi(item_name, room_gallery_val, artist_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": True,
                    "included_2d": False
                }
                
    sorted_items = list(merged.values())
    sorted_items.sort(key=lambda x: (not x["included_5h"], x["rank"]))
    for index, item in enumerate(sorted_items, 1):
        item["rank"] = index
    return sorted_items

async def seed_museum(slug, masterpieces):
    async with async_session() as session:
        # Find museum
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()
        if not museum:
            print(f"❌ Museum with slug '{slug}' not found in database. Run seed_all_museums first.")
            return

        print(f"⚙️  Seeding details for {museum.name} ({slug})...")

        # Clear existing masterpieces for idempotency
        existing = await session.execute(
            select(MuseumMasterpiece).where(MuseumMasterpiece.museum_id == museum.id)
        )
        for old in existing.scalars().all():
            await session.delete(old)
        await session.flush()

        # Insert new masterpieces
        count = 0
        for item in masterpieces:
            mp = MuseumMasterpiece(
                id=uuid.uuid4(),
                museum_id=museum.id,
                rank=item["rank"],
                building=item["building"],
                room_gallery=item["room_gallery"],
                must_see_item=item["must_see_item"],
                artist=item["artist"],
                category=item["category"],
                description=item["description"],
                included_5h=item["included_5h"],
                included_1d=item["included_1d"],
                included_2d=item["included_2d"]
            )
            session.add(mp)
            count += 1

        await session.commit()
        print(f"✅ Successfully seeded {count} masterpieces for {museum.name}!")

async def main():
    uffizi_items = process_uffizi(UFFIZI_XLSX)
    if uffizi_items:
        await seed_museum("galleria-degli-uffizi", uffizi_items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
