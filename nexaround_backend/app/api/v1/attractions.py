import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.services.attraction_service import AttractionService
from app.schemas.attraction import (
    AttractionCreate, 
    AttractionResponse, 
    AttractionListResponse, 
    NearbyRequest
)

router = APIRouter(prefix="/attractions", tags=["attractions"])

@router.get("/", response_model=AttractionListResponse)
async def list_attractions(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    category_id: Optional[uuid.UUID] = None,
    search: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """List attractions with pagination and filtering."""
    service = AttractionService(db)
    return await service.list_attractions(
        page=page, 
        page_size=page_size, 
        category_id=category_id, 
        search_query=search,
        is_active=True
    )

@router.get("/nearby", response_model=List[AttractionResponse])
async def get_nearby_attractions(
    lat: float = Query(...),
    lng: float = Query(...),
    radius: float = Query(1000.0, description="Radius in meters"),
    category_id: Optional[uuid.UUID] = None,
    limit: int = Query(50, ge=1, le=100),
    sort: str = Query("proximity", pattern="^(proximity|away)$"),
    db: AsyncSession = Depends(get_db)
):
    """Get attractions near specific coordinates."""
    service = AttractionService(db)
    request = NearbyRequest(
        latitude=lat,
        longitude=lng,
        radius_m=radius,
        category_id=category_id,
        limit=limit,
        sort=sort
    )
    return await service.get_nearby_attractions(request)

@router.get("/{attraction_id}", response_model=AttractionResponse)
async def get_attraction(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db)
):
    """Get a single attraction by ID."""
    service = AttractionService(db)
    result = await service.get_attraction(attraction_id)
    # Record a place visit — the real source for the admin 'Places Visited'
    # metric. Best-effort: analytics must never break the detail read.
    try:
        from app.models.analytics import PlaceVisit
        db.add(PlaceVisit(attraction_id=attraction_id))
        await db.commit()
    except Exception:
        await db.rollback()
    return result

@router.post("/", response_model=AttractionResponse, status_code=status.HTTP_201_CREATED)
async def create_attraction(
    data: AttractionCreate,
    db: AsyncSession = Depends(get_db)
):
    """Create a new attraction."""
    service = AttractionService(db)
    return await service.create_attraction(data)
