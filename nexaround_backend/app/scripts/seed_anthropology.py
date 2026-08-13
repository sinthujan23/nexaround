"""
Seed script for National Museum of Anthropology (Mexico City) masterpieces and metadata.
Includes 5-Hour (8 stops), 1-Day (13 stops), and 2-Day (23 stops) itinerary stops from National_Museum_of_Anthropology_Itineraries_Full.xlsx.

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

POSSIBLE_EXCEL_PATHS = [
    os.environ.get("ANTHROPOLOGY_XLSX", ""),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "National_Museum_of_Anthropology_Itineraries_Full.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "National_Museum_of_Anthropology_Itineraries_Full (1).xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "National_Museum_of_Anthropology_Itineraries_Full.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "nexaround_app", "National_Museum_of_Anthropology_Itineraries_Full.xlsx")),
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "nexaround_backend", "app", "scripts", "National_Museum_of_Anthropology_Itineraries_Full.xlsx")),
]

def find_excel_file():
    for p in POSSIBLE_EXCEL_PATHS:
        if p and os.path.exists(p):
            return p
    return ""

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
    else:
        building = "Ground Floor - Archaeology"
        category = "Origins & Archaeology"
    return building, category

def guess_artist(room_name, highlights_raw):
    room_lower = (room_name or "").lower()
    item_lower = (highlights_raw or "").lower()

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
    stop_order = {}

    def extract_items_from_sheet(sheet_name, flag_name, priority):
        if sheet_name not in xl.sheet_names:
            return
        df = pd.read_excel(xl, sheet_name)
        for _, row in df.iterrows():
            stop_num = row.get("Stop")
            
            # Support 'Area' (from Excel) or 'Room'
            area_name = row.get("Area") if pd.notna(row.get("Area")) else row.get("Room", "")
            area_name = str(area_name or "").strip()
            if not area_name or area_name.lower() in ["nan", "none"]:
                continue

            overview = str(row.get("Overview", "")).strip()
            if overview.lower() in ["nan", "none"]:
                overview = ""

            highlights_raw = str(row.get("Key Highlights", "")).strip()
            if highlights_raw.lower() in ["nan", "none"]:
                highlights_raw = ""

            desc = overview
            if highlights_raw:
                if desc:
                    desc += f"\n\nKey Highlights: {highlights_raw}"
                else:
                    desc = f"Key Highlights: {highlights_raw}"

            building_val, cat_val = get_building_and_category(area_name)
            key = area_name.lower()

            if key not in stop_order:
                stop_order[key] = priority * 100 + (stop_num if pd.notna(stop_num) else 99)

            if key in merged:
                merged[key][flag_name] = True
                if desc and len(desc) > len(merged[key]["description"]):
                    merged[key]["description"] = desc
            else:
                merged[key] = {
                    "building": building_val,
                    "room_gallery": area_name,
                    "must_see_item": area_name,
                    "artist": guess_artist(area_name, highlights_raw),
                    "category": cat_val,
                    "description": desc,
                    "included_3h": False,
                    "included_5h": False,
                    "included_1d": False,
                    "included_2d": False,
                    "_order": stop_order[key],
                }
                merged[key][flag_name] = True

    extract_items_from_sheet("5 Hour", "included_5h", priority=1)
    extract_items_from_sheet("1 Day", "included_1d", priority=2)
    extract_items_from_sheet("2 Day", "included_2d", priority=3)

    masterpieces = list(merged.values())
    masterpieces.sort(key=lambda x: x["_order"])
    for idx, item in enumerate(masterpieces, 1):
        item["rank"] = idx
        del item["_order"]

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

        excel_path = find_excel_file()
        print(f"Using Excel file at: {excel_path}")

        # 3. Process excel and insert masterpieces
        items = process_excel(excel_path)
        print(f"Found {len(items)} stop items across 5h, 1d, 2d itineraries.")

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
        print(f"✅ Successfully seeded {added_count} stop items for {museum.name}!")

if __name__ == "__main__":
    asyncio.run(seed())
