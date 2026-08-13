"""
Seed script for Van Gogh Museum (Amsterdam) masterpieces and metadata.
Includes 5-Hour and 1-Day itinerary stops and highlights from Van_Gogh_Museum_1-Day_and_5-Hour_Itineraries.xlsx.

Usage (from backend root or docker/VPS):
    docker exec nexaround_backend-api-1 python -m app.scripts.seed_van_gogh
"""

import asyncio
import os
import sys
import uuid
import pandas as pd
from sqlalchemy import select, delete

# Bootstrap app models / settings
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import engine, async_session, Base
from app.models.museum import Museum, MuseumMasterpiece

MUSEUM_META = {
    "slug": "van-gogh-museum",
    "name": "Van Gogh Museum",
    "city": "Amsterdam",
    "country": "Netherlands",
    "annual_visitors": 1840000,
    "rank": 47,
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e8/Van_Gogh_Museum_2015.jpg/1280px-Van_Gogh_Museum_2015.jpg",
    "ticket_url": "https://www.vangoghmuseum.nl/en/visit/tickets",
    "website": "https://www.vangoghmuseum.nl/en",
    "opening_hours": "Monday to Sunday: 09:00 to 18:00",
    "closing_hours": "18:00",
    "latitude": 52.3584,
    "longitude": 4.8811,
}

POSSIBLE_EXCEL_PATHS = [
    os.environ.get("VAN_GOGH_XLSX", ""),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "Van_Gogh_Museum_1-Day_and_5-Hour_Itineraries.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Van_Gogh_Museum_1-Day_and_5-Hour_Itineraries.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "nexaround_app", "Van_Gogh_Museum_1-Day_and_5-Hour_Itineraries.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "nexaround_backend", "app", "scripts", "Van_Gogh_Museum_1-Day_and_5-Hour_Itineraries.xlsx")),
]

def find_excel_file():
    for p in POSSIBLE_EXCEL_PATHS:
        if p and os.path.exists(p):
            return p
    return ""

def get_building(period):
    p_lower = (period or "").lower()
    if any(x in p_lower for x in ["nuenen", "paris"]):
        return "Floor 1 - Early Works & Paris"
    elif any(x in p_lower for x in ["arles", "saint-rémy", "saint-remy", "auvers"]):
        return "Floor 2 - Masterpieces (Arles, Saint-Rémy & Auvers)"
    elif "portrait" in p_lower or "context" in p_lower:
        return "Floor 3 - Portraits & Contemporaries"
    return "Main Building"

def guess_artist(artwork_name, period):
    art_lower = (artwork_name or "").lower()
    if "gauguin" in art_lower:
        return "Paul Gauguin"
    if "delacroix" in art_lower:
        return "Vincent van Gogh (after Delacroix)"
    if "millet" in art_lower:
        return "Vincent van Gogh (after Millet)"
    if "theo van gogh" in art_lower:
        return "Vincent van Gogh / Theo van Gogh"
    return "Vincent van Gogh"

def process_excel(file_path):
    if not os.path.exists(file_path):
        print(f"[ERROR] Van Gogh Excel file not found at: {file_path}")
        return []

    xl = pd.ExcelFile(file_path)
    merged = {}

    def extract_items(sheet_name, flag_name):
        if sheet_name not in xl.sheet_names:
            return
        df = pd.read_excel(xl, sheet_name)
        for _, row in df.iterrows():
            artwork = str(row.get("Artwork", "")).strip()
            if not artwork or artwork.lower() in ["nan", "none"]:
                continue

            period = str(row.get("Period", "")).strip()
            if period.lower() in ["nan", "none"]:
                period = "Van Gogh Masterpieces"

            must_see_val = str(row.get("Must See", "")).strip().lower() == "yes"
            building_val = get_building(period)

            notes = str(row.get("Notes", "")).strip()
            if not notes or notes.lower() in ["nan", "none"]:
                notes = f"Famous masterpiece '{artwork}' by Vincent van Gogh from the {period} period."

            key = artwork.lower()

            if key in merged:
                merged[key][flag_name] = True
                if must_see_val:
                    merged[key]["included_5h"] = True
            else:
                merged[key] = {
                    "building": building_val,
                    "room_gallery": period,
                    "must_see_item": artwork,
                    "artist": guess_artist(artwork, period),
                    "category": "Post-Impressionism",
                    "description": notes,
                    "included_3h": False,
                    "included_5h": False,
                    "included_1d": True,  # Items in sheet are in 1-day itinerary
                    "included_2d": False,
                }
                merged[key][flag_name] = True
                if must_see_val:
                    merged[key]["included_5h"] = True

    extract_items("5-Hour Itinerary", "included_5h")
    extract_items("1-Day Itinerary", "included_1d")

    masterpieces = list(merged.values())
    masterpieces.sort(key=lambda x: (not x["included_5h"], x["building"], x["must_see_item"]))
    for idx, item in enumerate(masterpieces, 1):
        item["rank"] = idx

    return masterpieces

async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    excel_path = find_excel_file()
    print(f"Using Excel file at: {excel_path}")

    async with async_session() as session:
        # 1. Upsert museum
        result = await session.execute(
            select(Museum).where(Museum.slug == MUSEUM_META["slug"])
        )
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
                website=MUSEUM_META["website"],
                opening_hours=MUSEUM_META["opening_hours"],
                closing_hours=MUSEUM_META["closing_hours"],
                latitude=MUSEUM_META["latitude"],
                longitude=MUSEUM_META["longitude"],
            )
            session.add(museum)
            await session.flush()
            print(f"Created museum: {museum.name}")
        else:
            museum.name = MUSEUM_META["name"]
            museum.website = MUSEUM_META["website"]
            museum.opening_hours = MUSEUM_META["opening_hours"]
            museum.closing_hours = MUSEUM_META["closing_hours"]
            museum.ticket_url = MUSEUM_META["ticket_url"]
            print(f"Updated museum: {museum.name}")

        # 2. Delete existing masterpieces for re-seeding
        await session.execute(
            delete(MuseumMasterpiece).where(MuseumMasterpiece.museum_id == museum.id)
        )
        print(f"Cleared previous masterpieces for {museum.name}")

        # 3. Process excel and insert masterpieces
        items = process_excel(excel_path)
        print(f"Found {len(items)} masterpieces across 5h and 1d itineraries.")

        added_count = 0
        for item_data in items:
            m = MuseumMasterpiece(
                id=uuid.uuid4(),
                museum_id=museum.id,
                rank=item_data["rank"],
                building=item_data["building"],
                room_gallery=item_data["room_gallery"],
                must_see_item=item_data["must_see_item"],
                artist=item_data["artist"],
                category=item_data["category"],
                description=item_data["description"],
                included_3h=item_data["included_3h"],
                included_5h=item_data["included_5h"],
                included_1d=item_data["included_1d"],
                included_2d=item_data["included_2d"],
            )
            session.add(m)
            added_count += 1

        await session.commit()
        print(f"✅ Successfully seeded {added_count} masterpieces for {museum.name}!")

if __name__ == "__main__":
    asyncio.run(seed())
