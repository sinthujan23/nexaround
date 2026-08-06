"""
Seed script for Mevlana Museum (3-Hour & 1-Day Itineraries, 14 Stops).

Usage:
    docker exec nexaround_backend-api-1 python -m app.scripts.seed_mevlana
"""

import asyncio
import os
import sys
import uuid
from sqlalchemy import select, update, delete, text
from sqlalchemy.ext.asyncio import AsyncSession

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine, Base
from app.models.museum import Museum, MuseumMasterpiece
from app.services import google_places_client, photo_cache_service

MEVLANA_META = {
    "slug": "mevlana-museum",
    "name": "Mevlana Museum",
    "city": "Konya",
    "country": "Türkiye",
    "annual_visitors": 3048000,
    "rank": 26,
    "website": "https://muze.gov.tr/muze-detay?SectionId=MEV01&DistId=MEV",
    "opening_hours": "Summer: 9:00 AM - 7:00 PM\nWinter: 9:00 AM - 5:00 PM",
    "closing_hours": "Summer: 7:00 PM / Winter: 5:00 PM",
    "latitude": 37.870685,
    "longitude": 32.505021,
}

MASTERPIECES = [
    {
        "rank": 1,
        "building": "Entrance & Courtyard",
        "room_gallery": "Main Entrance",
        "must_see_item": "Chelebi Gate",
        "artist": "Mevlevi Order Craftsmen",
        "category": "Architecture",
        "description": "The historic ornate main entrance gate leading into the sacred Mevlana Museum complex.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 2,
        "building": "Entrance & Courtyard",
        "room_gallery": "Central Courtyard",
        "must_see_item": "Museum Courtyard",
        "artist": "Ottoman Architects",
        "category": "Courtyard",
        "description": "The peaceful central courtyard surrounding the fountain and mausoleum entrance.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 3,
        "building": "Grounds & Gardens",
        "room_gallery": "Outer Grounds",
        "must_see_item": "Rose Garden",
        "artist": "Sultan Alaeddin Keykubad",
        "category": "Garden",
        "description": "The fragrant rose garden originally gifted by Seljuk Sultan Alaeddin Keykubad to Rumi's father.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 4,
        "building": "Grounds & Gardens",
        "room_gallery": "Courtyard Center",
        "must_see_item": "Ablution Fountain (Shadirvan)",
        "artist": "Sultan Yavuz Selim",
        "category": "Architecture",
        "description": "The elegant covered 16th-century ablution fountain built by Ottoman Sultan Yavuz Selim.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 5,
        "building": "Main Complex & Mausoleum",
        "room_gallery": "Exterior & Roofline",
        "must_see_item": "Turquoise (Green) Dome (Kubbe-i Hadra)",
        "artist": "Badr al-Din Tabrizi",
        "category": "Architecture",
        "description": "The iconic 13th-century turquoise-tiled fluted tower standing over Rumi's tomb.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 6,
        "building": "Main Complex & Mausoleum",
        "room_gallery": "Mausoleum Entrance",
        "must_see_item": "Ornate Antique Doors",
        "artist": "Seljuk & Ottoman Master Woodcarvers",
        "category": "Woodworking",
        "description": "Intricately carved silver and wooden doors adorned with calligraphic inscriptions.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 7,
        "building": "Main Complex & Mausoleum",
        "room_gallery": "Main Shrine",
        "must_see_item": "Mausoleum of Rumi (Tomb of Mevlana Celaleddin-i Rumi)",
        "artist": "Seljuk & Ottoman Masters",
        "category": "Shrine & Mausoleum",
        "description": "The sacred tomb chamber of Jalal al-Din Muhammad Rumi, covered in gold-embroidered velvet.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 8,
        "building": "Dervish Lodge & Sema Hall",
        "room_gallery": "Tekke Quarters",
        "must_see_item": "Dervish Lodge (Tekke)",
        "artist": "Mevlevi Order",
        "category": "Historical Quarters",
        "description": "The historical living cells and quarters where Mevlevi dervishes studied and practiced.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 9,
        "building": "Dervish Lodge & Sema Hall",
        "room_gallery": "Ceremonial Hall",
        "must_see_item": "Sema Hall (Semahane)",
        "artist": "Sultan Suleiman the Magnificent",
        "category": "Ceremonial Hall",
        "description": "The grand hall built under Suleiman the Magnificent where the sacred Whirling Dervish Sema rituals take place.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 10,
        "building": "Treasury & Manuscripts",
        "room_gallery": "Manuscript Gallery",
        "must_see_item": "Manuscript Room",
        "artist": "Historic Calligraphers & Illuminators",
        "category": "Manuscripts",
        "description": "Includes historic illuminated Qur'ans, original hand-copied poetry manuscripts of Rumi's Masnavi and Divan-i Kabir.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 11,
        "building": "Treasury & Artifacts",
        "room_gallery": "Artifact Exhibition",
        "must_see_item": "Dervish Lodge Artifacts",
        "artist": "Mevlevi Order Craftsmen",
        "category": "Relics & Artifacts",
        "description": "Exhibits of historic dervish robes, tall conical hats (sikke), musical instruments (ney, kudüm), and personal items.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 12,
        "building": "Tombs & Monuments",
        "room_gallery": "Courtyard Tombs",
        "must_see_item": "Hurrem Pasha's Tomb",
        "artist": "Ottoman Master Builders",
        "category": "Mausoleum",
        "description": "The octagonal 16th-century stone tomb of Hurrem Pasha, Governor of Karaman.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 13,
        "building": "Architecture & Views",
        "room_gallery": "Courtyard Vantage Point",
        "must_see_item": "View of Selimiye Mosque",
        "artist": "Mimar Sinan Guild",
        "category": "Architecture",
        "description": "Stunning view of the adjacent 16th-century Ottoman Selimiye Mosque from the museum courtyard.",
        "included_3h": True,
        "included_1d": True,
    },
    {
        "rank": 14,
        "building": "Cultural Performance",
        "room_gallery": "Semahane / Cultural Center",
        "must_see_item": "Whirling Dervish (Sema) Performance",
        "artist": "Mevlevi Sema Ensemble",
        "category": "Live Performance",
        "description": "The spiritual Whirling Dervish Sema ceremony representing spiritual ascension and universal love.",
        "included_3h": True,
        "included_1d": True,
    },
]


