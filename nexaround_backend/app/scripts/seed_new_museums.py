"""
Seed the China Science and Technology Museum and Natural History Museum into the database.

Usage (from the backend root):
    python -m app.scripts.seed_new_museums
"""

import asyncio
import os
import sys
import uuid
import pandas as pd
from sqlalchemy import select

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base
from app.models.museum import Museum, MuseumMasterpiece

APP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app"))
CHINA_SCIENCE_XLSX = os.path.join(APP_DIR, "China_Science_and_Technology_Museum_Itineraries.xlsx")
NATURAL_HISTORY_XLSX = os.path.join(APP_DIR, "Natural_History_Museum_London_Itineraries.xlsx")

def process_china_science(file_path):
    if not os.path.exists(file_path):
        print(f"❌ China Science museum Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    # 1. 5-Hour Itinerary
    if "5 Hour Itinerary" in xl.sheet_names:
        df = pd.read_excel(xl, "5 Hour Itinerary")
        for idx, row in df.iterrows():
            item_name = str(row["Highlight"]).strip()
            building_val = str(row.get("Floor / Exhibition Hall", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop", idx + 1)),
                "building": building_val,
                "room_gallery": "",
                "must_see_item": item_name,
                "artist": None,
                "category": "Science & Technology",
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    # 2. 1-Day Itinerary
    if "1 Day Itinerary" in xl.sheet_names:
        df = pd.read_excel(xl, "1 Day Itinerary")
        for idx, row in df.iterrows():
            item_name = str(row["Highlight"]).strip()
            building_val = str(row.get("Floor / Exhibition Hall", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": building_val,
                    "room_gallery": "",
                    "must_see_item": item_name,
                    "artist": None,
                    "category": "Science & Technology",
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

def process_natural_history(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Natural History Museum Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    # 1. 5-Hour Itinerary
    if "5 Hour Itinerary" in xl.sheet_names:
        df = pd.read_excel(xl, "5 Hour Itinerary")
        for idx, row in df.iterrows():
            item_name = str(row["Gallery / Highlight"]).strip()
            location = str(row.get("Location", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop", idx + 1)),
                "building": "Main Building",
                "room_gallery": location,
                "must_see_item": item_name,
                "artist": None,
                "category": "Natural History",
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    # 2. 1-Day Itinerary
    if "1 Day Itinerary" in xl.sheet_names:
        df = pd.read_excel(xl, "1 Day Itinerary")
        for idx, row in df.iterrows():
            item_name = str(row["Gallery / Highlight"]).strip()
            location = str(row.get("Location", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": "Main Building",
                    "room_gallery": location,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": "Natural History",
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

async def seed_museum(slug, masterpieces, updates):
    async with async_session() as session:
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()
        if not museum:
            print(f"❌ Museum with slug '{slug}' not found in database. Run seed_all_museums first.")
            return

        print(f"⚙️  Seeding details for {museum.name} ({slug})...")
        
        # Apply updates
        for k, v in updates.items():
            setattr(museum, k, v)

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
        print(f"✅ Successfully seeded {count} masterpieces and updated info for {museum.name}!")

async def main():
    china_science_items = process_china_science(CHINA_SCIENCE_XLSX)
    if china_science_items:
        china_science_updates = {
            "website": "https://www.cstm.org.cn/",
            "opening_hours": "9:30-17:00, Tuesday to Sunday",
            "closing_hours": "Closed on Mondays (except national holidays), Chinese Lunar New Year's Eve, first day and second day"
        }
        await seed_museum("china-science-and-technology-museum", china_science_items, china_science_updates)

    natural_history_items = process_natural_history(NATURAL_HISTORY_XLSX)
    if natural_history_items:
        natural_history_updates = {
            "website": "https://www.nhm.ac.uk/",
            "opening_hours": "Open every day, 10:00-17:50",
            "closing_hours": ""
        }
        await seed_museum("natural-history-museum-south-kensington", natural_history_items, natural_history_updates)

if __name__ == "__main__":
    asyncio.run(main())
