import uuid
from typing import List, Optional, Tuple
from sqlalchemy import select, func, desc, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
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

    async def list_attractions(
        self, 
        skip: int = 0, 
        limit: int = 20, 
        category_id: Optional[uuid.UUID] = None,
        search_query: Optional[str] = None
    ) -> Tuple[List[Attraction], int]:
        """Get a list of attractions with optional filtering and search."""
        query = select(Attraction).options(selectinload(Attraction.category))
        
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
        return list(results.scalars().all()), total

    async def get_nearby(
        self,
        latitude: float,
        longitude: float,
        radius_m: float,
        category_id: Optional[uuid.UUID] = None,
        limit: int = 50,
        sort_by_away: bool = False
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
        
        if category_id:
            query = query.where(Attraction.category_id == category_id)
            
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