async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text("ALTER TABLE museum_masterpieces ADD COLUMN IF NOT EXISTS included_3h BOOLEAN DEFAULT FALSE;"))

    async with async_session() as session:
        # Check if Mevlana Museum exists
        result = await session.execute(
            select(Museum).where(Museum.slug == MEVLANA_META["slug"])
        )
        museum = result.scalar_one_or_none()

        # Search Google Places photo for Mevlana Museum if not present or missing image_data
        photo_bytes = None
        if museum and museum.image_data:
            photo_bytes = museum.image_data
            image_url = f"/api/v1/museums/{museum.slug}/image"
        else:
            print("📸 Searching Google Places API for Mevlana Museum photo...")
            try:
                places = await google_places_client.text_search(
                    query="Mevlana Museum Konya",
                    latitude=MEVLANA_META["latitude"],
                    longitude=MEVLANA_META["longitude"],
                )
                if places:
                    photos = places[0].get("photos") or []
                    if photos:
                        ref = photos[0].get("name") or photos[0].get("photo_reference")
                        if ref:
                            data, ctype = await google_places_client.fetch_photo_bytes(ref, maxwidth=1200)
                            photo_bytes = data
                            print(f"✅ Fetched {len(photo_bytes) // 1024} KB photo from Google Places")
            except Exception as e:
                print(f"⚠️ Photo fetch error: {e}")

            image_url = f"/api/v1/museums/{MEVLANA_META['slug']}/image"

        if museum is None:
            museum = Museum(
                id=uuid.uuid4(),
                slug=MEVLANA_META["slug"],
                name=MEVLANA_META["name"],
                city=MEVLANA_META["city"],
                country=MEVLANA_META["country"],
                annual_visitors=MEVLANA_META["annual_visitors"],
                rank=MEVLANA_META["rank"],
                image_url=image_url,
                image_data=photo_bytes,
                image_content_type="image/jpeg",
                website=MEVLANA_META["website"],
                opening_hours=MEVLANA_META["opening_hours"],
                closing_hours=MEVLANA_META["closing_hours"],
                latitude=MEVLANA_META["latitude"],
                longitude=MEVLANA_META["longitude"],
            )
            session.add(museum)
            await session.flush()
            print(f"Added Museum: {museum.name}")
        else:
            museum.opening_hours = MEVLANA_META["opening_hours"]
            museum.closing_hours = MEVLANA_META["closing_hours"]
            if photo_bytes:
                museum.image_data = photo_bytes
                museum.image_url = image_url
            print(f"Updated Museum: {museum.name}")

        # Clear existing masterpieces for Mevlana Museum to replace with full 14 stops
        await session.execute(
            delete(MuseumMasterpiece).where(MuseumMasterpiece.museum_id == museum.id)
        )

        for mp in MASTERPIECES:
            item = MuseumMasterpiece(
                id=uuid.uuid4(),
                museum_id=museum.id,
                rank=mp["rank"],
                building=mp["building"],
                room_gallery=mp["room_gallery"],
                must_see_item=mp["must_see_item"],
                artist=mp["artist"],
                category=mp["category"],
                description=mp["description"],
                included_3h=mp["included_3h"],
                included_5h=False,
                included_1d=mp["included_1d"],
                included_2d=False,
            )
            session.add(item)

        await session.commit()
        print(f"✅ Successfully seeded Mevlana Museum with {len(MASTERPIECES)} stops (3-Hour & 1-Day Itinerary)!")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed())
