"""
Seed Musée d'Orsay masterpieces and opening hours into the database.

Usage (from backend root):
    python -m app.scripts.seed_musee_dorsay
"""

import asyncio
import os
import re
import sys
import uuid
import pandas as pd
from sqlalchemy import select

# ── Bootstrap the app so models / settings are importable ────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from app.core.database import engine, async_session, Base  # noqa: E402
from app.models.museum import Museum, MuseumMasterpiece  # noqa: E402

APP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "nexaround_app"))
MUSEE_DORSAY_XLSX = os.environ.get(
    "MUSEE_DORSAY_XLSX",
    os.path.join(APP_DIR, "Musee_dOrsay_5hr_1day_Itineraries.xlsx")
)


def guess_category_dorsay(item_name: str, artist: str | None, location: str) -> str:
    """Classify items to display rich icons and theme colors in the app UI."""
    item_lower = (item_name or "").lower()
    artist_lower = (artist or "").lower()
    loc_lower = (location or "").lower()

    if any(x in artist_lower for x in ["monet", "renoir", "degas", "manet", "pissarro", "sisley", "morisot", "caillebotte", "fantin-latour", "bazille"]):
        return "Impressionist Painting"
    if any(x in artist_lower for x in ["van gogh", "gauguin", "cezanne", "cézanne", "seurat", "signac", "toulouse-lautrec", "redon", "vuillard", "bonnard"]):
        return "Post-Impressionist Painting"
    if any(x in artist_lower for x in ["rodin", "carpeaux", "maillol", "claudel", "bourdelle", "barye", "pompon", "sculpture"]) or "statue" in item_lower or "sculpture" in item_lower or "bronze" in item_lower or "marble" in item_lower:
        return "Sculpture"
    if any(x in artist_lower for x in ["guimard", "majorelle", "lalique", "galle", "gallé", "tiffany", "art nouveau"]) or "furniture" in item_lower or "decorative" in item_lower or "clock" in item_lower:
        return "Art Nouveau & Decorative Arts"
    if any(x in artist_lower for x in ["courbet", "millet", "daumier", "corot", "rousseau", "barbizon"]) or "realism" in loc_lower:
        return "Realist & Barbizon Painting"
    
    if "impressionnism" in loc_lower or "impression" in loc_lower:
        return "Impressionist Painting"
    if "post-impressionnism" in loc_lower:
        return "Post-Impressionist Painting"
    if "sculpture" in loc_lower:
        return "Sculpture"
    
    return "Museum Masterpiece"


def clean_text(text: str) -> str:
    """Clean text, replace unicode dash variations, and fix common accents."""
    text = str(text).strip()
    text = re.sub(r"\s*[\ufffd\u2013\u2014–—]\s*", " - ", text)
    text = text.replace("\ufffd", "é")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def parse_highlight(raw_text: str) -> tuple[str | None, str]:
    """Parse 'Artist - Masterpiece' or return (None, Masterpiece)."""
    text = clean_text(raw_text)
    if " - " in text:
        parts = text.split(" - ", 1)
        artist = parts[0].strip()
        item = parts[1].strip()
        if artist and item:
            return artist, item
    return None, text


