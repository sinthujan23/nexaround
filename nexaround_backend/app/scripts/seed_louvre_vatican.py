"""
Seed the Louvre and Vatican Museum masterpieces into the database.

Usage (from the backend root):
    python -m app.scripts.seed_louvre_vatican

This script:
  1. Locates the Louvre and Vatican Museums in the DB.
  2. Reads and merges the 5-Hour and 1-Day Itinerary sheets from their respective Excel files.
  3. Applies smart categorizations so they render with custom colors/icons in the app.
  4. Inserts/updates all masterpieces with their duration flags.

Requires: openpyxl, pandas
    pip install openpyxl pandas
"""

import asyncio
import os
import sys
import uuid
import pandas as pd
from sqlalchemy import select

# ── Bootstrap the app so models / settings are importable ────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base  # noqa: E402
from app.models.museum import Museum, MuseumMasterpiece  # noqa: E402

# Paths to Excel files (configurable via env variables, defaulting to app directory)
LOUVRE_XLSX = os.environ.get(
    "LOUVRE_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Louvre_5_Hour_and_1_Day_Itineraries.xlsx"))
)
VATICAN_XLSX = os.environ.get(
    "VATICAN_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app", "Vatican_5_Hour_and_1_Day_Itineraries.xlsx"))
)

def guess_category(item_name, artist, building, is_vatican=False):
    """Heuristic categorizer to map items to beautiful icons and colors in the mobile app."""
    item_lower = item_name.lower()
    artist_lower = (artist or "").lower()
    building_lower = (building or "").lower()
    
    if is_vatican:
        if any(x in item_lower for x in ["chapel", "sistine", "fresco", "painting", "canvas", "stanze", "raphael"]):
            return "Renaissance Painting"
        if any(x in item_lower for x in ["sculpture", "statue", "laocoon", "belvedere", "pieta", "apollo", "torso"]):
            return "Classical Sculpture"
        if any(x in item_lower for x in ["gallery", "hall", "map", "tapestry", "candelabra"]):
            return "Decorative Arts"
        if any(x in item_lower for x in ["square", "basilica", "dome", "entrance", "courtyard", "gardens"]):
            return "Architecture"
        return "Vatican Masterpiece"
    else:
        if any(x in item_lower for x in ["pyramid", "palace", "colonnade", "courtyard", "entrance", "galerie"]):
            return "Architecture"
        if any(x in item_lower for x in ["victory of samothrace", "venus de milo", "sculpture", "statue", "psyche", "slaves", "sculptures"]):
            return "Sculpture"
        if any(x in item_lower for x in ["mona lisa", "cana", "painting", "coronation", "raft", "liberty", "portrait", "madonna"]):
            if "leonardo" in artist_lower or "veronese" in artist_lower or "raphael" in artist_lower:
                return "Renaissance Painting"
            if "david" in artist_lower or "gericault" in artist_lower or "delacroix" in artist_lower or "ingres" in artist_lower:
                return "French Painting"
            return "Painting"
        if any(x in item_lower for x in ["antiquities", "egyptian", "code of hammurabi", "mummy", "sarcophagus"]):
            return "Antiquities"
        return "Louvre Masterpiece"

def process_excel(file_path, is_vatican=False):
    """Reads and merges 5-Hour and 1-Day Itineraries from Excel."""
    if not os.path.exists(file_path):
        print(f"❌ Excel file not found at: {file_path}")
        return None

    # Load file
    xl = pd.ExcelFile(file_path)
    merged = {}

    # Column name mappings
    item_col = "Must-See Highlight" if is_vatican else "Must-See Item"
    building_col = "Area" if is_vatican else "Wing"
    room_col = "Gallery / Collection"
    artist_col = "Artist / Culture"
    desc_col = "Why It's a Must-See"

    # 1. Read 5-Hour Itinerary
    df_5h = pd.read_excel(xl, "5-Hour Itinerary")
    for idx, row in df_5h.iterrows():
        item_name = str(row[item_col]).strip()
        key = item_name.lower()
        rank_val = int(row.get('#', idx + 1))
        artist_val = str(row.get(artist_col, "")).strip() or None
        building_val = str(row.get(building_col, "")).strip()
        
        merged[key] = {
            "rank": rank_val,
            "building": building_val,
            "room_gallery": str(row.get(room_col, "")).strip(),
            "must_see_item": item_name,
            "artist": artist_val,
            "category": guess_category(item_name, artist_val, building_val, is_vatican),
            "description": str(row.get(desc_col, "")).strip() or None,
            "included_5h": True,
            "included_1d": False,
            "included_2d": False
        }

    # 2. Read 1-Day Itinerary
    df_1d = pd.read_excel(xl, "1-Day Itinerary")
    for idx, row in df_1d.iterrows():
        item_name = str(row[item_col]).strip()
        key = item_name.lower()
        rank_val = int(row.get('#', idx + 1))
        artist_val = str(row.get(artist_col, "")).strip() or None
        building_val = str(row.get(building_col, "")).strip()

        if key in merged:
            # Mark as included in 1D too
            merged[key]["included_1d"] = True
            # Prefer 5H metadata but ensure it has 1D flag set
        else:
            # Unique to 1D
            merged[key] = {
                "rank": rank_val,
                "building": building_val,
                "room_gallery": str(row.get(room_col, "")).strip(),
                "must_see_item": item_name,
                "artist": artist_val,
                "category": guess_category(item_name, artist_val, building_val, is_vatican),
                "description": str(row.get(desc_col, "")).strip() or None,
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

async def seed_museum(slug, excel_path, is_vatican=False):
    async with async_session() as session:
        # Find museum
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()
        if not museum:
            print(f"❌ Museum with slug '{slug}' not found in database. Run seed_all_museums first.")
            return

        print(f"⚙️  Processing details for {museum.name} ({slug})...")

        # Parse Excel data
        masterpieces = process_excel(excel_path, is_vatican=is_vatican)
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
    # Ensure tables exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Seed Louvre
    await seed_museum("louvre", LOUVRE_XLSX, is_vatican=False)
    
    # Seed Vatican
    await seed_museum("vatican-museums", VATICAN_XLSX, is_vatican=True)

if __name__ == "__main__":
    asyncio.run(main())
