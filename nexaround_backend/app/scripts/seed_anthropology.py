"""
Seed script for National Museum of Anthropology (Mexico City) masterpieces and metadata.
Includes 5-Hour, 1-Day, and 2-Day itinerary stops and highlights from National_Museum_of_Anthropology_Itineraries_Full.xlsx.

Usage (from backend root or docker):
    docker exec nexaround_backend-api-1 python -m app.scripts.seed_anthropology
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
    "slug": "national-museum-of-anthropology",
    "name": "National Museum of Anthropology",
    "city": "Mexico City",
    "country": "Mexico",
    "annual_visitors": 3700000,
    "rank": 17,
    "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Museo_Nacional_de_Antropolog%C3%ADa_01.jpg/1280px-Museo_Nacional_de_Antropolog%C3%ADa_01.jpg",
    "ticket_url": "https://mna.inah.gob.mx/",
    "website": "https://mna.inah.gob.mx/",
    "opening_hours": "Tuesday to Sunday: 9:00 to 18:00 hours",
    "closing_hours": "18:00",
    "latitude": 19.426002,
    "longitude": -99.186279,
}

EXCEL_PATH = os.environ.get(
    "ANTHROPOLOGY_XLSX",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "National_Museum_of_Anthropology_Itineraries_Full.xlsx"))
)

def get_building_and_category(room_name):
    room_lower = (room_name or "").lower()
    if any(x in room_lower for x in ["ethnography", "indigenous", "nayar", "puréecherio", "otopame", "sierra de puebla", "southern indigenous", "huasteca", "jungle maya", "highland maya", "northwest", "nahua"]):
        building = "Upper Floor - Ethnography"
        category = "Living Ethnography"
    elif "mexica" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Mexica (Aztec)"
    elif "maya" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Maya Civilization"
    elif "teotihuacan" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Teotihuacan"
    elif "oaxaca" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Zapotec & Mixtec (Oaxaca)"
    elif "gulf" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Gulf Coast (Olmec)"
    elif "toltec" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Toltec & Epiclassic"
    elif "west mexico" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "West Mexico"
    elif "northern" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Northern Mexico"
    elif "preclassic" in room_lower:
        building = "Ground Floor - Archaeology"
        category = "Preclassic Central Highlands"
    elif any(x in room_lower for x in ["populating", "anthropology", "entrance"]):
        building = "Ground Floor - Archaeology"
        category = "Origins & Archaeology"
    else:
        building = "Ground Floor - Archaeology"
        category = "Archaeology"
    return building, category

def guess_artist(room_name, item_name):
    room_lower = (room_name or "").lower()
    item_lower = (item_name or "").lower()

    if "mexica" in room_lower or "aztec" in item_lower or "tenochtitlan" in item_lower:
        return "Mexica Artisans"
    if "maya" in room_lower or "pakal" in item_lower:
        return "Maya Artists"
    if "olmec" in item_lower or "gulf" in room_lower:
        return "Olmec Sculptors"
    if "teotihuacan" in room_lower:
        return "Teotihuacan Craftsmen"
    if "oaxaca" in room_lower or "zapotec" in item_lower or "mixtec" in item_lower:
        return "Zapotec & Mixtec Artisans"
    if "toltec" in room_lower:
        return "Toltec Master Sculptors"
    if "ethnography" in room_lower or "indigenous" in room_lower:
        return "Indigenous Communities"
    return "Mesoamerican Artisans"

def process_excel(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Anthropology Excel file not found at: {file_path}")
        return []

    xl = pd.ExcelFile(file_path)
    merged = {}

    def extract_items_from_sheet(sheet_name, flag_name):
        if sheet_name not in xl.sheet_names:
            return
        df = pd.read_excel(xl, sheet_name)
        for _, row in df.iterrows():
            room_name = str(row.get("Room", "")).strip()
            overview = str(row.get("Overview", "")).strip()
            highlights_raw = str(row.get("Key Highlights", "")).strip()

            building_val, cat_val = get_building_and_category(room_name)

            # Split key highlights by semicolon
            highlights = [h.strip() for h in highlights_raw.split(";") if h.strip()]
            if not highlights:
                highlights = [room_name]

            for item_name in highlights:
                # Key based on item_name and room_name to preserve context
                key = f"{room_name.lower()}||{item_name.lower()}"
                
                if key in merged:
                    merged[key][flag_name] = True
                else:
                    merged[key] = {
                        "building": building_val,
                        "room_gallery": room_name,
                        "must_see_item": item_name,
                        "artist": guess_artist(room_name, item_name),
                        "category": cat_val,
                        "description": overview,
                        "included_3h": False,
                        "included_5h": False,
                        "included_1d": False,
                        "included_2d": False,
                    }
                    merged[key][flag_name] = True

    extract_items_from_sheet("5 Hour", "included_5h")
    extract_items_from_sheet("1 Day", "included_1d")
    extract_items_from_sheet("2 Day", "included_2d")

    masterpieces = list(merged.values())
    # Sort by building, room, and inclusion (5h first, then 1d, then 2d)
    masterpieces.sort(key=lambda x: (x["building"], not x["included_5h"], not x["included_1d"], not x["included_2d"], x["must_see_item"]))
    for idx, item in enumerate(masterpieces, 1):
        item["rank"] = idx

    return masterpieces

async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

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
        items = process_excel(EXCEL_PATH)
        print(f"Found {len(items)} masterpieces across 5h, 1d, 2d itineraries.")

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
