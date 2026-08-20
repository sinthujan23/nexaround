import uuid
from typing import List, Optional, Tuple
from sqlalchemy import select, func, desc, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload, aliased
from geoalchemy2 import Geometry, Geography
from geoalchemy2.functions import ST_Distance, ST_DWithin
from app.models.attraction import Attraction
from app.models.category import Category
from app.utils.geo_utils import create_point


class AttractionRepository:
    """Data access layer for Attraction operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, attraction_id: uuid.UUID) -> Optional[Attraction]:
        """Get an attraction by its UUID."""
        result = await self.db.execute(
            select(Attraction)
            .where(Attraction.id == attraction_id)
            .options(selectinload(Attraction.category))
        )
        return result.scalar_one_or_none()

    async def find_duplicate_by_coordinates(
        self, 
        latitude: float, 
        longitude: float, 
        exclude_id: Optional[uuid.UUID] = None
    ) -> Optional[Attraction]:
        """Find an existing attraction with the same coordinates (within a very small tolerance)."""
        stmt = select(Attraction).where(
            func.abs(func.ST_X(Attraction.location) - longitude) < 0.000001,
            func.abs(func.ST_Y(Attraction.location) - latitude) < 0.000001
        )
        if exclude_id:
            stmt = stmt.where(Attraction.id != exclude_id)
        stmt = stmt.limit(1)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def list_attractions(
        self, 
        skip: int = 0, 
        limit: int = 20, 
        category_id: Optional[uuid.UUID] = None,
        search_query: Optional[str] = None,
        is_active: Optional[bool] = None
    ) -> Tuple[List[Tuple[Attraction, bool]], int]:
        """Get a list of attractions with optional filtering, search, and duplicate status."""
        alias = aliased(Attraction)
        
        # Subquery to check duplicate coordinates (distance < 0.000001 degrees ~ 11cm)
        dup_exists = select(1).select_from(alias).where(
            alias.id != Attraction.id,
            func.ST_DWithin(alias.location, Attraction.location, 0.000001)
        ).exists()
        
        query = select(Attraction, dup_exists.label("has_duplicate")).options(selectinload(Attraction.category))
        
        if is_active is not None:
            query = query.where(Attraction.is_active == is_active)
            
        if category_id:
            query = query.where(Attraction.category_id == category_id)
        
        if search_query:
            query = query.where(
                or_(
                    Attraction.name.ilike(f"%{search_query}%"),
                    Attraction.description.ilike(f"%{search_query}%")
                )
            )
            
        # Get total count
        count_query = select(func.count()).select_from(query.subquery())
        total = await self.db.scalar(count_query) or 0
        
        # Get actual results
        results = await self.db.execute(query.offset(skip).limit(limit))
        return [(row[0], bool(row[1])) for row in results.all()], total

    async def get_coordinates_in_bounds(
        self,
        min_lat: float,
        min_lng: float,
        max_lat: float,
        max_lng: float,
    ) -> set:
        """Coordinates of every attraction inside a bounding box.

        The duplicate check when seeding used to run find_duplicate_by_coordinates
        once per incoming place, which is one database round trip each — sixty
        places meant sixty queries. This pulls the same information in one, and
        the caller matches in memory.

        Rounded to six decimals to match the tolerance find_duplicate_by_coordinates
        applies (< 1e-6), so the two agree on what counts as the same spot.
        """
        stmt = select(
            func.ST_Y(Attraction.location),
            func.ST_X(Attraction.location),
        ).where(
            func.ST_Y(Attraction.location).between(min_lat, max_lat),
            func.ST_X(Attraction.location).between(min_lng, max_lng),
        )
        result = await self.db.execute(stmt)
        return {(round(lat, 6), round(lng, 6)) for lat, lng in result.all()}

    async def get_nearby(
        self,
        latitude: float,
        longitude: float,
        radius_m: float,
        category_id: Optional[uuid.UUID] = None,
        limit: int = 50,
        sort_by_away: bool = False,
        is_active: Optional[bool] = None,
        min_radius_m: Optional[float] = None,
        category_ids: Optional[List[uuid.UUID]] = None
    ) -> List[Tuple[Attraction, float]]:
        """Get attractions within a certain radius, with distance calculation."""
        center_point = create_point(latitude, longitude)
        
        # ST_Distance returns distance in degrees for 4326 unless we use geography
        # But we want meters. ST_Distance(geography(location), geography(point))
        # Or just use the model field if it's geography. Our model is Geometry(4326).
        distance_func = ST_Distance(
            func.geography(Attraction.location), 
            func.cast(center_point, Geography)
        )
        
        query = select(Attraction, distance_func.label("distance")).where(
            ST_DWithin(
                func.geography(Attraction.location),
                func.cast(center_point, Geography),
                radius_m
            )
        ).options(selectinload(Attraction.category))
        
        if min_radius_m is not None:
            query = query.where(distance_func >= min_radius_m)
            
        if is_active is not None:
            query = query.where(Attraction.is_active == is_active)
            
        if category_id:
            query = query.where(Attraction.category_id == category_id)

        # POI absorbed the older 'Attractions'/'Nature'/'Experiences' categories,
        # so a band query has to match every name a place may have been seeded
        # under or most of the existing rows stay invisible to it.
        if category_ids:
            query = query.where(Attraction.category_id.in_(category_ids))


        if min_radius_m is not None:
            query = query.order_by(desc(Attraction.rating), desc("distance") if sort_by_away else "distance")
        else:
            if sort_by_away:
                query = query.order_by(desc("distance"))
            else:
                query = query.order_by("distance")
            
        query = query.limit(limit)
        
        results = await self.db.execute(query)
        return [(row[0], row[1]) for row in results.all()]

    async def create(self, attraction: Attraction) -> Attraction:
        self.db.add(attraction)
        await self.db.flush()
        await self.db.refresh(attraction)
        return attraction

    async def update(self, attraction: Attraction) -> Attraction:
        await self.db.flush()
        await self.db.refresh(attraction)
        return attraction

    async def delete(self, attraction: Attraction) -> None:
        await self.db.delete(attraction)
        await self.db.flush()

    async def search_by_name(
        self,
        name: str,
        latitude: float,
        longitude: float,
        radius_m: float = 50000.0,
        limit: int = 5,
    ) -> List[Tuple[Attraction, float]]:
        """Search attractions by name (ILIKE fuzzy match) within a radius.

        Used by the trending resolution flow to check the local DB before
        calling Google Text Search, saving API costs.
        """
        center_point = create_point(latitude, longitude)
        distance_func = ST_Distance(
            func.geography(Attraction.location),
            func.cast(center_point, Geography),
        )

        query = (
            select(Attraction, distance_func.label("distance"))
            .where(
                ST_DWithin(
                    func.geography(Attraction.location),
                    func.cast(center_point, Geography),
                    radius_m,
                ),
                Attraction.is_active == True,
                Attraction.name.ilike(f"%{name}%"),
            )
            .options(selectinload(Attraction.category))
            .order_by("distance")
            .limit(limit)
        )
        results = await self.db.execute(query)
        return [(row[0], row[1]) for row in results.all()]
