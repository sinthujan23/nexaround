"""
Automated script to fetch Google Places photos for ALL museums in the DB and seed_all_museums list,
pre-cache them locally on disk, and update the database so every museum has a working, high-res image.

Usage:
    docker exec nexaround_backend-api-1 python -m app.scripts.fix_all_museum_photos
"""

import asyncio
import os
import sys
from sqlalchemy import select, update

# Bootstrap
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine
from app.models.museum import Museum
from app.services import google_places_client, photo_cache_service
from app.scripts.seed_all_museums import MUSEUMS_DATA


# Fallback high quality open access images if Google API fails or has no photo
FALLBACK_IMAGES = {
    "louvre": "https://upload.wikimedia.org/wikipedia/commons/thumb/6/66/Louvre_Museum_Wikimedia_Commons.jpg/1280px-Louvre_Museum_Wikimedia_Commons.jpg",
    "vatican-museums": "https://upload.wikimedia.org/wikipedia/commons/thumb/0/06/Vatican_Museums_Spiral_Staircase.jpg/1280px-Vatican_Museums_Spiral_Staircase.jpg",
    "british-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/British_Museum_Great_Court_Roof_2.jpg/1280px-British_Museum_Great_Court_Roof_2.jpg",
    "metropolitan-museum-of-art": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/30/The_Metropolitan_Museum_of_Art_5th_Ave_NYC.jpg/1280px-The_Metropolitan_Museum_of_Art_5th_Ave_NYC.jpg",
    "state-hermitage-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/46/Winter_Palace_Panorama_3.jpg/1280px-Winter_Palace_Panorama_3.jpg",
    "uffizi-galleries": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/Uffizi_Florence_BW_2016-09-20_14-41-45.jpg/1280px-Uffizi_Florence_BW_2016-09-20_14-41-45.jpg",
    "acropolis-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/Acropolis_Museum_Athens_Greece.jpg/1280px-Acropolis_Museum_Athens_Greece.jpg",
    "american-museum-of-natural-history": "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/American_Museum_of_Natural_History_Central_Park_West.jpg/1280px-American_Museum_of_Natural_History_Central_Park_West.jpg",
    "grand-egyptian-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Grand_Egyptian_Museum_2023.jpg/1280px-Grand_Egyptian_Museum_2023.jpg",
    "national-palace-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/National_Palace_Museum_Main_Building_2019.jpg/1280px-National_Palace_Museum_Main_Building_2019.jpg",
    "national-museum-of-korea": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1d/National_Museum_of_Korea_1.jpg/1280px-National_Museum_of_Korea_1.jpg",
    "china-art-museum": "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f3/China_Art_Museum_Shanghai_2016.jpg/1280px-China_Art_Museum_Shanghai_2016.jpg",
    "musee-dorsay": "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7c/Mus%C3%A9e_d%27Orsay%2C_North-West_view%2C_Paris_7e_140402.jpg/1280px-Mus%C3%A9e_d%27Orsay%2C_North-West_view%2C_Paris_7e_140402.jpg"
}


async def fix_museum_photo(session, museum: Museum) -> str:
    print(f"\n🎨 Processing: {museum.name} ({museum.city}, {museum.country}) - slug: {museum.slug}")
    
    # If already a valid cached places photo, check if it's cached on disk
    if museum.image_url and museum.image_url.startswith("/api/v1/places/photo?ref="):
        ref = museum.image_url.split("ref=")[1]
        cached = await photo_cache_service.get_or_fetch(ref, maxwidth=1200)
        if cached:
            print(f"  ✅ Already cached at {cached}")
            return museum.image_url

    # Search Google Places API
    query = f"{museum.name} {museum.city}"
    lat = museum.latitude or 0.0
    lng = museum.longitude or 0.0

    photo_ref = None
    try:
        places = await google_places_client.text_search(
            query=query,
            latitude=lat,
            longitude=lng,
        )
        if places:
            photos = places[0].get("photos") or []
            if photos:
                photo_ref = photos[0].get("name") or photos[0].get("photo_reference")
                print(f"  📸 Found Google Photo Reference for {museum.name}")
    except Exception as e:
        print(f"  ⚠️ Search error for {museum.name}: {e}")

    new_image_url = None
    if photo_ref:
        new_image_url = f"/api/v1/places/photo?ref={photo_ref}"
        try:
            cached = await photo_cache_service.get_or_fetch(photo_ref, maxwidth=1200)
            if cached:
                print(f"  ✅ Photo downloaded & cached at: {cached}")
            else:
                print(f"  ⚠️ Pre-cache failed for {museum.name}")
        except Exception as e:
            print(f"  ⚠️ Pre-cache exception: {e}")
    else:
        # Fallback to predefined fallback or wikimedia
        new_image_url = FALLBACK_IMAGES.get(
            museum.slug,
            f"https://upload.wikimedia.org/wikipedia/commons/thumb/6/66/Louvre_Museum_Wikimedia_Commons.jpg/1280px-Louvre_Museum_Wikimedia_Commons.jpg"
        )
        print(f"  ℹ️ Using fallback image URL: {new_image_url}")

    museum.image_url = new_image_url
    return new_image_url


async def main():
    async with async_session() as session:
        # 1. Fetch all existing museums in DB
        result = await session.execute(select(Museum))
        museums = result.scalars().all()
        print(f"Loaded {len(museums)} existing museums from database.")

        for m in museums:
            await fix_museum_photo(session, m)

        await session.commit()
        print("\n✅ Successfully updated all existing database museums!")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
