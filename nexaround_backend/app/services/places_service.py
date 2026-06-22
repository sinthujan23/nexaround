"""Top-level Places service: cache-first, Google as fallback."""
import math
from typing import Optional
from app.services import google_places_client, place_cache_service
from app.schemas.place import PlaceResponse, PlacesNearbyResponse
from app.core.database import async_session
from app.repositories.attraction_repository import AttractionRepository
from app.models.category import Category
from app.models.attraction import Attraction
from app.utils.geo_utils import create_point, get_lat_lng
from sqlalchemy import select


def _photo_url(photo_reference: str) -> str:
    """Public URL the mobile app should hit to retrieve a photo.

    Routes through our backend so the Google API key never leaves the server.
    """
    return f"/api/v1/places/photo?ref={photo_reference}"


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371000.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(dlng / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(a))


def offset_lat_lng(lat: float, lng: float, bearing_deg: float, distance_m: float) -> tuple[float, float]:
    earth_r = 6371000.0
    ang_dist = distance_m / earth_r
    brng = math.radians(bearing_deg)
    lat1 = math.radians(lat)
    lng1 = math.radians(lng)
    
    lat2 = math.asin(
        math.sin(lat1) * math.cos(ang_dist) +
        math.cos(lat1) * math.sin(ang_dist) * math.cos(brng)
    )
    lng2 = lng1 + math.atan2(
        math.sin(brng) * math.sin(ang_dist) * math.cos(lat1),
        math.cos(ang_dist) - math.sin(lat1) * math.sin(lat2)
    )
    
    return math.degrees(lat2), ((math.degrees(lng2) + 540.0) % 360.0) - 180.0


def get_min_radius(radius: int) -> int:
    if radius == 5000:
        return 2000
    elif radius == 10000:
        return 2000
    elif radius == 15000:
        return 0
    elif radius == 25000:
        return 10000
    elif radius == 50000:
        return 25000
    return 0


def _enforce_distance_distribution(places: list[dict], radius_m: int) -> list[dict]:
    """Force a distributed mix of nearby and distant places to ensure variety.
    
    Requested distribution:
    - 5 places in 0-2 km
    - 5 places in 2-10 km
    - 5 places in 10-20 km
    - 5 places in 20-50 km
    """
    if radius_m < 10000:
        # For small radiuses, just return closest 20
        return sorted(places, key=lambda p: p.get("distance_m", 0))[:20]

    buckets = {"0_2": [], "2_10": [], "10_20": [], "20_50": []}
    
    for p in places:
        dist = p.get("distance_m", 0)
        if dist <= 2000:
            buckets["0_2"].append(p)
        elif dist <= 10000:
            buckets["2_10"].append(p)
        elif dist <= 20000:
            buckets["10_20"].append(p)
        else:
            buckets["20_50"].append(p)
            
    for k in buckets:
        buckets[k].sort(key=lambda p: p.get("distance_m", 0))
        
    result = []
    
    def take_up_to(bucket_key: str, n: int) -> list[dict]:
        taken = buckets[bucket_key][:n]
        buckets[bucket_key] = buckets[bucket_key][n:]
        return taken
        
    result.extend(take_up_to("0_2", 5))
    result.extend(take_up_to("2_10", 5))
    result.extend(take_up_to("10_20", 5))
    if radius_m >= 20000:
        result.extend(take_up_to("20_50", 5))
        
    # If we have less than 20 total, backfill from remaining closest places
    if len(result) < 20:
        remaining = []
        remaining.extend(buckets["0_2"])
        remaining.extend(buckets["2_10"])
        remaining.extend(buckets["10_20"])
        remaining.extend(buckets["20_50"])
        remaining.sort(key=lambda p: p.get("distance_m", 0))
        
        needed = 20 - len(result)
        result.extend(remaining[:needed])
        
    result.sort(key=lambda p: p.get("distance_m", 0))
    return result


