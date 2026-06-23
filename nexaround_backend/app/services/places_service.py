"""Top-level Places service: cache-first, Google as fallback."""
import json
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


# --- Around You Optimization Constants & Helpers ---

ALLOWED_TYPES = {
    # High Priority
    "tourist_attraction", "museum", "park", "zoo", "aquarium", "amusement_park",
    "art_gallery", "landmark", "historical_landmark", "cultural_center",
    "hindu_temple", "buddhist_temple", "church", "mosque", "national_park",
    "nature_reserve", "event_venue",
    # Medium Priority
    "shopping_mall", "bookstore", "market", "public_square"
}

EXCLUDED_TYPES = {
    "lodging", "hotel", "motel", "apartment_complex", "residential",
    "housing_complex", "real_estate_agency", "private_property", "accommodation"
}

FOOD_TYPES = {
    "restaurant", "cafe", "bakery", "food", "bar", "coffee_shop"
}

CATEGORY_IMPORTANCE_WEIGHTS = {
    "tourist_attraction": 100.0,
    "museum": 95.0,
    "historical_landmark": 95.0,
    "landmark": 95.0,
    "park": 85.0,
    "zoo": 85.0,
    "aquarium": 85.0,
    "amusement_park": 85.0,
    "art_gallery": 85.0,
    "cultural_center": 85.0,
    "hindu_temple": 85.0,
    "buddhist_temple": 85.0,
    "church": 85.0,
    "mosque": 85.0,
    "national_park": 85.0,
    "nature_reserve": 85.0,
    "event_venue": 85.0,
    "shopping_mall": 70.0,
    "bookstore": 65.0,
    "market": 65.0,
    "public_square": 65.0,
}

PRIVATE_KEYWORDS = {
    "home", "house", "residence", "'s place", "my place", "my home", "private",
    "personal", "apartment", "flat", "villa", "homestay", "guest house",
    "guesthouse", "3bhk", "2bhk", "4bhk", "1bhk", "cottage", "bungalow", "stay"
}
PUBLIC_ALLOWWORDS = {"museum", "historic", "heritage", "public"}


def _calculate_distance_score(distance_m: float) -> float:
    if distance_m <= 200:
        return 100.0
    elif distance_m <= 1000:
        return 100.0 - (distance_m - 200.0) / 800.0 * 15.0
    elif distance_m <= 3000:
        return 85.0 - (distance_m - 1000.0) / 2000.0 * 25.0
    elif distance_m <= 10000:
        return 60.0 - (distance_m - 3000.0) / 7000.0 * 40.0
    else:
        return max(20.0 - (distance_m - 10000.0) / 40000.0 * 20.0, 0.0)


def _calculate_rating_score(rating: float) -> float:
    return float(rating) * 20.0


def _calculate_review_score(review_count: int) -> float:
    if review_count <= 0:
        return 0.0
    if review_count >= 1000:
        return 100.0
    if review_count < 10:
        return float(review_count)
    import math
    log_val = math.log10(review_count)
    return 10.0 + (log_val - 1.0) / 2.0 * 90.0


def _calculate_category_importance(types: list[str]) -> float:
    max_weight = 50.0
    for t in types:
        if t in CATEGORY_IMPORTANCE_WEIGHTS:
            max_weight = max(max_weight, CATEGORY_IMPORTANCE_WEIGHTS[t])
    return max_weight


def _calculate_discovery_score(distance_m: float, rating: float, review_count: int, types: list[str]) -> float:
    dist_s = _calculate_distance_score(distance_m)
    rate_s = _calculate_rating_score(rating)
    rev_s = _calculate_review_score(review_count)
    cat_s = _calculate_category_importance(types)
    return 0.40 * dist_s + 0.25 * rate_s + 0.20 * rev_s + 0.15 * cat_s


def _check_is_hidden_gem(rating: float, review_count: int) -> bool:
    return rating >= 4.5 and 20 <= review_count <= 300


def _fallback_is_public(name: str, description: str) -> bool:
    name_lower = name.lower()
    desc_lower = (description or "").lower()
    for word in PRIVATE_KEYWORDS:
        if word in name_lower or word in desc_lower:
            if any(allow in name_lower or allow in desc_lower for allow in PUBLIC_ALLOWWORDS):
                continue
            return False
    return True


