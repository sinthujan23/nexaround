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
        "created_at": attraction.created_at,
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
        repo = AttractionRepository(session)
        nearby_db_attractions = await repo.get_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_m=float(radius),
            category_id=category_id,
            limit=db_limit
        )

        # If we have a healthy list of attractions (e.g. >= 10) AND they cover the requested radius
        # adequately (e.g. at least one is in the outer 30% of the radius, or the radius is small <= 2000m)
        has_adequate_coverage = radius <= 2000 or any(dist >= radius * 0.7 for _, dist in nearby_db_attractions)
        if len(nearby_db_attractions) >= 10 and has_adequate_coverage:
            place_dicts = [
                attraction_to_place_dict(attr, dist)
                for attr, dist in nearby_db_attractions
            ]
            await place_cache_service.set_cached(key, place_dicts)
            return PlacesNearbyResponse(
                places=[PlaceResponse.model_validate(p) for p in place_dicts],
                cached=False,
                source="database",
            )

        # Otherwise, query Google Places API as a fallback
        if use_legacy:
            raw = await google_places_client.nearby_search_legacy(
                latitude=latitude,
                longitude=longitude,
                category=category,
                radius=radius,
            )
            place_dicts = [
                google_places_client.to_place_dict_legacy(p, latitude, longitude, category, _photo_url)
                for p in raw
            ]
        else:
            raw = await google_places_client.nearby_search(
                latitude=latitude,
                longitude=longitude,
                category=category,
                radius=radius,
            )
            if category == "Food & Drink":
                raw = google_places_client.filter_food(raw)
            elif category != "Beach":
                raw = raw[:40]

            place_dicts = [
                google_places_client.to_place_dict(p, latitude, longitude, category, _photo_url)
                for p in raw
            ]

        # Save newly fetched places to PostgreSQL database
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
                    is_active=True,
                )
                session.add(new_attr)

        await session.commit()

        # Re-query the database to get the complete unified set of attractions (Google + existing)
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

    place_dicts.sort(key=lambda p: p.get("distance_m") or 0)

    await place_cache_service.set_cached(key, place_dicts)

    return PlacesNearbyResponse(
        places=[PlaceResponse.model_validate(p) for p in place_dicts],
        cached=False,
        source="google",
    )