async def seed_places_from_google_bg(
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
    use_legacy: bool,
    category_id: Optional[int],
    key: str,
):
    """Seed places from Google API in the background to avoid blocking the user request."""
    try:
        # 1. Check database first to see if revalidation is actually needed (close session immediately after)
        async with async_session() as session:
            repo = AttractionRepository(session)
            db_limit = 100 if radius <= 10000 else 200
            min_rad = get_min_radius(radius)
            
            # Fetch the latest set from DB to check if another worker has already seeded
            nearby_db_attractions = await repo.get_nearby(
                latitude=latitude,
                longitude=longitude,
                radius_m=float(radius),
                category_id=category_id,
                limit=db_limit,
                min_radius_m=float(min_rad) if min_rad > 0 else None
            )
            
            has_adequate_coverage = radius <= 2000 or any(dist >= radius * 0.7 for _, dist in nearby_db_attractions)
            if has_adequate_coverage:
                return

            existing_records = [
                (get_lat_lng(attr.location), attr.name)
                for attr, _ in nearby_db_attractions
            ]

        # 2. Call Google API outside the database session context (no connection held!)
        min_radius = get_min_radius(radius)
        if min_radius == 0:
            if use_legacy:
                raw_places = await google_places_client.nearby_search_legacy(
                    latitude=latitude,
                    longitude=longitude,
                    category=category,
                    radius=radius,
                )
            else:
                raw_places = await google_places_client.nearby_search(
                    latitude=latitude,
                    longitude=longitude,
                    category=category,
                    radius=radius,
                )
        else:
            mid = (min_radius + radius) / 2.0
            sample_radius = int((radius - min_radius) / 2.0)
            num_centers = 4
            bearings = [(360.0 / num_centers) * i for i in range(num_centers)]
            offset_coords = [offset_lat_lng(latitude, longitude, b, mid) for b in bearings]
            all_queries = [(latitude, longitude, radius)] + [
                (olat, olng, sample_radius) for olat, olng in offset_coords
            ]
            
            async def fetch_one(lat: float, lng: float, rad: int) -> list:
                try:
                    if use_legacy:
                        return await google_places_client.nearby_search_legacy(
                            latitude=lat,
                            longitude=lng,
                            category=category,
                            radius=rad,
                        )
                    else:
                        return await google_places_client.nearby_search(
                            latitude=lat,
                            longitude=lng,
                            category=category,
                            radius=rad,
                        )
                except Exception as e:
                    print(f"⚠️ Error fetching offset nearby search in get_nearby background: {e}")
                    return []
            
            import asyncio
            results = await asyncio.gather(*(fetch_one(lat, lng, rad) for lat, lng, rad in all_queries))
            raw_places = []
            seen_ids = set()
            for r_list in results:
                for p in r_list:
                    pid = p.get("id") or p.get("place_id")
                    if pid and pid not in seen_ids:
                        seen_ids.add(pid)
                        raw_places.append(p)

        if not raw_places:
            return

        if use_legacy:
            place_dicts = [
                google_places_client.to_place_dict_legacy(p, latitude, longitude, category, _photo_url)
                for p in raw_places
            ]
        else:
            if category == "Food & Drink":
                raw_places = google_places_client.filter_food(raw_places)
            elif category != "Beach":
                raw_places = raw_places[:100]
            place_dicts = [
                google_places_client.to_place_dict(p, latitude, longitude, category, _photo_url)
                for p in raw_places
            ]

        # 3. Open a new session to write/commit the fetched places
        async with async_session() as session:
            repo = AttractionRepository(session)
            
            for p in place_dicts:
                p_name = p.get("name")
                plat = p.get("latitude")
                plng = p.get("longitude")
                resolved_category = p.get("category_name")

                if not p_name or plat is None or plng is None:
                    continue

                existing_attraction = None
                for (alat, alng), name in existing_records:
                    dist = _haversine_m(plat, plng, alat, alng)
                    name_similarity = (name.lower() in p_name.lower()) or (p_name.lower() in name.lower())
                    if dist < 25.0 and name_similarity:
                        existing_attraction = True
                        break

                if not existing_attraction:
                    cat_id = None
                    if resolved_category:
                        stmt = select(Category).where(Category.name == resolved_category)
                        res = await session.execute(stmt)
                        cat_obj = res.scalar_one_or_none()
                        if not cat_obj:
                            cat_obj = Category(name=resolved_category, icon="place", color="#607D8B")
                            session.add(cat_obj)
                            await session.flush()
                        cat_id = cat_obj.id

                    # Check duplicate coordinates
                    dup_coords = False
                    for (alat, alng), _ in existing_records:
                        if abs(plat - alat) < 0.000001 and abs(plng - alng) < 0.000001:
                            dup_coords = True
                            break
                    if not dup_coords:
                        dup = await repo.find_duplicate_by_coordinates(plat, plng)
                        if dup:
                            dup_coords = True
                    is_active = not dup_coords

                    new_attr = Attraction(
                        name=p_name,
                        description=p.get("description") or "",
                        location=create_point(plat, plng),
                        category_id=cat_id,
                        address=p.get("address") or "",
                        opening_hours=p.get("opening_hours") or {},
                        entry_fee=p.get("entry_fee") or 0.0,
                        currency=p.get("currency") or "USD",
                        rating=p.get("rating") or 0.0,
                        review_count=p.get("review_count") or 0,
                        photo_urls=p.get("photo_urls") or [],
                        tags=p.get("tags") or [],
                        geofence_radius_m=100,
                        is_active=is_active,
                    )
                    session.add(new_attr)

            await session.commit()

            # Re-query the database to get the complete unified set
            nearby_db_attractions = await repo.get_nearby(
                latitude=latitude,
                longitude=longitude,
                radius_m=float(radius),
                category_id=category_id,
                limit=db_limit
            )

            place_dicts = [
                attraction_to_place_dict(attr, dist)
                for attr, dist in nearby_db_attractions
            ]
            place_dicts = _enforce_distance_distribution(place_dicts, radius)

            await place_cache_service.set_cached(key, place_dicts)
            print(f"✅ Background seeding complete: cached {len(place_dicts)} places for radius {radius}m.")
    except Exception as e:
        print(f"⚠️ Error in seed_places_from_google_bg: {e}")



