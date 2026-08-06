"""
Fetch Google Places photo for Musée d'Orsay and update DB & seed files.

Usage:
    docker exec nexaround_backend-api-1 python -m app.scripts.update_musee_dorsay_photo
"""

import asyncio
import os
import sys
from sqlalchemy import select, update

# Bootstrap path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine
from app.models.museum import Museum
from app.services import google_places_client, photo_cache_service


async def main():
    print("🔎 Searching Google Places for 'Musée d'Orsay Paris'...")
    photo_ref = None
    
    try:
        places = await google_places_client.text_search(
            query="Musée d'Orsay Paris",
            latitude=48.859967,
            longitude=2.326561,
        )
        print(f"Found {len(places)} results from Google Places.")
        if places:
            photos = places[0].get("photos") or []
            if photos:
                photo_ref = photos[0].get("name") or photos[0].get("photo_reference")
                print(f"📸 Got Google Photo Reference: {photo_ref[:60]}...")
    except Exception as e:
        print(f"⚠️ Google Places API search error: {e}")

    image_url = None
    if photo_ref:
        image_url = f"/api/v1/places/photo?ref={photo_ref}"
        print(f"Pre-caching photo bytes via photo_cache_service...")
        try:
            cached_path = await photo_cache_service.get_or_fetch(photo_ref, maxwidth=1200)
            if cached_path:
                print(f"✅ Photo pre-cached at: {cached_path}")
            else:
                print("⚠️ Photo pre-cache returned None (Google Places key missing or fetch failed).")
        except Exception as e:
            print(f"⚠️ Photo caching error: {e}")
    else:
        # Fallback to high quality Wikimedia Commons image if Google Places API is unavailable
        image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/0/08/Mus%C3%A9e_d%27Orsay_nuit.jpg/1280px-Mus%C3%A9e_d%27Orsay_nuit.jpg"
        print(f"Using fallback high-res image URL: {image_url}")

    print(f"Updating DB image_url to: {image_url}")
    async with async_session() as session:
        result = await session.execute(
            update(Museum)
            .where(Museum.slug == "musee-dorsay")
            .values(image_url=image_url)
        )
        await session.commit()
        print("✅ Database updated successfully!")

    await engine.dispose()
    return image_url


if __name__ == "__main__":
    asyncio.run(main())
