"""
Seed the M+ Museum masterpieces and metadata into the database.

Usage (from the backend root):
    python -m app.scripts.seed_mplus
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

MPLUS_XLSX = os.environ.get(
    "MPLUS_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "M+_Museum_Itineraries_5hr_1day.xlsx"))
)

MUSEUM_META = {
    "slug": "m-plus",
    "name": "M+",
    "city": "Hong Kong",
    "country": "Hong Kong",
    "annual_visitors": 2610000,
    "rank": 33,
    "image_url": "/api/v1/places/photo?ref=places/ChIJd3wXPZAABDQRDFz86-Qpbto/photos/AWCwydjGflUeFGRuT-TMWf00aEM8bXTy4lGY0EmOPxjHfHZoPRTcMtOsgWXaMcaro1aJh82mgF6XHDLeYgQdrgNGRgoP65gO4Ck8NqsSSCD3wNdqa06RyyyF_mtHsf8Ronv7xQFAT8hDEERjqpPfSmIRXuQSMGg663KMNcbNEaGWpQv9qUdKJE1_FgpRRsj55t9p65s5fM8socK6heUmvpuAQY1h3TcNS0ICn5GZHkgcGmVQnzxYw8-uRD0k-jlM9rWJeE1_LxR_AlacHOGScH9l4lrniCm-jzfVvESfZf15WwTiVBjFhIO3IxVn_8pW5ttqqat4P_Mui6QJEywUXr-k44ZdoQ_9QbnlrtEpQn412aRA-JsRC79aGXUKvq4STUmJgobzNZ6bqS_GKJpOEdwNHDDAUjjbnPy-JKt4zUzK5PSCnLTr",
    "ticket_url": "https://www.mplus.org.hk/en/",
    "latitude": 22.300958,
    "longitude": 114.159645,
}

def guess_category_mplus(item_name, location):
    item_lower = item_name.lower()
    loc_lower = (location or "").lower()
    
    if any(x in item_lower for x in ["neon", "signs", "tsang", "kowloon"]):
        return "Hong Kong Visual Culture"
    if any(x in item_lower for x in ["sigg", "fang lijun", "yang jiechang"]):
        return "Contemporary Chinese Art"
    if any(x in item_lower for x in ["kuramata", "sushi", "gary chang", "domestic transformer"]):
        return "Design & Architecture"
    if any(x in item_lower for x in ["installation", "found space", "facade"]):
        return "Installation Art"
    if any(x in item_lower or x in loc_lower for x in ["moving image", "cinema", "mediatheque"]):
        return "Moving Image"
    return "Visual Art"

def clean_value(val):
    if not val or pd.isna(val):
        return ""
    s = str(val).strip()
    for c in ["\ufffd", "\u2013", "\u2014", "\u2011"]:
        s = s.replace(c, "-")
    s = " ".join(s.split())
    return s

def get_floor_and_room(location_str):
    loc = clean_value(location_str)
    if not loc:
        return "M+", ""
    
    parts = [p.strip() for p in loc.split("-") if p.strip()]
    if len(parts) >= 2:
        return parts[0], " - ".join(parts[1:])
    
    # Fallbacks
    if loc.startswith("Level 3"):
        return "Level 3", loc
    if loc.startswith("B1"):
        return "B1", loc
    
    return "M+", loc

def normalize_key(name):
    s = name.lower()
    for suffix in [" (optional detour)", " (varies)", " works (selection rotates)"]:
        if s.endswith(suffix):
            s = s[:-len(suffix)]
    return s.strip()

def process_mplus(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Excel file not found at: {file_path}")
        return None

    xl = pd.ExcelFile(file_path)
    merged = {}

    item_col = "Highlight"
    loc_col = "Location"
    stop_col = "Stop"

    # 1. Read 5 Hour Itinerary
    if "5 Hour Itinerary" in xl.sheet_names:
        df_5h = pd.read_excel(xl, "5 Hour Itinerary")
        for idx, row in df_5h.iterrows():
            item_name = clean_value(row[item_col])
            loc_val = clean_value(row[loc_col])
            key = normalize_key(item_name)
            rank_val = int(row.get(stop_col, idx + 1))
            floor_val, room_val = get_floor_and_room(loc_val)
            
            merged[key] = {
                "rank": rank_val,
                "building": floor_val,
                "room_gallery": room_val or floor_val,
                "must_see_item": item_name,
                "artist": None,
                "category": guess_category_mplus(item_name, loc_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }

    # 2. Read 1 Day Itinerary
    if "1 Day Itinerary" in xl.sheet_names:
        df_1d = pd.read_excel(xl, "1 Day Itinerary")
        for idx, row in df_1d.iterrows():
            item_name = clean_value(row[item_col])
            loc_val = clean_value(row[loc_col])
            key = normalize_key(item_name)
            rank_val = int(row.get(stop_col, idx + 1))
            floor_val, room_val = get_floor_and_room(loc_val)

            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": rank_val,
                    "building": floor_val,
                    "room_gallery": room_val or floor_val,
                    "must_see_item": item_name,
                    "artist": None,
                    "category": guess_category_mplus(item_name, loc_val),
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
    mplus_items = process_mplus(MPLUS_XLSX)
    if mplus_items:
        await seed_museum("m-plus", mplus_items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
