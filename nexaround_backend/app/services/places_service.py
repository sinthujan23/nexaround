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
    return 0


def _enforce_distance_distribution(places: list[dict], radius_m: int, category: Optional[str] = None) -> list[dict]:
    """Filter and select a balanced distribution of nearby places across Near, Mid, and Far zones
    to ensure the client receives variety instead of only the closest clusters.
    """
    # Sort places by rating (descending) and distance (ascending) to get high quality ones
    places.sort(key=lambda p: (-(p.get("rating") or 4.0), p.get("distance_m", 0)))
    
    t1 = radius_m * 0.1
    t2 = radius_m * 0.4
    
    near_list = []
    mid_list = []
    far_list = []
    
    for p in places:
        dist = p.get("distance_m", 0)
        if dist < t1:
            near_list.append(p)
        elif dist < t2:
            mid_list.append(p)
        else:
            far_list.append(p)
            
    # Target counts out of 100 total
    near_target = 40
    mid_target = 30
    far_target = 30
    
    near_taken = min(len(near_list), near_target)
    mid_taken = min(len(mid_list), mid_target)
    far_taken = min(len(far_list), far_target)
    
    remaining = 100 - (near_taken + mid_taken + far_taken)
    
    if remaining > 0:
        extra_near = min(len(near_list) - near_taken, remaining)
        near_taken += extra_near
        remaining -= extra_near
        
    if remaining > 0:
        extra_mid = min(len(mid_list) - mid_taken, remaining)
        mid_taken += extra_mid
        remaining -= extra_mid
        
    if remaining > 0:
        extra_far = min(len(far_list) - far_taken, remaining)
        far_taken += extra_far
        remaining -= extra_far
        
    selected = near_list[:near_taken] + mid_list[:mid_taken] + far_list[:far_taken]
    
    if category == "Shopping":
        # Prioritize malls, then sort by distance
        def sort_key(p):
            tags = p.get("tags", []) or []
            is_mall = "shopping_mall" in tags
            return (0 if is_mall else 1, p.get("distance_m", 0))
        selected.sort(key=sort_key)
    elif category == "Attractions":
        # Prioritize beaches, parks, museums, and historical landmarks, then sort by distance
        def sort_key(p):
            tags = set(p.get("tags") or [])
            is_priority = bool(tags & {"beach", "park", "museum", "national_park", "historical_landmark", "tourist_attraction"})
            return (0 if is_priority else 1, p.get("distance_m", 0))
        selected.sort(key=sort_key)
    else:
        selected.sort(key=lambda p: p.get("distance_m", 0))
        
    return selected


async def _query_nearby_three_zones(
    repo: AttractionRepository,
    latitude: float,
    longitude: float,
    radius: int,
    category_id: Optional[int],
    is_active: Optional[bool] = None
) -> list:
    """Helper to query nearby places from PostgreSQL in three distinct zones."""
    t1 = radius * 0.1
    t2 = radius * 0.4
    
    # Zone 1 (Near): 0 to t1, limit 50
    near_db = await repo.get_nearby(
        latitude=latitude,
        longitude=longitude,
        radius_m=float(t1),
        category_id=category_id,
        limit=50,
        is_active=is_active
    )
    
    # Zone 2 (Mid): t1 to t2, limit 40
    mid_db = await repo.get_nearby(
        latitude=latitude,
        longitude=longitude,
        radius_m=float(t2),
        category_id=category_id,
        limit=40,
        is_active=is_active,
        min_radius_m=float(t1)
    )
    
    # Zone 3 (Far): t2 to radius, limit 40
    far_db = await repo.get_nearby(
        latitude=latitude,
        longitude=longitude,
        radius_m=float(radius),
        category_id=category_id,
        limit=40,
        is_active=is_active,
        min_radius_m=float(t2)
    )
    
    return near_db + mid_db + far_db


