"""
Seed the British Museum masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_british_museum
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

BRITISH_MUSEUM_XLSX = os.environ.get(
    "BRITISH_MUSEUM_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "British_Museum_Itineraries_5h_1d_2d.xlsx"))
)

def guess_category(item_name, gallery, floor):
    item_lower = item_name.lower()
    gallery_lower = (gallery or "").lower()
    floor_lower = (floor or "").lower()
    
    if any(x in item_lower or x in gallery_lower for x in ["sculpture", "statue", "mummy", "sarcophagus", "rosetta", "amenhotep", "lamassu", "parthenon", "marbles", "relief"]):
        return "Classical Sculpture"
    if any(x in item_lower or x in gallery_lower for x in ["painting", "print", "draw", "canvas"]):
        return "Painting"
    if any(x in item_lower or x in gallery_lower for x in ["gold", "sutton hoo", "treasure", "relic", "jewel", "enamel", "pottery", "urn", "vase"]):
        return "Decorative Arts"
    if any(x in item_lower or x in gallery_lower for x in ["reading room", "great court", "clock", "architecture"]):
        return "Architecture"
    return "British Museum Masterpiece"

def process_excel(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Excel file not found at: {file_path}")
        return None

    xl = pd.ExcelFile(file_path)
    merged = {}

    item_col = "Must-See Highlight"
    floor_col = "Floor"
    room_col = "Room"
    gallery_col = "Gallery"

    # 1. Read 5-Hour Itinerary
    if "5-Hour Itinerary" in xl.sheet_names:
        df_5h = pd.read_excel(xl, "5-Hour Itinerary")
        for idx, row in df_5h.iterrows():
            item_name = str(row[item_col]).strip()
            key = item_name.lower()
            rank_val = int(row.get('#', idx + 1))
            floor_val = str(row.get(floor_col, "")).strip()
            room_val = str(row.get(room_col, "")).strip()
            gallery_val = str(row.get(gallery_col, "")).strip()
            
            # Format room_gallery as "Room X - Gallery Name"
            if room_val and gallery_val and room_val.lower() != gallery_val.lower():
                room_gallery_val = f"Room {room_val} - {gallery_val}"
            else:
                room_gallery_val = room_val or gallery_val
                
            merged[key] = {
                "rank": rank_val,
                "building": floor_val,
                "room_gallery": room_gallery_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category(item_name, gallery_val, floor_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }

    # 2. Read 1-Day Itinerary
    if "1-Day Itinerary" in xl.sheet_names:
        df_1d = pd.read_excel(xl, "1-Day Itinerary")
        for idx, row in df_1d.iterrows():
            item_name = str(row[item_col]).strip()
            key = item_name.lower()
            rank_val = int(row.get('#', idx + 1))
            floor_val = str(row.get(floor_col, "")).strip()
            room_val = str(row.get(room_col, "")).strip()
            gallery_val = str(row.get(gallery_col, "")).strip()
            
            if room_val and gallery_val and room_val.lower() != gallery_val.lower():
                room_gallery_val = f"Room {room_val} - {gallery_val}"
            else:
                room_gallery_val = room_val or gallery_val

            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": rank_val,
                    "building": floor_val,
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category(item_name, gallery_val, floor_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": True,
                    "included_2d": False
                }

    # 3. Read 2-Day Itinerary
    if "2-Day Itinerary" in xl.sheet_names:
        df_2d = pd.read_excel(xl, "2-Day Itinerary")
        for idx, row in df_2d.iterrows():
            item_name = str(row[item_col]).strip()
            key = item_name.lower()
            rank_val = int(row.get('#', idx + 1))
            floor_val = str(row.get(floor_col, "")).strip()
            room_val = str(row.get(room_col, "")).strip()
            gallery_val = str(row.get(gallery_col, "")).strip()
            day_val = str(row.get('Day', "1")).strip()
            
            if room_val and gallery_val and room_val.lower() != gallery_val.lower():
                room_gallery_val = f"Room {room_val} - {gallery_val}"
            else:
                room_gallery_val = room_val or gallery_val
                
            # Prefix building with Day 1 / Day 2 to make it clear in timeline
            building_prefix = f"Day {day_val} - {floor_val}" if day_val else floor_val

            if key in merged:
                merged[key]["included_2d"] = True
            else:
                merged[key] = {
                    "rank": rank_val,
                    "building": building_prefix,
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category(item_name, gallery_val, floor_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": False,
                    "included_2d": True
                }

    # Sort merged masterpieces by 5H inclusion first, then 1D, then 2D, then rank
    sorted_items = list(merged.values())
    sorted_items.sort(key=lambda x: (not x["included_5h"], not x["included_1d"], not x["included_2d"], x["rank"]))

    # Assign clean sequential rank from 1 to N
    for index, item in enumerate(sorted_items, 1):
        item["rank"] = index

    return sorted_items

async def seed_museum(slug, excel_path):
    async with async_session() as session:
        # Find museum
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()
        if not museum:
            print(f"❌ Museum with slug '{slug}' not found in database. Run seed_all_museums first.")
            return

        print(f"⚙️  Processing details for {museum.name} ({slug})...")

        # Parse Excel data
        masterpieces = process_excel(excel_path)
        if not masterpieces:
            return

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
    await seed_museum("british-museum", BRITISH_MUSEUM_XLSX)

if __name__ == "__main__":
    asyncio.run(main())
