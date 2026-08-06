"""
Seed ALL remaining museums into the DB, fetch their Google Places photos,
cache them on disk permanently, and store the image_url in the database.

This ensures every museum in the master list has a self-hosted, cached photo.

Usage:
    docker exec nexaround_backend-api-1 python -m app.scripts.seed_and_cache_all_museum_photos
"""

import asyncio
import os
import sys
import uuid
from sqlalchemy import select

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from app.core.database import async_session, engine, Base
from app.models.museum import Museum
from app.services import google_places_client, photo_cache_service
from app.scripts.seed_all_museums import MUSEUMS_DATA


async def fetch_and_cache_photo(name: str, city: str) -> str | None:
    """Search Google Places for a museum, fetch its best photo, cache it, return the image_url."""
    query = f"{name} {city} museum"
    try:
        places = await google_places_client.text_search(
            query=query, latitude=0.0, longitude=0.0,
        )
        if not places:
            print(f"    ⚠️ No Google Places results for '{query}'")
            return None

        photos = places[0].get("photos") or []
        if not photos:
            print(f"    ⚠️ No photos for '{name}'")
            return None

        photo_ref = photos[0].get("name") or photos[0].get("photo_reference")
        if not photo_ref:
            print(f"    ⚠️ No photo reference for '{name}'")
            return None

        # Pre-cache the photo bytes on disk
        cached = await photo_cache_service.get_or_fetch(photo_ref, maxwidth=1200)
        if cached:
            image_url = f"/api/v1/places/photo?ref={photo_ref}"
            print(f"    ✅ Cached ({cached.stat().st_size // 1024} KB)")
            return image_url
        else:
            print(f"    ⚠️ Cache fetch returned None")
            return None

    except Exception as e:
        print(f"    ⚠️ Error: {e}")
        return None


async def main():
    # Ensure tables exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        # Get existing museum slugs
        result = await session.execute(select(Museum.slug))
        existing_slugs = {row[0] for row in result.all()}
        print(f"📊 {len(existing_slugs)} museums already in DB")
        print(f"📊 {len(MUSEUMS_DATA)} museums in master list")

        new_count = 0
        updated_count = 0
        failed = []

        for i, m_data in enumerate(MUSEUMS_DATA, 1):
            slug = m_data["slug"]
            name = m_data["name"]
            city = m_data["city"]

            if slug in existing_slugs:
                # Museum exists — check if it already has a cached photo
                result = await session.execute(
                    select(Museum).where(Museum.slug == slug)
                )
                museum = result.scalar_one()
                if museum.image_url and museum.image_url.startswith("/api/v1/places/photo?ref="):
                    print(f"[{i}/{len(MUSEUMS_DATA)}] ✅ {name} — already cached")
                    continue

                # Existing museum needs a photo
                print(f"[{i}/{len(MUSEUMS_DATA)}] 🔄 {name} — fetching photo...")
                image_url = await fetch_and_cache_photo(name, city)
                if image_url:
                    museum.image_url = image_url
                    updated_count += 1
                else:
                    failed.append(name)
            else:
                # New museum — create and fetch photo
                print(f"[{i}/{len(MUSEUMS_DATA)}] 🆕 {name} — seeding + fetching photo...")
                image_url = await fetch_and_cache_photo(name, city)
                if not image_url:
                    failed.append(name)

                museum = Museum(
                    id=uuid.uuid4(),
                    slug=slug,
                    name=name,
                    city=city,
                    country=m_data["country"],
                    annual_visitors=m_data["visitors"],
                    rank=m_data["rank"],
                    image_url=image_url,
                )
                session.add(museum)
                new_count += 1

            # Commit in batches of 5 to avoid losing progress
            if (new_count + updated_count) % 5 == 0:
                await session.commit()

        await session.commit()

        print(f"\n{'='*60}")
        print(f"✅ {new_count} new museums seeded")
        print(f"✅ {updated_count} existing museums updated with photos")
        if failed:
            print(f"⚠️ {len(failed)} museums failed to get photos:")
            for f in failed:
                print(f"   - {f}")
        print(f"{'='*60}")

    # Final count
    async with async_session() as session:
        result = await session.execute(select(Museum))
        all_museums = result.scalars().all()
        cached = sum(1 for m in all_museums if m.image_url and m.image_url.startswith("/api/v1/places/photo"))
        print(f"\n📊 Final: {len(all_museums)} total museums, {cached} with cached photos")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