def _classify_place(place_dict: dict) -> bool:
    tags = place_dict.get("tags") or []
    if tags:
        if any(t in EXCLUDED_TYPES for t in tags):
            return False
        return any(t in ALLOWED_TYPES for t in tags) or any(t in FOOD_TYPES for t in tags)
    else:
        return _fallback_is_public(place_dict.get("name", ""), place_dict.get("description", ""))


async def get_nearby(
    *,
    latitude: float,
    longitude: float,
    category: Optional[str],
    radius: int,
    use_legacy: bool = False,
    around_you: bool = False,
) -> PlacesNearbyResponse:
    # Canonicalize once at the entry point so the cache key, the Google call,
    # and the filter_food decision below all agree on the same category value.
    category = google_places_client.canonical_category(category)
    key = place_cache_service.build_key(latitude, longitude, category, radius)
    if use_legacy:
        key = f"{key}:legacy"
    if around_you:
        key = f"{key}:around_you"

    # 1. Redis Cache Check
    # If around_you=True, check the Redis Geospatial Cache
    if around_you:
        client = place_cache_service._get_client()
        try:
            place_ids = await client.execute_command("GEORADIUS", "places:geo", longitude, latitude, radius, "m")
        except Exception as e:
            print(f"⚠️ Redis GEORADIUS error: {e}")
            place_ids = []

        if place_ids:
            pipeline = client.pipeline()
            for pid in place_ids:
                pipeline.get(f"places:detail:{pid}")
            raw_details = await pipeline.execute()

            cached_places = []
            for raw_detail in raw_details:
                if raw_detail:
                    try:
                        p_dict = json.loads(raw_detail)
                        plat = p_dict["latitude"]
                        plng = p_dict["longitude"]
                        dist_m = _haversine_m(latitude, longitude, plat, plng)
                        
                        p_dict["distance_m"] = dist_m
                        p_dict["discovery_score"] = _calculate_discovery_score(
                            dist_m, p_dict.get("rating", 0.0), p_dict.get("review_count", 0), p_dict.get("tags", [])
                        )
                        p_dict["is_hidden_gem"] = _check_is_hidden_gem(p_dict.get("rating", 0.0), p_dict.get("review_count", 0))
                        
                        p_dict["category"] = p_dict.get("category_name")
                        p_dict["photo_url"] = p_dict["photo_urls"][0] if p_dict.get("photo_urls") else ""
                        
                        # Apply category filtering if specified
                        if category:
                            if p_dict.get("category_name") == category or p_dict.get("category") == category:
                                cached_places.append(p_dict)
                        else:
                            cached_places.append(p_dict)
                    except Exception as e:
                        print(f"⚠️ Error parsing cached detail: {e}")

            # Sort and validate coverage
            cached_places.sort(key=lambda p: p.get("discovery_score", 0.0), reverse=True)
            min_count = 10 if radius >= 5000 else 5
            if len(cached_places) >= min_count:
                return PlacesNearbyResponse(
                    places=[PlaceResponse.model_validate(p) for p in cached_places],
                    cached=True,
                    source="cache",
                )
    else:
        # Standard Grid Key Cache Check
        cached = await place_cache_service.get_cached(key)
        if cached is not None:
            # Map standard compatibility fields
            for p in cached:
                p["category"] = p.get("category_name")
                p["photo_url"] = p["photo_urls"][0] if p.get("photo_urls") else ""
            return PlacesNearbyResponse(
                places=[PlaceResponse.model_validate(p) for p in cached],
                cached=True,
                source="cache",
            )

    # 2. Redis Cache Missed. Query local PostgreSQL database
    async with async_session() as session:
        category_id = None
        if category:
            stmt = select(Category).where(Category.name == category)
            res = await session.execute(stmt)
            cat_obj = res.scalar_one_or_none()
            if cat_obj:
                category_id = cat_obj.id

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

        if around_you:
            db_places = []
            for attr, dist in nearby_db_attractions:
                p_dict = attraction_to_place_dict(attr, dist)
                plat = p_dict["latitude"]
                plng = p_dict["longitude"]
                dist_m = _haversine_m(latitude, longitude, plat, plng)
                p_dict["distance_m"] = dist_m

                # Classify
                if not _classify_place(p_dict):
                    continue

                p_dict["discovery_score"] = _calculate_discovery_score(
                    dist_m, p_dict.get("rating", 0.0), p_dict.get("review_count", 0), p_dict.get("tags", [])
                )
                p_dict["is_hidden_gem"] = _check_is_hidden_gem(p_dict.get("rating", 0.0), p_dict.get("review_count", 0))
                p_dict["category"] = p_dict.get("category_name")
                p_dict["photo_url"] = p_dict["photo_urls"][0] if p_dict.get("photo_urls") else ""
                db_places.append(p_dict)

            min_count = 10 if radius >= 5000 else 5
            if len(db_places) >= min_count:
                # Store in Redis Geospatial Cache
                try:
                    client = place_cache_service._get_client()
                    pipeline = client.pipeline()
                    for p in db_places:
                        pid = p["id"]
                        pipeline.set(f"places:detail:{pid}", json.dumps(p), ex=7 * 24 * 60 * 60)
                        pipeline.execute_command("GEOADD", "places:geo", p["longitude"], p["latitude"], pid)
                    await pipeline.execute()
                except Exception as e:
                    print(f"⚠️ Redis GEO Cache write error: {e}")

                db_places.sort(key=lambda p: p.get("discovery_score", 0.0), reverse=True)
                return PlacesNearbyResponse(
                    places=[PlaceResponse.model_validate(p) for p in db_places],
                    cached=False,
                    source="database",
                )
        else:
            # Standard Database handling (has_adequate_coverage checks)
            has_adequate_coverage = radius <= 2000 or any(dist >= radius * 0.7 for _, dist in nearby_db_attractions)
            if len(nearby_db_attractions) >= 10:
                place_dicts = [
                    attraction_to_place_dict(attr, dist)
                    for attr, dist in nearby_db_attractions
                ]
                place_dicts = _enforce_distance_distribution(place_dicts, radius)

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

                # Map standard compatibility fields
                for p in place_dicts:
                    p["category"] = p.get("category_name")
                    p["photo_url"] = p["photo_urls"][0] if p.get("photo_urls") else ""

                await place_cache_service.set_cached(key, place_dicts)
                return PlacesNearbyResponse(
                    places=[PlaceResponse.model_validate(p) for p in place_dicts],
                    cached=False,
                    source="database",
                )

        existing_records = [
            (get_lat_lng(attr.location), attr.name)
            for attr, _ in nearby_db_attractions
        ]

    # Session closed here! No connection is held during the slow Google query.

    # 3. Query Google Places API as a fallback
    import asyncio
    if radius < 25000:
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
        mid = radius * 0.7
        sample_radius = int(radius * 0.5)
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
                print(f"⚠️ Error fetching offset nearby search in get_nearby: {e}")
                return []

        results = await asyncio.gather(*(fetch_one(lat, lng, rad) for lat, lng, rad in all_queries))
        raw_places = []
        seen_ids = set()
        for r_list in results:
            for p in r_list:
                pid = p.get("id") or p.get("place_id")
                if pid and pid not in seen_ids:
                    seen_ids.add(pid)
                    raw_places.append(p)

    # Convert raw places to PlaceResponse format dicts
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

        final_places = []
        for attr, dist in nearby_db_attractions:
            p_dict = attraction_to_place_dict(attr, dist)
            plat = p_dict["latitude"]
            plng = p_dict["longitude"]
            dist_m = _haversine_m(latitude, longitude, plat, plng)
            p_dict["distance_m"] = dist_m

            if around_you:
                if not _classify_place(p_dict):
                    continue
                p_dict["discovery_score"] = _calculate_discovery_score(
                    dist_m, p_dict.get("rating", 0.0), p_dict.get("review_count", 0), p_dict.get("tags", [])
                )
                p_dict["is_hidden_gem"] = _check_is_hidden_gem(p_dict.get("rating", 0.0), p_dict.get("review_count", 0))
            
            p_dict["category"] = p_dict.get("category_name")
            p_dict["photo_url"] = p_dict["photo_urls"][0] if p_dict.get("photo_urls") else ""
            final_places.append(p_dict)

        if around_you:
            # Cache details and geo index
            try:
                client = place_cache_service._get_client()
                pipeline = client.pipeline()
                for p in final_places:
                    pid = p["id"]
                    pipeline.set(f"places:detail:{pid}", json.dumps(p), ex=7 * 24 * 60 * 60)
                    pipeline.execute_command("GEOADD", "places:geo", p["longitude"], p["latitude"], pid)
                await pipeline.execute()
            except Exception as e:
                print(f"⚠️ Redis GEO Cache write error: {e}")
            
            final_places.sort(key=lambda p: p.get("discovery_score", 0.0), reverse=True)
        else:
            final_places = _enforce_distance_distribution(final_places, radius)
            await place_cache_service.set_cached(key, final_places)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in final_places],
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

