"""
Seed the National Museum of Korea masterpieces and metadata into the database.

Usage (from the backend root):
    python -m app.scripts.seed_korea
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

KOREA_XLSX = os.environ.get(
    "KOREA_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "National_Museum_of_Korea_Itineraries_Updated.xlsx"))
)

MUSEUM_META = {
    "slug": "national-museum-of-korea",
    "name": "National Museum of Korea",
    "city": "Seoul",
    "country": "South Korea",
    "annual_visitors": 6505483,
    "rank": 5,
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/National_Museum_of_Korea_1.jpg/1280px-National_Museum_of_Korea_1.jpg",
    "ticket_url": "https://www.museum.go.kr/ENG/contents/E0101010000.do",
    "latitude": 37.523851,
    "longitude": 126.980482,
}

def guess_category_korea(item_name, gallery_name):
    item_lower = item_name.lower()
    gallery_lower = (gallery_name or "").lower()
    
    if "sculpture" in item_lower or "sculpture" in gallery_lower or "statue" in item_lower or "buddha" in item_lower or "bodhisattva" in item_lower:
        return "Sculpture"
    if "painting" in item_lower or "painting" in gallery_lower or "calligraphy" in gallery_lower or "genre painting" in item_lower or "scroll" in item_lower:
        return "Painting"
    if "celadon" in gallery_lower or "porcelain" in gallery_lower or "buncheong" in gallery_lower or "pottery" in item_lower or "jar" in item_lower or "vase" in item_lower or "urn" in item_lower or "bowl" in item_lower:
        return "Decorative Arts"
    if "crown" in item_lower or "belt" in item_lower or "crafts" in gallery_lower or "metal" in gallery_lower or "wood" in gallery_lower or "lacquer" in gallery_lower or "bell" in item_lower or "dagger" in item_lower or "ritual" in item_lower or "relic" in item_lower:
        return "Decorative Arts"
    return "Antiquities"

def clean_room_gallery(val):
    if not val or pd.isna(val):
        return ""
    s = str(val).strip()
    # Replace non-breaking hyphen, en-dash, em-dash, or replacement character
    for c in ["\ufffd", "\u2013", "\u2014", "\u2011"]:
        s = s.replace(c, "-")
    # Clean up double spaces or spaces around dashes
    s = " ".join(s.split())
    # Ensure spaces around dashes look clean, e.g. "101 - Paleolithic"
    if " - " not in s and "-" in s:
        s = s.replace("-", " - ")
        s = " ".join(s.split())
    return s

def extract_building(gallery_name):
    g_str = str(gallery_name)
    if "(1F)" in g_str:
        return "1st Floor (1F)"
    elif "(2F)" in g_str:
        return "2nd Floor (2F)"
    elif "(3F)" in g_str:
        return "3rd Floor (3F)"
    return "Main Building"

def process_korea(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Korea museum Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    # 1. 5-Hour Itinerary
    sheet_5h = "5 Hour Itinerary"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            item_name = str(row["Object"]).strip()
            raw_gallery = str(row.get("Gallery / Floor", "")).strip()
            gallery_val = clean_room_gallery(raw_gallery)
            building_val = extract_building(raw_gallery)
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("Stop", idx + 1)),
                "building": building_val,
                "room_gallery": gallery_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category_korea(item_name, gallery_val),
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
            item_name = str(row["Object"]).strip()
            raw_gallery = str(row.get("Gallery / Floor", "")).strip()
            gallery_val = clean_room_gallery(raw_gallery)
            building_val = extract_building(raw_gallery)
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("Stop", idx + 1)),
                    "building": building_val,
                    "room_gallery": gallery_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category_korea(item_name, gallery_val),
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
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        # 1. Upsert museum metadata
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()
        if museum is None:
            museum = Museum(
                id=uuid.uuid4(),
                slug=MUSEUM_META["slug"],
                name=MUSEUM_META["name"],
                city=MUSEUM_META["city"],
                country=MUSEUM_META["country"],
                annual_visitors=MUSEUM_META["annual_visitors"],
                rank=MUSEUM_META["rank"],
                image_url=MUSEUM_META["image_url"],
                ticket_url=MUSEUM_META["ticket_url"],
                latitude=MUSEUM_META["latitude"],
                longitude=MUSEUM_META["longitude"],
            )
            session.add(museum)
            await session.flush()
            print(f"✅ Created museum: {museum.name} (id={museum.id})")
        else:
            # Update fields
            museum.name = MUSEUM_META["name"]
            museum.city = MUSEUM_META["city"]
            museum.country = MUSEUM_META["country"]
            museum.annual_visitors = MUSEUM_META["annual_visitors"]
            museum.rank = MUSEUM_META["rank"]
            museum.image_url = MUSEUM_META["image_url"]
            museum.ticket_url = MUSEUM_META["ticket_url"]
            museum.latitude = MUSEUM_META["latitude"]
            museum.longitude = MUSEUM_META["longitude"]
            await session.flush()
            print(f"ℹ️  Updated museum metadata for: {museum.name} (id={museum.id})")

        # 2. Clear existing masterpieces for idempotency
        existing = await session.execute(
            select(MuseumMasterpiece).where(MuseumMasterpiece.museum_id == museum.id)
        )
        for old in existing.scalars().all():
            await session.delete(old)
        await session.flush()

        # 3. Insert new masterpieces
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
    korea_items = process_korea(KOREA_XLSX)
    if korea_items:
        await seed_museum("national-museum-of-korea", korea_items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
