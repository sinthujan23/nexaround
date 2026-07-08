"""
Seed the Metropolitan Museum of Art masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_metropolitan
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

MET_XLSX = os.environ.get(
    "MET_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Metropolitan_Museum_of Art_5_Hour_and_1_Day_Itineraries.xlsx"))
)

def guess_category_met(item_name, wing, gallery, artist):
    item_lower = item_name.lower()
    wing_lower = (wing or "").lower()
    gallery_lower = (gallery or "").lower()
    artist_lower = (artist or "").lower()
    
    if "egyptian" in wing_lower or "egyptian" in gallery_lower:
        return "Antiquities"
    if "greek" in wing_lower or "roman" in wing_lower or "etruscan" in wing_lower:
        if "sculpture" in item_lower or "statue" in item_lower or "perseus" in item_lower or "bust" in item_lower:
            return "Classical Sculpture"
        return "Antiquities"
    if "paintings" in wing_lower or "painting" in wing_lower or "european art" in wing_lower:
        if "dutch" in gallery_lower or "flemish" in gallery_lower or "rembrandt" in artist_lower or "vermeer" in artist_lower or "bruegel" in artist_lower:
            return "Dutch & Flemish Painting"
        if "renaissance" in gallery_lower or "raphael" in artist_lower or "da vinci" in artist_lower or "michelangelo" in artist_lower or "botticelli" in artist_lower:
            return "Renaissance Painting"
        if "baroque" in gallery_lower or "caravaggio" in artist_lower or "gentileschi" in artist_lower:
            return "Baroque Painting"
        if "french" in gallery_lower or "david" in artist_lower or "monet" in artist_lower or "degas" in artist_lower or "renoir" in artist_lower:
            return "French Painting"
        if "spanish" in gallery_lower or "velázquez" in artist_lower or "velazquez" in artist_lower or "goya" in artist_lower or "el greco" in artist_lower:
            return "Spanish Painting"
        if "british" in gallery_lower or "gainsborough" in artist_lower or "turner" in artist_lower:
            return "British Painting"
        return "Painting"
    if "modern" in wing_lower or "modern" in gallery_lower:
        if "sculpture" in item_lower:
            return "Modern Sculpture"
        return "Modern Painting"
    if "medieval" in wing_lower or "medieval" in gallery_lower:
        if "sculpture" in item_lower or "statue" in item_lower:
            return "Sculpture"
        return "Decorative Arts"
    if "arms" in wing_lower or "armor" in wing_lower or "arms" in gallery_lower:
        return "Arms and Armor"
    if "sculpture" in item_lower or "sculpture" in wing_lower or "sculpture" in gallery_lower:
        return "Sculpture"
    return "Decorative Arts"

def process_met(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Met Excel file not found at: {file_path}")
        return None
    xl = pd.ExcelFile(file_path)
    merged = {}
    
    sheet_5h = "5-Hour Itinerary (21)"
    if sheet_5h in xl.sheet_names:
        df = pd.read_excel(xl, sheet_5h)
        for idx, row in df.iterrows():
            raw_item = str(row["Must-See Masterpiece"]).strip()
            
            if "\u2011" in raw_item:
                raw_item = raw_item.replace("\u2011", "-")
            if "\u2013" in raw_item:
                parts = raw_item.split("\u2013")
            elif "—" in raw_item:
                parts = raw_item.split("—")
            else:
                parts = [raw_item]
                
            item_name = parts[0].strip()
            artist_val = parts[1].strip() if len(parts) > 1 else None
            if artist_val == "\u2014" or not artist_val or artist_val == "nan":
                artist_val = None
                
            building_val = str(row.get("Area / Wing", "")).strip()
            room_gallery_val = str(row.get("Gallery / Collection", "")).strip()
            key = item_name.lower()
            
            merged[key] = {
                "rank": int(row.get("#", idx + 1)),
                "building": building_val,
                "room_gallery": room_gallery_val,
                "must_see_item": item_name,
                "artist": artist_val,
                "category": guess_category_met(item_name, building_val, room_gallery_val, artist_val),
                "description": None,
                "included_5h": True,
                "included_1d": False,
                "included_2d": False
            }
            
    sheet_1d = "Top 50 Masterpieces"
    if sheet_1d in xl.sheet_names:
        df = pd.read_excel(xl, sheet_1d)
        for idx, row in df.iterrows():
            raw_item = str(row["Must-See Masterpiece"]).strip()
            
            if "\u2011" in raw_item:
                raw_item = raw_item.replace("\u2011", "-")
            if "\u2013" in raw_item:
                parts = raw_item.split("\u2013")
            elif "—" in raw_item:
                parts = raw_item.split("—")
            else:
                parts = [raw_item]
                
            item_name = parts[0].strip()
            artist_val = parts[1].strip() if len(parts) > 1 else None
            if artist_val == "\u2014" or not artist_val or artist_val == "nan":
                artist_val = None
                
            building_val = str(row.get("Area / Wing", "")).strip()
            room_gallery_val = str(row.get("Gallery / Collection", "")).strip()
            key = item_name.lower()
            
            if key in merged:
                merged[key]["included_1d"] = True
            else:
                merged[key] = {
                    "rank": int(row.get("#", idx + 1)),
                    "building": building_val,
                    "room_gallery": room_gallery_val,
                    "must_see_item": item_name,
                    "artist": artist_val,
                    "category": guess_category_met(item_name, building_val, room_gallery_val, artist_val),
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
    met_items = process_met(MET_XLSX)
    if met_items:
        await seed_museum("metropolitan-museum-of-art", met_items)
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(main())
