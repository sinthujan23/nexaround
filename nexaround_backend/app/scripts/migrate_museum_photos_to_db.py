"""
Migrate museum photos from disk cache into permanent PostgreSQL storage.

1. Adds image_data + image_content_type columns (if not already present)
2. For each museum, reads its cached photo from disk (or re-fetches from Google)
3. Stores the JPEG bytes directly in the image_data column
4. Updates image_url to point to /api/v1/museums/{slug}/image

Usage:
    docker exec nexaround_backend-api-1 python -m app.scripts.migrate_museum_photos_to_db
"""

import asyncio
import os
import sys
from pathlib import Path
from sqlalchemy import select, text

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine, Base
from app.models.museum import Museum
from app.services import google_places_client, photo_cache_service


CACHE_DIR = Path("app/static/photo_cache")


async def main():
    # 1. Add columns if they don't exist
    async with engine.begin() as conn:
        # Check if columns exist
        result = await conn.execute(text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name = 'museums' AND column_name = 'image_data'"
        ))
        if result.first() is None:
            print("Adding image_data column...")
            await conn.execute(text(
                "ALTER TABLE museums ADD COLUMN image_data BYTEA"
            ))
            print("Adding image_content_type column...")
            await conn.execute(text(
                "ALTER TABLE museums ADD COLUMN image_content_type VARCHAR(50) DEFAULT 'image/jpeg'"
            ))
            print("✅ Columns added!")
        else:
            print("✅ Columns already exist")

    # 2. For each museum, load photo bytes and store in DB
    async with async_session() as session:
        result = await session.execute(select(Museum))
        museums = result.scalars().all()
        print(f"\n📊 Processing {len(museums)} museums...")

        stored = 0
        failed = []

        for m in museums:
            print(f"\n🎨 {m.name} ({m.slug})")

            photo_bytes = None
            content_type = "image/jpeg"

            # Try to read from disk cache first
            if m.image_url and m.image_url.startswith("/api/v1/places/photo?ref="):
                ref = m.image_url.split("ref=")[1]
                cached_path = photo_cache_service.cached_path(ref, 1200)
                if cached_path.exists() and cached_path.stat().st_size > 0:
                    photo_bytes = cached_path.read_bytes()
                    print(f"  📁 Read {len(photo_bytes) // 1024} KB from disk cache")

            # If not on disk, try fetching from Google
            if not photo_bytes:
                print(f"  🔎 Fetching from Google Places...")
                try:
                    places = await google_places_client.text_search(
                        query=f"{m.name} {m.city} museum",
                        latitude=m.latitude or 0.0,
                        longitude=m.longitude or 0.0,
                    )
                    if places:
                        photos = places[0].get("photos") or []
                        if photos:
                            ref = photos[0].get("name") or photos[0].get("photo_reference")
                            if ref:
                                data, ctype = await google_places_client.fetch_photo_bytes(ref, maxwidth=1200)
                                photo_bytes = data
                                content_type = ctype
                                print(f"  📸 Fetched {len(photo_bytes) // 1024} KB from Google")
                except Exception as e:
                    print(f"  ⚠️ Fetch error: {e}")

            if photo_bytes:
                m.image_data = photo_bytes
                m.image_content_type = content_type
                m.image_url = f"/api/v1/museums/{m.slug}/image"
                stored += 1
                print(f"  ✅ Stored in DB ({len(photo_bytes) // 1024} KB)")
            else:
                failed.append(m.name)
                print(f"  ❌ No photo available")

        await session.commit()

        print(f"\n{'='*60}")
        print(f"✅ {stored}/{len(museums)} museum photos stored permanently in DB")
        if failed:
            print(f"⚠️ Failed: {', '.join(failed)}")
        print(f"{'='*60}")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
