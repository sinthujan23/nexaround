"""
Seed the Acropolis Museum masterpieces and metadata into the database.

Usage (from the backend root):
    python -m app.scripts.seed_acropolis
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

ACROPOLIS_XLSX = os.environ.get(
    "ACROPOLIS_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Acropolis_Museum_Itineraries_with_Locations.xlsx"))
)

MUSEUM_META = {
    "slug": "acropolis-museum",
    "name": "Acropolis Museum",
    "city": "Athens",
    "country": "Greece",
    "annual_visitors": 1451727,
    "rank": 58,
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Athens_Acropolis_Museum_N1.JPG/1280px-Athens_Acropolis_Museum_N1.JPG",
    "ticket_url": "https://www.theacropolismuseum.gr/en/tickets-acropolis-museum",
    "website": "https://www.theacropolismuseum.gr/",
    "latitude": 37.968294,
    "longitude": 23.728519,
    "opening_hours": (
        "Winter season (1 November - 31 March):\n"
        "Monday - Thursday: 9 am - 5 pm / Last entry: 4:30 pm\n"
        "Friday: 9 am - 10 pm / Last entry: 9:30 pm\n"
        "Saturday & Sunday: 9 am - 8 pm / Last entry: 7:30 pm\n\n"
        "Summer season (1 April - 31 October):\n"
        "Monday: 9 am - 5 pm / Last entry: 4:30 pm\n"
        "Tuesday - Sunday: 9 am - 8 pm / Last entry: 7:30 pm\n"
        "Friday: 9 am - 10 pm / Last entry: 9:30 pm"
    ),
    "closing_hours": "Closed: 1 January, Easter Sunday, 1 May, 25 & 26 December"
}

def guess_category(item_name, location):
    item_lower = item_name.lower()
    loc_lower = (location or "").lower()
    
    if "parthenon" in loc_lower or "parthenon" in item_lower:
        return "Parthenon Gallery"
    if "archaic" in loc_lower or "archaic" in item_lower:
        return "Archaic Sculpture"
    if "slopes" in loc_lower or "slopes" in item_lower:
        return "Acropolis Slopes Gallery"
    if "excavation" in loc_lower or "excavation" in item_lower:
        return "Archaeological Excavation"
    if "mycenaean" in loc_lower or "geometric" in loc_lower:
        return "Prehistoric Gallery"
    if "nike" in item_lower or "caryatid" in item_lower or "sculpture" in item_lower or "statue" in item_lower or "head" in item_lower or "torso" in item_lower:
        return "Classical Sculpture"
    return "Acropolis Antiquities"

def extract_building(location):
    loc_lower = (location or "").lower()
    if "level -1" in loc_lower:
        return "Level -1 (Excavation)"
    if "ground floor" in loc_lower:
        return "Ground Floor"
    if "first floor" in loc_lower:
        return "First Floor"
    if "third floor" in loc_lower:
        return "Third Floor"
    return "Main Building"

def clean_value(val):
    if not val or pd.isna(val):
        return ""
    return str(val).strip()

def process_acropolis(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Acropolis museum Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    # 1. 5-Hour Itinerary
    sheet_5h = "5 Hour Itinerary"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            item_name = clean_value(row["Exhibit"])
            location_val = clean_value(row.get("Location", ""))
            building_val = extract_building(location_val)
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop", idx + 1)),
                "building": building_val,
                "room_gallery": location_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category(item_name, location_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    # 2. 1-Day Itinerary
    sheet_1d = "1 Day Itinerary"
    if sheet_1d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_1d)
        for idx, row in df.iterrows():
            item_name = clean_value(row["Exhibit"])
            location_val = clean_value(row.get("Location", ""))
            building_val = extract_building(location_val)
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": building_val,
                    "room_gallery": location_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category(item_name, location_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": True,
                    "included_2d": False
                }

    # 3. 2-Day Itinerary
    sheet_2d = "2 Day Itinerary"
    if sheet_2d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_2d)
        for idx, row in df.iterrows():
            item_name = clean_value(row["Exhibit"])
            location_val = clean_value(row.get("Location", ""))
            building_val = extract_building(location_val)
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_2d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": building_val,
                    "room_gallery": location_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category(item_name, location_val),
                    "description": None,
                    "included_5h": False,
                    "included_1d": False,
                    "included_2d": True
                }
                
    sorted_items = list(merged.values())
    sorted_items.sort(key=lambda x: (not x["included_5h"], not x["included_1d"], x["rank"]))
    for index, item in enumerate(sorted_items, 1):
        item["rank"] = index
    return sorted_items

async def seed_museum(masterpieces):
    async with async_session() as session:
        # Find museum
        result = await session.execute(select(Museum).where(Museum.slug == MUSEUM_META["slug"]))
        museum = result.scalar_one_or_none()
        
        if not museum:
            # If not found, create new record
            print(f"➕ Creating museum record for {MUSEUM_META['name']}...")
            museum = Museum(
                id=uuid.uuid4(),
                slug=MUSEUM_META["slug"],
                name=MUSEUM_META["name"],
                city=MUSEUM_META["city"],
                country=MUSEUM_META["country"],
                annual_visitors=MUSEUM_META["annual_visitors"],
                rank=MUSEUM_META["rank"]
            )
            session.add(museum)
            await session.flush()
        
        print(f"⚙️  Updating details for {museum.name} ({MUSEUM_META['slug']})...")
        
        # Update metadata
        museum.image_url = MUSEUM_META["image_url"]
        museum.ticket_url = MUSEUM_META["ticket_url"]
        museum.website = MUSEUM_META["website"]
        museum.latitude = MUSEUM_META["latitude"]
        museum.longitude = MUSEUM_META["longitude"]
        museum.opening_hours = MUSEUM_META["opening_hours"]
        museum.closing_hours = MUSEUM_META["closing_hours"]

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
        print(f"✅ Successfully seeded {count} masterpieces and metadata for {museum.name}!")

async def main():
    items = process_acropolis(ACROPOLIS_XLSX)
    if items:
        await seed_museum(items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