def attraction_to_place_dict(attraction: Attraction, distance_m: float) -> dict:
    lat, lng = get_lat_lng(attraction.location)
    return {
        "id": str(attraction.id),
        "name": attraction.name,
        "description": attraction.description,
        "history": attraction.history,
        "latitude": lat,
        "longitude": lng,
        "category_id": str(attraction.category_id) if attraction.category_id else None,
        "category_name": attraction.category.name if attraction.category else None,
        "address": attraction.address,
        "opening_hours": attraction.opening_hours or {},
        "entry_fee": attraction.entry_fee or 0.0,
        "currency": attraction.currency or "USD",
        "rating": attraction.rating or 0.0,
        "review_count": attraction.review_count or 0,
        "photo_urls": attraction.photo_urls or [],
        "tags": attraction.tags or [],
        "geofence_radius_m": attraction.geofence_radius_m or 100,
        "distance_m": distance_m,
        "is_active": attraction.is_active,
        "created_at": attraction.created_at.isoformat() if attraction.created_at else None,
    }


async def get_nearby(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
    use_legacy: bool = False,
) -> PlacesNearbyResponse:
    # Canonicalize once at the entry point so the cache key, the Google call,
    # and the filter_food decision below all agree on the same category value.
    category = google_places_client.canonical_category(category)
    key = place_cache_service.build_key(latitude, longitude, category, radius)
    if use_legacy:
        key = f"{key}:legacy"

    cached = await place_cache_service.get_cached(key)
    if cached is not None:
        return PlacesNearbyResponse(
            places=[PlaceResponse.model_validate(p) for p in cached],
            cached=True,
            source="cache",
        )

    # Redis missed. Query local PostgreSQL database first
    async with async_session() as session:
        # Find category ID mapping if category is specified
        category_id = None
        if category:
            stmt = select(Category).where(Category.name == category)
            res = await session.execute(stmt)
            cat_obj = res.scalar_one_or_none()
            if cat_obj:
                category_id = cat_obj.id

        # Query database attractions
        # Use a higher limit for wide-area searches so 25–50km results aren't
        # truncated to only the closest 100.
        db_limit = 100 if radius <= 10000 else 200
        min_rad = get_min_radius(radius)
        repo = AttractionRepository(session)
        nearby_db_attractions = await repo.get_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_m=float(radius),
            category_id=category_id,
            limit=db_limit,
            is_active=True,
            sort_by_popularity=(radius >= 10000)
        )

        # If we have a healthy list of attractions (e.g. >= 10) AND they cover the requested radius
        # adequately (e.g. at least one is in the outer 30% of the radius, or the radius is small <= 2000m)
        has_adequate_coverage = radius <= 2000 or any(dist >= radius * 0.7 for _, dist in nearby_db_attractions)
        
        # Optimize: if database already has a reasonable number of places (e.g. >= 10), return them
        # immediately to prevent user delay, and run the revalidation/seeding from Google in the background.
        if len(nearby_db_attractions) >= 10:
            place_dicts = [
                attraction_to_place_dict(attr, dist)
                for attr, dist in nearby_db_attractions
            ]
            place_dicts = _enforce_distance_distribution(place_dicts, radius)
            
            # Revalidate in the background if the coverage is not adequate yet
            if not has_adequate_coverage:
                import asyncio
                asyncio.create_task(seed_places_from_google_bg(
                    latitude=latitude,
                    longitude=longitude,
                    category=category,
                    radius=radius,
                    use_legacy=use_legacy,
                    category_id=category_id,
                    key=key
                ))
            
            await place_cache_service.set_cached(key, place_dicts)
            return PlacesNearbyResponse(
                places=[PlaceResponse.model_validate(p) for p in place_dicts],
                cached=False,
                source="database",
            )

        # Keep a list of existing attraction names and coordinates to prevent duplicates
        existing_records = [
            (get_lat_lng(attr.location), attr.name)
            for attr, _ in nearby_db_attractions
        ]

    # Session closed here! No connection is held during the slow Google query.
    
    # Otherwise, query Google Places API as a fallback
    import asyncio
    min_radius = get_min_radius(radius)
    
    if min_radius == 0:
        # Standard single query at center
        if use_legacy:
            raw_places = await google_places_client.nearby_search_legacy(
                latitude=latitude,
                longitude=longitude,
                category=category,
                radius=radius,
            )
        else:
            raw_places = await google_places_client.nearby_search(
                latitude=latitude,
                longitude=longitude,
                category=category,
                radius=radius,
            )
    else:
        # Annulus offset center queries to cover the entire band (since single query caps at 20 places)
        mid = (min_radius + radius) / 2.0
        sample_radius = int((radius - min_radius) / 2.0)
        
        # Scale centers: reduced from 8 to 4 to speed up search and minimize API costs
        num_centers = 4
        bearings = [(360.0 / num_centers) * i for i in range(num_centers)]
        offset_coords = [offset_lat_lng(latitude, longitude, b, mid) for b in bearings]
        
        # Add center query as well to ensure total coverage
        all_queries = [(latitude, longitude, radius)] + [
            (olat, olng, sample_radius) for olat, olng in offset_coords
        ]
        
        async def fetch_one(lat: float, lng: float, rad: int) -> list:
            try:
                if use_legacy:
                    return await google_places_client.nearby_search_legacy(
                        latitude=lat,
                        longitude=lng,
                        category=category,
                        radius=rad,
                    )
                else:
                    return await google_places_client.nearby_search(
                        latitude=lat,
                        longitude=lng,
                        category=category,
                        radius=rad,
                    )
            except Exception as e:
                print(f"⚠️ Error fetching offset nearby search in get_nearby: {e}")
                return []
        
        # Fetch all in parallel
        results = await asyncio.gather(*(fetch_one(lat, lng, rad) for lat, lng, rad in all_queries))
        
        # Merge and deduplicate
        raw_places = []
        seen_ids = set()
        for r_list in results:
            for p in r_list:
                pid = p.get("id") or p.get("place_id")
                if pid and pid not in seen_ids:
                    seen_ids.add(pid)
                    raw_places.append(p)
    
    # Convert raw places to PlaceResponses
    if use_legacy:
        place_dicts = [
            google_places_client.to_place_dict_legacy(p, latitude, longitude, category, _photo_url)
            for p in raw_places
        ]
    else:
        if category == "Food & Drink":
            raw_places = google_places_client.filter_food(raw_places)
        elif category != "Beach":
            raw_places = raw_places[:100] # cap merged result
            
        place_dicts = [
            google_places_client.to_place_dict(p, latitude, longitude, category, _photo_url)
            for p in raw_places
        ]

    # Save newly fetched places to PostgreSQL database (in a new session!)
    async with async_session() as session:
        repo = AttractionRepository(session)
        for p in place_dicts:
            p_name = p.get("name")
            plat = p.get("latitude")
            plng = p.get("longitude")
            resolved_category = p.get("category_name")

            if not p_name or plat is None or plng is None:
                continue

            # Check duplicates using the coordinate snapshot
            existing_attraction = None
            for (alat, alng), name in existing_records:
                dist = _haversine_m(plat, plng, alat, alng)
                name_similarity = (name.lower() in p_name.lower()) or (p_name.lower() in name.lower())
                if dist < 25.0 and name_similarity:
                    existing_attraction = True
                    break

            if not existing_attraction:
                cat_id = None
                if resolved_category:
                    stmt = select(Category).where(Category.name == resolved_category)
                    res = await session.execute(stmt)
                    cat_obj = res.scalar_one_or_none()
                    if not cat_obj:
                        cat_obj = Category(name=resolved_category, icon="place", color="#607D8B")
                        session.add(cat_obj)
                        await session.flush()
                    cat_id = cat_obj.id

                # Check duplicate coordinates
                dup_coords = False
                for (alat, alng), _ in existing_records:
                    if abs(plat - alat) < 0.000001 and abs(plng - alng) < 0.000001:
                        dup_coords = True
                        break
                if not dup_coords:
                    dup = await repo.find_duplicate_by_coordinates(plat, plng)
                    if dup:
                        dup_coords = True
                is_active = not dup_coords

                new_attr = Attraction(
                    name=p_name,
                    description=p.get("description") or "",
                    location=create_point(plat, plng),
                    category_id=cat_id,
                    address=p.get("address") or "",
                    opening_hours=p.get("opening_hours") or {},
                    entry_fee=p.get("entry_fee") or 0.0,
                    currency=p.get("currency") or "USD",
                    rating=p.get("rating") or 0.0,
                    review_count=p.get("review_count") or 0,
                    photo_urls=p.get("photo_urls") or [],
                    tags=p.get("tags") or [],
                    geofence_radius_m=100,
                    is_active=is_active,
                )
                session.add(new_attr)

        await session.commit()

        # Re-query the database to get the complete unified set
        nearby_db_attractions = await repo.get_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_m=float(radius),
            category_id=category_id,
            limit=db_limit,
            sort_by_popularity=(radius >= 10000)
        )

        place_dicts = [
            attraction_to_place_dict(attr, dist)
            for attr, dist in nearby_db_attractions
        ]
        place_dicts = _enforce_distance_distribution(place_dicts, radius)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in place_dicts],
        cached=False,
        source="google",
    )


