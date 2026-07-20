"""
Seed the American Museum of Natural History masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_amnh
"""

import asyncio
import os
import sys
import uuid
import pandas as pd
from sqlalchemy import select

# Bootstrap the app so models / settings are importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session
from app.models.museum import Museum, MuseumMasterpiece

AMNH_XLSX = os.environ.get(
    "AMNH_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "American Museum of Natural History_5hr_and_1day_Itineraries.xlsx"))
)

def guess_category_amnh(item_name, location):
    item_lower = item_name.lower()
    loc_lower = (location or "").lower()
    
    if "dinosaur" in loc_lower or "rex" in item_lower or "saur" in item_lower or "fossil" in item_lower:
        return "Dinosaurs & Fossils"
    if "mammal" in loc_lower or "primate" in loc_lower or "ocean life" in loc_lower or "biodiversity" in loc_lower:
        return "Mammals & Biodiversity"
    if "space" in loc_lower or "meteorite" in loc_lower or "planet" in loc_lower or "sphere" in loc_lower or "universe" in loc_lower:
        return "Earth & Space"
    if "people" in loc_lower or "human origins" in loc_lower or "mexico" in loc_lower or "asian" in loc_lower or "african" in loc_lower:
        return "Human Cultures & Origins"
    if "gems" in loc_lower or "mineral" in loc_lower or "geodes" in loc_lower:
        return "Gems & Minerals"
    if "bird" in loc_lower:
        return "Birds"
    if "reptile" in loc_lower or "amphibian" in loc_lower:
        return "Reptiles & Amphibians"
    if "insect" in loc_lower:
        return "Insects"
    return "Exhibits"

def process_amnh(file_path):
    if not os.path.exists(file_path):
        print(f"❌ AMNH Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    sheet_5h = "5 Hour Itinerary"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            item_name = str(row.get("Exhibit / Highlight", "")).strip()
            building_val = str(row.get("Floor", "")).strip()
            room_gallery_val = str(row.get("Location", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop", idx + 1)),
                "building": f"Floor {building_val}" if building_val and building_val != "nan" else "",
                "room_gallery": room_gallery_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category_amnh(item_name, room_gallery_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    sheet_1d = "1 Day Itinerary"
    if sheet_1d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_1d)
        for idx, row in df.iterrows():
            item_name = str(row.get("Exhibit / Highlight", "")).strip()
            building_val = str(row.get("Floor", "")).strip()
            room_gallery_val = str(row.get("Location", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": f"Floor {building_val}" if building_val and building_val != "nan" else "",
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category_amnh(item_name, room_gallery_val),
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
    items = process_amnh(AMNH_XLSX)
    if items:
        await seed_museum("american-museum-of-natural-history", items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
