import uuid
from typing import List, Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from app.repositories.attraction_repository import AttractionRepository
from app.models.attraction import Attraction
from app.schemas.attraction import (
    AttractionCreate, 
    AttractionResponse, 
    AttractionListResponse, 
    NearbyRequest
)
from app.utils.geo_utils import create_point, get_lat_lng
from app.core.exceptions import NotFoundException


class AttractionService:
    """Business logic for Attraction management."""

    def __init__(self, db: AsyncSession):
        self.repo = AttractionRepository(db)

    def _map_to_response(self, attraction: Attraction, distance_m: Optional[float] = None) -> AttractionResponse:
        """Helper to map a model to a response schema."""
        lat, lng = get_lat_lng(attraction.location)
        
        response_dict = {
            "id": attraction.id,
            "name": attraction.name,
            "description": attraction.description,
            "history": attraction.history,
            "latitude": lat,
            "longitude": lng,
            "category_id": attraction.category_id,
            "category_name": attraction.category.name if attraction.category else None,
            "address": attraction.address,
            "opening_hours": attraction.opening_hours,
            "entry_fee": attraction.entry_fee,
            "currency": attraction.currency,
            "rating": attraction.rating,
            "review_count": attraction.review_count,
            "photo_urls": attraction.photo_urls,
            "tags": attraction.tags,
            "geofence_radius_m": attraction.geofence_radius_m,
            "distance_m": distance_m,
            "is_active": attraction.is_active,
            "created_at": attraction.created_at
        }
        return AttractionResponse.model_validate(response_dict)

    async def get_attraction(self, attraction_id: uuid.UUID) -> AttractionResponse:
        """Get an attraction by ID."""
        attraction = await self.repo.get_by_id(attraction_id)
        if not attraction:
            raise NotFoundException(detail="Attraction not found")
        return self._map_to_response(attraction)

    async def list_attractions(
        self, 
        page: int = 1, 
        page_size: int = 20, 
        category_id: Optional[uuid.UUID] = None,
        search_query: Optional[str] = None
    ) -> AttractionListResponse:
        """List attractions with pagination."""
        skip = (page - 1) * page_size
        attractions, total = await self.repo.list_attractions(
            skip=skip, 
            limit=page_size, 
            category_id=category_id, 
            search_query=search_query
        )
        
        return AttractionListResponse(
            attractions=[self._map_to_response(a) for a in attractions],
            total=total,
            page=page,
            page_size=page_size
        )

    async def get_nearby_attractions(self, request: NearbyRequest) -> List[AttractionResponse]:
        """Get attractions near a coordinate."""
        nearby_data = await self.repo.get_nearby(
            latitude=request.latitude,
            longitude=request.longitude,
            radius_m=request.radius_m,
            category_id=request.category_id,
            limit=request.limit,
            sort_by_away=(request.sort == "away")
        )
        
        return [self._map_to_response(a, dist) for a, dist in nearby_data]

    async def create_attraction(self, data: AttractionCreate) -> AttractionResponse:
        """Create a new attraction."""
        attraction = Attraction(
            name=data.name,
            description=data.description,
            history=data.history,
            location=create_point(data.latitude, data.longitude),
            category_id=data.category_id,
            address=data.address,
            opening_hours=data.opening_hours,
            entry_fee=data.entry_fee,
            currency=data.currency,
            photo_urls=data.photo_urls,
            tags=data.tags,
            geofence_radius_m=data.geofence_radius_m
        )
        
        attraction = await self.repo.create(attraction)
        # Re-fetch to load relationship
        full_attraction = await self.repo.get_by_id(attraction.id)
        return self._map_to_response(full_attraction)

    async def update_attraction(self, attraction_id: uuid.UUID, data: dict) -> AttractionResponse:
        """Update an existing attraction."""
        attraction = await self.repo.get_by_id(attraction_id)
        if not attraction:
            raise NotFoundException(detail="Attraction not found")
        
        # Update fields if present in data
        if "name" in data: attraction.name = data["name"]
        if "description" in data: attraction.description = data["description"]
        if "history" in data: attraction.history = data["history"]
        if "latitude" in data and "longitude" in data:
            attraction.location = create_point(data["latitude"], data["longitude"])
        if "category_id" in data: attraction.category_id = data["category_id"]
        if "address" in data: attraction.address = data["address"]
        if "opening_hours" in data: attraction.opening_hours = data["opening_hours"]
        if "entry_fee" in data: attraction.entry_fee = data["entry_fee"]
        if "currency" in data: attraction.currency = data["currency"]
        if "tags" in data: attraction.tags = data["tags"]
        if "geofence_radius_m" in data: attraction.geofence_radius_m = data["geofence_radius_m"]
        if "is_active" in data: attraction.is_active = data["is_active"]
        
        updated_attraction = await self.repo.update(attraction)
        return self._map_to_response(updated_attraction)

    async def delete_attraction(self, attraction_id: uuid.UUID) -> bool:
        """Delete an attraction."""
        attraction = await self.repo.get_by_id(attraction_id)
        if not attraction:
            raise NotFoundException(detail="Attraction not found")
        
        await self.repo.delete(attraction)
        return True
