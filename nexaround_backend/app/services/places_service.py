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
        return 5000
    elif radius == 15000:
        return 0
    elif radius == 25000:
        return 10000
    elif radius == 50000:
        return 25000
    return 0


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
            place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

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
            min_radius_m=float(min_rad) if min_rad > 0 else None
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
            place_dicts.sort(key=lambda p: p.get("distance_m") or 0)
            
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
        min_rad = get_min_radius(radius)
        nearby_db_attractions = await repo.get_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_m=float(radius),
            category_id=category_id,
            limit=db_limit,
            min_radius_m=float(min_rad) if min_rad > 0 else None
        )

        place_dicts = [
            attraction_to_place_dict(attr, dist)
            for attr, dist in nearby_db_attractions
        ]
        place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

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