def process_musee_dorsay(file_path: str):
    """Reads and merges 5-Hour (40 Stops) and 1-Day (60 Stops) itineraries."""
    if not os.path.exists(file_path):
        print(f"❌ Musée d'Orsay Excel file not found at: {file_path}")
        return None

    xl = pd.ExcelFile(file_path)
    merged = {}

    sheet_5h = "5 Hour (40 Stops)" if "5 Hour (40 Stops)" in xl.sheet_names else xl.sheet_names[0]
    sheet_1d = "1 Day (60 Stops)" if "1 Day (60 Stops)" in xl.sheet_names else (xl.sheet_names[1] if len(xl.sheet_names) > 1 else sheet_5h)

    # 1. Process 5-Hour sheet
    df_5h = pd.read_excel(xl, sheet_5h)
    for idx, row in df_5h.iterrows():
        raw_highlight = str(row.get("Highlight", "")).strip()
        if not raw_highlight or raw_highlight == "nan":
            continue

        artist, item_name = parse_highlight(raw_highlight)
        level_val = str(row.get("Level", "")).strip()
        building_val = f"Level {level_val}" if level_val and not level_val.lower().startswith("level") else (level_val or "Main Building")
        room_val = str(row.get("Official Location", "")).strip()
        
        key = item_name.lower()
        rank_val = int(row.get("Stop", idx + 1))

        merged[key] = {
            "rank": rank_val,
            "building": building_val,
            "room_gallery": room_val,
            "must_see_item": item_name,
            "artist": artist,
            "category": guess_category_dorsay(item_name, artist, room_val),
            "description": None,
            "included_5h": True,
            "included_1d": False,
            "included_2d": False,
        }

    # 2. Process 1-Day sheet
    df_1d = pd.read_excel(xl, sheet_1d)
    for idx, row in df_1d.iterrows():
        raw_highlight = str(row.get("Highlight", "")).strip()
        if not raw_highlight or raw_highlight == "nan":
            continue

        artist, item_name = parse_highlight(raw_highlight)
        level_val = str(row.get("Level", "")).strip()
        building_val = f"Level {level_val}" if level_val and not level_val.lower().startswith("level") else (level_val or "Main Building")
        room_val = str(row.get("Official Location", "")).strip()

        key = item_name.lower()
        rank_val = int(row.get("Stop", idx + 1))

        if key in merged:
            merged[key]["included_1d"] = True
        else:
            merged[key] = {
                "rank": rank_val,
                "building": building_val,
                "room_gallery": room_val,
                "must_see_item": item_name,
                "artist": artist,
                "category": guess_category_dorsay(item_name, artist, room_val),
                "description": None,
                "included_5h": False,
                "included_1d": True,
                "included_2d": False,
            }

    sorted_items = list(merged.values())
    sorted_items.sort(key=lambda x: (not x["included_5h"], x["rank"]))

    for index, item in enumerate(sorted_items, 1):
        item["rank"] = index

    return sorted_items


async def seed_dorsay(slug: str = "musee-dorsay", file_path: str = MUSEE_DORSAY_XLSX):
    masterpieces = process_musee_dorsay(file_path)

    async with async_session() as session:
        result = await session.execute(select(Museum).where(Museum.slug == slug))
        museum = result.scalar_one_or_none()

        if not museum:
            print(f"➕ Creating new Museum entry for Musée d'Orsay ({slug})...")
            museum = Museum(
                id=uuid.uuid4(),
                slug=slug,
                name="Musée d'Orsay",
                city="Paris",
                country="France",
                annual_visitors=3751000,
                rank=16,
            )
            session.add(museum)
            await session.flush()

        print(f"⚙️ Updating details and schedule for {museum.name} ({slug})...")

        # Update metadata and schedules
        museum.website = "https://www.musee-orsay.fr/en"
        museum.ticket_url = "https://www.musee-orsay.fr/en/visit/tickets-pricing"
        museum.latitude = 48.859967
        museum.longitude = 2.326561
        museum.image_url = "https://images.unsplash.com/photo-1597910037310-7dd8ddb93e24"
        museum.opening_hours = (
            "Tuesday, Wednesday, Friday, Saturday, Sunday: 9:30 AM – 6:00 PM | "
            "Thursday: 9:30 AM – 9:45 PM (Late Night Opening) | "
            "Monday: Closed"
        )
        museum.closing_hours = (
            "Closed every Monday, May 1, and December 25. "
            "Last admission to museum at 5:00 PM (9:00 PM on Thursdays), "
            "last admission to exhibitions at 5:15 PM (9:00 PM on Thursdays), "
            "galleries close at 5:30 PM (9:15 PM on Thursdays)."
        )

        if masterpieces:
            # Clear existing masterpieces for idempotency
            existing = await session.execute(
                select(MuseumMasterpiece).where(MuseumMasterpiece.museum_id == museum.id)
            )
            for old in existing.scalars().all():
                await session.delete(old)
            await session.flush()

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
                    included_2d=item["included_2d"],
                )
                session.add(mp)
                count += 1
            print(f"✅ Successfully seeded {count} masterpieces for Musée d'Orsay!")

        await session.commit()
        print(f"🎉 Musée d'Orsay updated successfully!")


async def main():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    await seed_dorsay()
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
