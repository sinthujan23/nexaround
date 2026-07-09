"""
Seed the Grand Egyptian Museum masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_grand_egyptian_museum
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

GEM_XLSX = os.environ.get(
    "GEM_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Grand_Egyptian_Museum_Itineraries.xlsx"))
)

def guess_category_gem(item_name, collection):
    item_lower = item_name.lower()
    coll_lower = (collection or "").lower()
    
    if "boat" in coll_lower or "boat" in item_lower:
        return "Khufu Solar Boat"
    if "tutankhamun" in coll_lower or "burial" in item_lower or "mask" in item_lower or "golden" in item_lower or "coffin" in item_lower or "throne" in item_lower:
        return "Tutankhamun Treasury"
    if "obelisk" in coll_lower or "obelisk" in item_lower or "column" in item_lower or "doorway" in item_lower or "pyramidion" in item_lower:
        return "Architecture & Monuments"
    if "statue" in item_lower or "colossus" in item_lower or "sphinx" in item_lower or "colossal" in item_lower:
        return "Colossal Sculpture"
    return "Egyptian Antiquities"

def process_gem(file_path):
    if not os.path.exists(file_path):
        print(f"❌ GEM Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    sheet_5h = "5-Hour Itinerary"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            item_name = str(row["Official Object Name"]).strip()
            building_val = str(row.get("Gallery / Collection", "")).strip()
            room_gallery_val = building_val  # No separate wing, reuse collection
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop #", idx + 1)),
                "building": building_val,
                "room_gallery": room_gallery_val,
                "must_see_item": item_name,
                "artist": "Ancient Egyptian",
                "category": guess_category_gem(item_name, building_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    sheet_1d = "1 Day itinerary"
    if sheet_1d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_1d)
        for idx, row in df.iterrows():
            item_name = str(row["Official Object Name"]).strip()
            building_val = str(row.get("Gallery / Collection", "")).strip()
            room_gallery_val = building_val
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop #", idx + 1)),
                    "building": building_val,
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": "Ancient Egyptian",
                    "category": guess_category_gem(item_name, building_val),
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
    gem_items = process_gem(GEM_XLSX)
    if gem_items:
        await seed_museum("grand-egyptian-museum", gem_items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
