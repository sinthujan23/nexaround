"""
Seed the National Museum of China masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_china
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

CHINA_XLSX = os.environ.get(
    "CHINA_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "National_Museum_of_China_5-Hour_(27)_and_1-Day_(50)_Itineraries.xlsx"))
)

def guess_category_china(item_name, exhibition, category):
    item_lower = item_name.lower()
    exhibition_lower = (exhibition or "").lower()
    category_lower = (category or "").lower()
    
    if "buddhist sculpture" in exhibition_lower or "sculpture" in item_lower or "figurine" in item_lower or "statue" in item_lower:
        return "Sculpture"
    if "porcelain" in exhibition_lower or "porcelain" in category_lower:
        return "Decorative Arts"
    if "jade" in exhibition_lower or "jade" in item_lower:
        return "Antiquities"
    if "bronze" in item_lower or "ding" in item_lower or "zun" in item_lower or "chime" in item_lower or "ancient china" in exhibition_lower:
        return "Antiquities"
    if "currency" in exhibition_lower or "currencies" in category_lower:
        return "Antiquities"
    if "calligraphy" in exhibition_lower or "painting" in exhibition_lower or "painting" in item_lower or "founding ceremony" in item_lower:
        return "Painting"
    if "costume" in exhibition_lower or "adornment" in exhibition_lower or "food culture" in exhibition_lower or "folk art" in category_lower:
        return "Decorative Arts"
    if "rare books" in exhibition_lower or "stele rubbings" in exhibition_lower or "rare books" in category_lower:
        return "Decorative Arts"
    if "state gifts" in exhibition_lower or "foreign artifacts" in exhibition_lower:
        return "Decorative Arts"
    return "Antiquities"

def process_china(file_path):
    if not os.path.exists(file_path):
        print(f"❌ China museum Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    # 1. 5-Hour Itinerary
    sheet_5h = "5-Hour Itinerary (27 Stops)"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            item_name = str(row["Must-See Highlight"]).strip()
            exhibition_val = str(row.get("Gallery / Exhibition", "")).strip()
            category_val = str(row.get("Collection Category", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("#", idx + 1)),
                "building": exhibition_val,
                "room_gallery": category_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category_china(item_name, exhibition_val, category_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    # 2. 1-Day Itinerary
    sheet_1d = "1-Day Itinerary (50 Stops)"
    if sheet_1d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_1d)
        for idx, row in df.iterrows():
            item_name = str(row["Must-See Highlight"]).strip()
            exhibition_val = str(row.get("Gallery / Exhibition", "")).strip()
            category_val = str(row.get("Collection Category", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("#", idx + 1)),
                    "building": exhibition_val,
                    "room_gallery": category_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category_china(item_name, exhibition_val, category_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": True,
                    "included_2d": False
                }
                
    # Sort merged masterpieces by 5H inclusion first, then by rank to keep index logical
    sorted_items = list(merged.values())
    sorted_items.sort(key=lambda x: (not x["included_5h"], x["rank"]))
    
    # Assign clean sequential rank from 1 to N
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
    china_items = process_china(CHINA_XLSX)
    if china_items:
        await seed_museum("national-museum-of-china", china_items)

if __name__ == "__main__":
    asyncio.run(main())