_active_seed_tasks: set[str] = set()


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
    if key in _active_seed_tasks:
        return
    _active_seed_tasks.add(key)
    try:
        # 1. Check database first to see if revalidation is actually needed (close session immediately after)
        async with async_session() as session:
            repo = AttractionRepository(session)
            
            # Fetch the latest set from DB to check if another worker has already seeded
            nearby_db_attractions = await _query_nearby_three_zones(
                repo=repo,
                latitude=latitude,
                longitude=longitude,
                radius=radius,
                category_id=category_id
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
            if category == "Food & Drink":
                raw_places = google_places_client.filter_food(raw_places)
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

                if category == "Attractions":
                    exclude_tags = {
                        "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
                        "school", "primary_school", "secondary_school", "preschool", "kindergarten", "university",
                        "doctor", "dentist", "hospital", "medical_clinic", "pharmacy", "physiotherapist", "health",
                        "bank", "atm", "accounting", "lawyer", "insurance_agency", "real_estate_agency",
                        "car_repair", "gas_station", "car_dealer", "car_rental", "car_wash",
                        "store", "clothing_store", "electronics_store", "supermarket", "convenience_store", "grocery_store",
                        "gym", "fitness_center", "cemetery", "funeral_home"
                    }
                    if (set(p.get("tags") or []) & exclude_tags) or any(kw in p_name.lower() for kw in ["spa", "salon", "clinic", "surgery", "school", "preschool", "academy", "dental"]):
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
            nearby_db_attractions = await _query_nearby_three_zones(
                repo=repo,
                latitude=latitude,
                longitude=longitude,
                radius=radius,
                category_id=category_id
            )

            place_dicts = [
                attraction_to_place_dict(attr, dist)
                for attr, dist in nearby_db_attractions
            ]
            place_dicts = _enforce_distance_distribution(place_dicts, radius, category)

            await place_cache_service.set_cached(key, place_dicts)
            print(f"✅ Background seeding complete: cached {len(place_dicts)} places for radius {radius}m.")
    except Exception as e:
        print(f"⚠️ Error in seed_places_from_google_bg: {e}")
    finally:
        _active_seed_tasks.discard(key)



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


def _format_response_places(
    place_dicts: list[dict],
    max_photos: int,
    limit: int,
    offset: int,
) -> list[PlaceResponse]:
    """Slice places list by offset/limit and trim photo_urls to max_photos for response payload efficiency.
    Does not modify original dicts stored in DB/cache.
    """
    paginated = place_dicts[offset : offset + limit]
    formatted = []
    for p in paginated:
        p_copy = dict(p)
        if "photo_urls" in p_copy and p_copy["photo_urls"]:
            p_copy["photo_urls"] = p_copy["photo_urls"][:max_photos]
        formatted.append(PlaceResponse.model_validate(p_copy))
    return formatted


async def get_nearby(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
    use_legacy: bool = False,
    max_photos: int = 1,
    limit: int = 20,
    offset: int = 0,
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
            places=_format_response_places(cached, max_photos, limit, offset),
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
        repo = AttractionRepository(session)
        nearby_db_attractions = await _query_nearby_three_zones(
            repo=repo,
            latitude=latitude,
            longitude=longitude,
            radius=radius,
            category_id=category_id,
            is_active=True
        )

        place_dicts = [
            attraction_to_place_dict(attr, dist)
            for attr, dist in nearby_db_attractions
        ]

        if category == "Attractions":
            exclude_tags = {
                "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
                "school", "primary_school", "secondary_school", "preschool", "kindergarten", "university",
                "doctor", "dentist", "hospital", "medical_clinic", "pharmacy", "physiotherapist", "health",
                "bank", "atm", "accounting", "lawyer", "insurance_agency", "real_estate_agency",
                "car_repair", "gas_station", "car_dealer", "car_rental", "car_wash",
                "store", "clothing_store", "electronics_store", "supermarket", "convenience_store", "grocery_store",
                "gym", "fitness_center", "cemetery", "funeral_home"
            }
            place_dicts = [
                p for p in place_dicts 
                if not (set(p.get("tags") or []) & exclude_tags)
                and not any(kw in p["name"].lower() for kw in ["spa", "salon", "clinic", "surgery", "school", "preschool", "academy", "dental"])
            ]

        # If we have a healthy list of attractions (e.g. >= 10) AND they cover the requested radius
        # adequately (e.g. at least one is in the outer 30% of the radius, or the radius is small <= 2000m)
        has_adequate_coverage = radius <= 2000 or any(p["distance_m"] >= radius * 0.7 for p in place_dicts)
        
        # Optimize: if database already has a reasonable number of places (e.g. >= 10), return them
        # immediately to prevent user delay, and run the revalidation/seeding from Google in the background.
        if len(place_dicts) >= 10:
            place_dicts = _enforce_distance_distribution(place_dicts, radius, category)
            
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
                places=_format_response_places(place_dicts, max_photos, limit, offset),
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
    raw_places = []
    if not use_legacy:
        try:
            if radius < 25000:
                raw_places = await google_places_client.nearby_search(
                    latitude=latitude,
                    longitude=longitude,
                    category=category,
                    radius=radius,
                )
            else:
                # Annulus offset center queries to cover the entire band (since single query caps at 20 places)
                mid = radius * 0.7
                sample_radius = int(radius * 0.5)
                
                # Scale centers: 4 offsets to get more places
                num_centers = 4
                bearings = [(360.0 / num_centers) * i for i in range(num_centers)]
                offset_coords = [offset_lat_lng(latitude, longitude, b, mid) for b in bearings]
                
                # Add center query as well to ensure total coverage
                all_queries = [(latitude, longitude, radius)] + [
                    (olat, olng, sample_radius) for olat, olng in offset_coords
                ]
                
                async def fetch_one(lat: float, lng: float, rad: int) -> list:
                    return await google_places_client.nearby_search(
                        latitude=lat,
                        longitude=lng,
                        category=category,
                        radius=rad,
                    )
                
                # Fetch all in parallel
                results = await asyncio.gather(*(fetch_one(lat, lng, rad) for lat, lng, rad in all_queries))
                
                # Merge and deduplicate
                seen_ids = set()
                for r_list in results:
                    for p in r_list:
                        pid = p.get("id") or p.get("place_id")
                        if pid and pid not in seen_ids:
                            seen_ids.add(pid)
                            raw_places.append(p)
        except Exception as e:
            print(f"⚠️ Places API (New) failed with error: {e}. Falling back to Legacy Nearby Search API.")
            use_legacy = True

    # Execute legacy search if use_legacy is True (either requested or as fallback)
    if use_legacy:
        if radius < 25000:
            # Standard single query at center
            raw_places = await google_places_client.nearby_search_legacy(
                latitude=latitude,
                longitude=longitude,
                category=category,
                radius=radius,
            )
        else:
            # Annulus offset center queries to cover the entire band (since single query caps at 20 places)
            mid = radius * 0.7
            sample_radius = int(radius * 0.5)
            
            # Scale centers: 4 offsets to get more places
            num_centers = 4
            bearings = [(360.0 / num_centers) * i for i in range(num_centers)]
            offset_coords = [offset_lat_lng(latitude, longitude, b, mid) for b in bearings]
            
            # Add center query as well to ensure total coverage
            all_queries = [(latitude, longitude, radius)] + [
                (olat, olng, sample_radius) for olat, olng in offset_coords
            ]
            
            async def fetch_one_legacy(lat: float, lng: float, rad: int) -> list:
                try:
                    return await google_places_client.nearby_search_legacy(
                        latitude=lat,
                        longitude=lng,
                        category=category,
                        radius=rad,
                    )
                except Exception as e:
                    print(f"⚠️ Error fetching offset nearby search legacy in get_nearby: {e}")
                    return []
            
            # Fetch all in parallel
            results = await asyncio.gather(*(fetch_one_legacy(lat, lng, rad) for lat, lng, rad in all_queries))
            
            # Merge and deduplicate
            seen_ids = set()
            for r_list in results:
                for p in r_list:
                    pid = p.get("id") or p.get("place_id")
                    if pid and pid not in seen_ids:
                        seen_ids.add(pid)
                        raw_places.append(p)
    
    # Convert raw places to PlaceResponses
    if use_legacy:
        if category == "Food & Drink":
            raw_places = google_places_client.filter_food(raw_places)
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

    if category == "Attractions":
        exclude_tags = {
            "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
            "school", "primary_school", "secondary_school", "preschool", "kindergarten", "university",
            "doctor", "dentist", "hospital", "medical_clinic", "pharmacy", "physiotherapist", "health",
            "bank", "atm", "accounting", "lawyer", "insurance_agency", "real_estate_agency",
            "car_repair", "gas_station", "car_dealer", "car_rental", "car_wash",
            "store", "clothing_store", "electronics_store", "supermarket", "convenience_store", "grocery_store",
            "gym", "fitness_center", "cemetery", "funeral_home"
        }
        place_dicts = [
            p for p in place_dicts 
            if not (set(p.get("tags") or []) & exclude_tags)
            and not any(kw in p["name"].lower() for kw in ["spa", "salon", "clinic", "surgery", "school", "preschool", "academy", "dental"])
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
            limit=100,
            min_radius_m=float(min_rad) if min_rad > 0 else None
        )

        place_dicts = [
            attraction_to_place_dict(attr, dist)
            for attr, dist in nearby_db_attractions
        ]

        if category == "Attractions":
            exclude_tags = {
                "spa", "beauty_salon", "hair_care", "hair_salon", "nail_salon", "massage",
                "school", "primary_school", "secondary_school", "preschool", "kindergarten", "university",
                "doctor", "dentist", "hospital", "medical_clinic", "pharmacy", "physiotherapist", "health",
                "bank", "atm", "accounting", "lawyer", "insurance_agency", "real_estate_agency",
                "car_repair", "gas_station", "car_dealer", "car_rental", "car_wash",
                "store", "clothing_store", "electronics_store", "supermarket", "convenience_store", "grocery_store",
                "gym", "fitness_center", "cemetery", "funeral_home"
            }
            place_dicts = [
                p for p in place_dicts 
                if not (set(p.get("tags") or []) & exclude_tags)
                and not any(kw in p["name"].lower() for kw in ["spa", "salon", "clinic", "surgery", "school", "preschool", "academy", "dental"])
            ]

        place_dicts = _enforce_distance_distribution(place_dicts, radius, category)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=_format_response_places(place_dicts, max_photos, limit, offset),
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

    # 1. Check Redis Cache
    cached = await place_cache_service.get_cached(key)
    if cached is not None:
        return PlacesNearbyResponse(
            places=[PlaceResponse.model_validate(p) for p in cached],
            cached=True,
            source="cache",
        )

    # 2. Check local PostgreSQL database first (saves Google API calls)
    async with async_session() as session:
        repo = AttractionRepository(session)
        try:
            db_results = await repo.search_by_name(
                name=query.strip(),
                latitude=latitude,
                longitude=longitude,
                radius_m=50000.0,
                limit=20,
            )
            if len(db_results) >= 2:
                place_dicts = [
                    attraction_to_place_dict(attr, dist)
                    for attr, dist in db_results
                ]
                place_dicts.sort(key=lambda p: p.get("distance_m") or 0)
                await place_cache_service.set_cached(key, place_dicts)
                return PlacesNearbyResponse(
                    places=[PlaceResponse.model_validate(p) for p in place_dicts],
                    cached=False,
                    source="database",
                )
        except Exception as e:
            print(f"⚠️ DB search error in places_service.search: {e}")

    # 3. Fallback to Google Text Search (New) on cache/DB miss
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

    import asyncio
    asyncio.create_task(_save_search_results_bg(place_dicts, latitude, longitude))

    place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in place_dicts],
        cached=False,
        source="google",
    )