async def search(
    *,
    query: str,
    latitude: float,
    longitude: float,
) -> PlacesNearbyResponse:
    snap_lat = place_cache_service._snap(latitude)
    snap_lng = place_cache_service._snap(longitude)
    clean_query = query.strip().lower().replace(" ", "_")
    key = f"places:search:{snap_lat}:{snap_lng}:{clean_query}"

    cached = await place_cache_service.get_cached(key)
    if cached is not None:
        return PlacesNearbyResponse(
            places=[PlaceResponse.model_validate(p) for p in cached],
            cached=True,
            source="cache",
        )

    raw = await google_places_client.text_search(
        query=query,
        latitude=latitude,
        longitude=longitude,
    )

    place_dicts = [
        google_places_client.to_place_dict(p, latitude, longitude, None, _photo_url)
        for p in raw
    ]

    # Inject formatted address into place_dicts
    for i, p in enumerate(raw):
        if "formattedAddress" in p:
            place_dicts[i]["address"] = p["formattedAddress"]

    # Save newly fetched places to PostgreSQL database
    async with async_session() as session:
        repo = AttractionRepository(session)
        # Fetch existing database attractions near the search area (50km radius) to check for duplicates
        nearby_db_attractions = await repo.get_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_m=50000.0,
            limit=500
        )

        for p in place_dicts:
            p_name = p.get("name")
            plat = p.get("latitude")
            plng = p.get("longitude")
            resolved_category = p.get("category_name")

            if not p_name or plat is None or plng is None:
                continue

            # Check if this place already exists in database (within 25 meters and name matches)
            existing_attraction = None
            for attraction, _ in nearby_db_attractions:
                alat, alng = get_lat_lng(attraction.location)
                dist = _haversine_m(plat, plng, alat, alng)
                name_similarity = (attraction.name.lower() in p_name.lower()) or (p_name.lower() in attraction.name.lower())
                if dist < 25.0 and name_similarity:
                    existing_attraction = attraction
                    break

            if not existing_attraction:
                cat_id = None
                if resolved_category:
                    stmt = select(Category).where(Category.name == resolved_category)
                    res = await session.execute(stmt)
                    cat_obj = res.scalar_one_or_none()
                    if not cat_obj:
                        cat_obj = Category(name=resolved_category, icon="place", color="#607D8B")
                        session.add(cat_obj)
                        await session.flush()
                    cat_id = cat_obj.id

                # Check duplicate coordinates
                dup_coords = False
                for attraction, _ in nearby_db_attractions:
                    alat, alng = get_lat_lng(attraction.location)
                    if abs(plat - alat) < 0.000001 and abs(plng - alng) < 0.000001:
                        dup_coords = True
                        break
                if not dup_coords:
                    dup = await repo.find_duplicate_by_coordinates(plat, plng)
                    if dup:
                        dup_coords = True
                is_active = not dup_coords

                new_attr = Attraction(
                    name=p_name,
                    description=p.get("description") or "",
                    location=create_point(plat, plng),
                    category_id=cat_id,
                    address=p.get("address") or "",
                    opening_hours=p.get("opening_hours") or {},
                    entry_fee=p.get("entry_fee") or 0.0,
                    currency=p.get("currency") or "USD",
                    rating=p.get("rating") or 0.0,
                    review_count=p.get("review_count") or 0,
                    photo_urls=p.get("photo_urls") or [],
                    tags=p.get("tags") or [],
                    geofence_radius_m=100,
                    is_active=is_active,
                )
                session.add(new_attr)

        await session.commit()

    place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in place_dicts],
        cached=False,
        source="google",
    )


async def get_trending(
    *,
    district: str,
    latitude: float,
    longitude: float,
    db,
) -> dict:
    from app.services.settings_service import SettingsService
    from datetime import datetime
    import httpx
    import json
    import re
    import asyncio

    clean_dist = district.strip().lower().replace(" ", "_")
    if not clean_dist or clean_dist == "nearby":
        # Snap lat/lng to 0.1 degree grid (approx 11km) for caching when district is missing
        snap_lat = f"{math.floor(latitude / 0.1) * 0.1:.2f}"
        snap_lng = f"{math.floor(longitude / 0.1) * 0.1:.2f}"
        key = f"trending:v1:grid:{snap_lat}:{snap_lng}"
    else:
        key = f"trending:v1:district:{clean_dist}"

    # 1. Check Redis Cache
    cached_raw = await place_cache_service.get_raw(key)
    if cached_raw is not None:
        try:
            cached_data = json.loads(cached_raw)
            return {
                "markdown": cached_data["markdown"],
                "places": [PlaceResponse.model_validate(p) for p in cached_data["places"]],
                "cached": True
            }
        except Exception as e:
            print(f"⚠️ Error parsing cached trending data: {e}")

    # 2. Redis Cache Miss: Fetch from Gemini
    settings = SettingsService(db)
    api_key = await settings.get_setting("gemini_api_key")
    if not api_key:
        raise ValueError("Gemini API Key not configured")

    formatted_time = datetime.now().strftime('%A, %B %d, %Y, %I:%M %p')
    user_location = f"{district} ({latitude:.6f}, {longitude:.6f})"

    # The exact discovery prompt
    prompt = f"""# NexAround AI Experience Discovery Engine

You are **NexAround AI**, an intelligent local discovery companion.

Your mission is not to find events.

Your mission is to help people discover experiences worth leaving home for.

Act like a knowledgeable local guide, cultural insider, event curator, and travel companion combined.

---

## User Context

Analyze and utilize the following information whenever available:

* Current location : {user_location}
* Current date and time: {formatted_time}

---

## Experience Search Categories

Search for and prioritize:

### Events

* Festivals
* Cultural celebrations
* Religious festivals
* Community gatherings
* Live music
* Concerts
* Theater
* Comedy shows
* Workshops
* Meetups
* Art exhibitions
* Food festivals
* Farmers markets
* Sporting events

### Outdoor Experiences

* Walking trails
* Scenic viewpoints
* Parks
* Waterfront experiences
* Nature activities
* Adventure activities
* Seasonal outdoor attractions

### Local Discovery

* Hidden gems
* Local favorites
* Historic neighborhoods
* Street food experiences
* Artisan markets
* Cultural districts
* Unique local businesses

### Family Experiences

* Children's activities
* Educational attractions
* Interactive experiences
* Family festivals

### Nightlife

* Live entertainment
* Rooftop venues
* Night markets
* Cultural performances

---

## Recommendation Priorities

Rank opportunities using:

1. Relevance to user interests
2. Events happening now
3. Events starting soon
4. Weather suitability
5. Local popularity
6. Authenticity
7. Uniqueness
8. User ratings and reviews
9. Travel convenience
10. Value for money

Give preference to:

* Hyperlocal discoveries
* Experiences tourists often miss
* Time-sensitive opportunities
* Seasonal events
* One-time happenings
* Highly rated local experiences

Avoid:

* Generic tourist recommendations
* Duplicate listings
* Outdated events
* Poorly reviewed experiences
* Low-quality directory results

---

## Scoring Framework

Assign a confidence score from 1–100 based on:

* Data freshness
* Popularity
* Interest match
* Weather fit
* Timing suitability
* Travel convenience

---

## Response Format

# What's Happening Nearby

## Recommended For You (Atleast 5 events)

### [Event or Experience Name]

Why you'll love it:
[Personalized explanation]

Distance:
[X km]

Travel Time:
[X minutes]

When:
[Time and date]

Cost:
[Free / Estimated cost]

Best For:
[Solo / Couple / Family / Friends]

Confidence Score:
[X/100]

---

### Why It's Worth Leaving Home For

Provide a short personalized recommendation explaining why this experience stands out today.

---

# Hidden Gem (Atleast 5 gems)


If applicable, recommend a lesser-known local experience.

### [Hidden Gem Name]

Why locals love it:
[Description]

Distance:
[X km]

Cost:
[Estimated cost]


---

## No Event Fallback Strategy

If no notable events exist, intelligently recommend:

* Self-guided walking tours
* Food trails
* Scenic drives
* Historic neighborhoods
* Local markets
* Hidden attractions
* Sunset viewpoints
* Cultural experiences
* Nature spots
* Weekend adventures

Never return "No events found."

Always provide a meaningful discovery opportunity.
"""

    system_instruction = (
        "You are NexAround AI, an intelligent local discovery companion. "
        "Help people discover experiences worth leaving home for."
    )

    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "system_instruction": {"parts": [{"text": system_instruction}]},
        "generationConfig": {
            "temperature": 0.8,
            "maxOutputTokens": 4096,
        },
    }

    models = [
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-flash-latest",
        "gemini-2.5-pro",
    ]
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    
    response_text = ""
    async with httpx.AsyncClient(timeout=90.0) as client:
        for i, model in enumerate(models):
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            try:
                resp = await client.post(url, json=body, headers=headers)
                if resp.status_code in (429, 500, 503) and i < len(models) - 1:
                    continue
                resp.raise_for_status()
                data = resp.json()
                candidates = data.get("candidates") or []
                if candidates:
                    parts = (candidates[0].get("content") or {}).get("parts") or []
                    response_text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
                    if response_text.strip():
                        break
            except Exception as e:
                print(f"⚠️ Error calling Gemini model {model} in get_trending: {e}")
                if i == len(models) - 1:
                    raise e

    if not response_text.strip():
        raise ValueError("Gemini returned empty response")

    # 3. Extract place names from markdown headers starting with "### "
    extracted_names = []
    matches = re.findall(r'^###\s+(.*)$', response_text, re.MULTILINE)
    for match in matches:
        name = match.strip()
        if not name:
            continue
        
        # Strip square brackets
        if name.startswith('[') and name.endswith(']'):
            name = name[1:-1].strip()
        elif name.startswith('[') and ']' in name:
            closing_bracket = name.find(']')
            name = name[1:closing_bracket].strip()
            
        lower_name = name.lower()
        if (
            "why it's worth leaving home for" in lower_name
            or "why locals love it" in lower_name
            or "why you'll love it" in lower_name
            or "event or experience name" in lower_name
            or "hidden gem name" in lower_name
        ):
            continue
            
        if name not in extracted_names:
            extracted_names.append(name)

    # 4. Resolve the extracted names using Google Places text search API in parallel
    resolved_places = []
    
    async def resolve_one_place(name_str: str) -> Optional[dict]:
        try:
            # We call places_service.search which has built-in Redis caching!
            res = await search(query=name_str, latitude=latitude, longitude=longitude)
            if res.places:
                return res.places[0].model_dump()
        except Exception as ex:
            print(f"⚠️ Error resolving place '{name_str}' in get_trending: {ex}")
        return None

    # Resolve up to 8 places in parallel
    search_tasks = [resolve_one_place(n) for n in extracted_names[:8]]
    resolved_results = await asyncio.gather(*search_tasks)
    for r in resolved_results:
        if r is not None:
            resolved_places.append(r)

    # 5. Save in Redis (TTL = 24 hours / 86400 seconds)
    response_data = {
        "markdown": response_text,
        "places": resolved_places
    }
    # We will use place_cache_service to set the raw key in Redis
    await place_cache_service.set_raw(key, json.dumps(response_data, default=str), ttl=86400)

    return {
        "markdown": response_text,
        "places": [PlaceResponse.model_validate(p) for p in resolved_places],
        "cached": False
    }