async def _save_search_results_bg(place_dicts: list[dict], latitude: float, longitude: float):
    """Save newly fetched search places to PostgreSQL database asynchronously in the background."""
    try:
        async with async_session() as session:
            repo = AttractionRepository(session)
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
    except Exception as e:
        print(f"⚠️ Error saving search results in background: {e}")


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
    prompt = f"""You are NexAround AI, an intelligent local discovery companion helping people discover experiences worth leaving home for.

## User Context
- Location: {user_location}
- Date/Time: {formatted_time}

## Your Task
Recommend **5 events/experiences** and **5 hidden gems** near the user's location. Focus on:
- Events happening now or soon (festivals, live music, markets, exhibitions)
- Outdoor experiences (trails, viewpoints, beaches, parks)
- Hidden gems locals love (street food, artisan markets, cultural spots)
- Family-friendly and nightlife options where relevant

## Priorities
1. Hyperlocal discoveries tourists miss
2. Time-sensitive / seasonal opportunities
3. Weather-appropriate suggestions
4. Highly rated, authentic experiences

## Response Format

# What's Happening Nearby

## Recommended For You

### [Experience Name]
Why you'll love it: [1 sentence]
Distance: [X km] · Travel Time: [X min]
When: [Time/date] · Cost: [Free/amount]
Best For: [Solo/Couple/Family/Friends]
Confidence Score: [X/100]

---

### Why It's Worth Leaving Home For
[1-2 sentence personalized recommendation]

---

# Hidden Gems

### [Hidden Gem Name]
Why locals love it: [1 sentence]
Distance: [X km] · Cost: [amount]

If no events exist, recommend self-guided tours, food trails, scenic spots, or nature walks. Never return "No events found."
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
            "maxOutputTokens": 2048,
        },
    }

    models = [
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-1.5-flash",
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

    # 4. Resolve the extracted names — DB FIRST, Google as fallback.
    #    This saves ~50% of Google Text Search calls since many trending
    #    places already exist in our PostgreSQL attractions table from
    #    previous nearby/search queries.
    resolved_places = []
    names_to_resolve_via_google = []

    # 4a. Try local database lookup first (fuzzy name match)
    async with async_session() as session:
        repo = AttractionRepository(session)
        for name_str in extracted_names[:8]:
            # Search by name in our local DB within 50km
            try:
                db_results = await repo.search_by_name(
                    name=name_str,
                    latitude=latitude,
                    longitude=longitude,
                    radius_m=50000.0,
                    limit=1,
                )
                if db_results:
                    attr, dist = db_results[0]
                    place_dict = attraction_to_place_dict(attr, dist)
                    resolved_places.append(place_dict)
                    print(f"✅ Trending '{name_str}' resolved from local DB (saved 1 Google API call)")
                else:
                    names_to_resolve_via_google.append(name_str)
            except Exception:
                # If DB search fails (e.g. search_by_name not available),
                # fall back to Google
                names_to_resolve_via_google.append(name_str)

    # 4b. Only call Google for places NOT found in local DB
    if names_to_resolve_via_google:
        async def resolve_one_place(name_str: str) -> Optional[dict]:
            try:
                # We call places_service.search which has built-in Redis caching!
                res = await search(query=name_str, latitude=latitude, longitude=longitude)
                if res.places:
                    return res.places[0].model_dump()
            except Exception as ex:
                print(f"⚠️ Error resolving place '{name_str}' in get_trending: {ex}")
            return None

        print(f"🔍 Resolving {len(names_to_resolve_via_google)} trending places via Google "
              f"(saved {len(extracted_names[:8]) - len(names_to_resolve_via_google)} calls via DB)")
        search_tasks = [resolve_one_place(n) for n in names_to_resolve_via_google]
        resolved_results = await asyncio.gather(*search_tasks)
        for r in resolved_results:
            if r is not None:
                resolved_places.append(r)

    # 5. Save in Redis (TTL = 48 hours / 172800 seconds — trending places don't
    #    churn that fast, and the previous 24h TTL was causing unnecessary
    #    re-fetches that doubled Gemini + Google costs)
    response_data = {
        "markdown": response_text,
        "places": resolved_places
    }
    # We will use place_cache_service to set the raw key in Redis
    await place_cache_service.set_raw(key, json.dumps(response_data, default=str), ttl=172800)

    return {
        "markdown": response_text,
        "places": [PlaceResponse.model_validate(p) for p in resolved_places],
        "cached": False
    }


async def get_place_details(place_id: str) -> Optional[dict]:
    """Fetch place details with 14-day Redis caching.
    Uses Google Places API (New) with field masking to minimize billing.
    """
    clean_id = place_id.replace("places/", "")
    key = f"places:details:{clean_id}"

    # 1. Check Redis cache first (14 days TTL)
    try:
        cached_raw = await place_cache_service.get_raw(key)
        if cached_raw is not None:
            data = json.loads(cached_raw)
            data["cached"] = True
            return data
    except Exception as e:
        print(f"⚠️ Redis GET error for {key}: {e}")

    # 2. Cache miss — fetch from Google Places API (New)
    details = await google_places_client.fetch_place_details(place_id)
    if not details:
        return None

    # 3. Store in Redis (14-day TTL = 1,209,600 seconds)
    try:
        await place_cache_service.set_raw(key, json.dumps(details, default=str), ttl=1209600)
    except Exception as e:
        print(f"⚠️ Redis SET error for {key}: {e}")

    details["cached"] = False
    return details

