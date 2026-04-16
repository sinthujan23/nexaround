from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.itinerary import Itinerary
from app.repositories.itinerary_repository import ItineraryRepository
from app.repositories.attraction_repository import AttractionRepository
from app.services.ai_service import ai_service
from app.schemas.itinerary import ItineraryCreate, ItineraryUpdate, ItineraryResponse
import uuid
import json

router = APIRouter(prefix="/itineraries", tags=["itineraries"])

@router.post("/generate", response_model=dict)
async def generate_ai_itinerary(
    location: str,
    days: int = 1,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Generate an AI-powered itinerary based on nearby attractions.
    """
    attraction_repo = AttractionRepository(db)
    # Get some nearby attractions for context (e.g. from center of Colombo)
    attractions = await attraction_repo.get_nearby(6.9271, 79.8612, 10000.0)
    
    data_str = "\n".join([f"- {a.name}: {a.description}" for a in attractions[:10]])
    
    itinerary_json = await ai_service.generate_itinerary(
        location, 
        data_str, 
        days,
        preferences=current_user.preferences
    )
    
    if not itinerary_json:
        raise HTTPException(status_code=500, detail="Failed to generate itinerary")
        
    try:
        return json.loads(itinerary_json)
    except:
        return {"error": "AI response was not valid JSON", "raw": itinerary_json}

@router.get("/", response_model=List[ItineraryResponse])
async def get_my_itineraries(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    return await repo.get_by_user(current_user.id)

@router.post("/", response_model=ItineraryResponse, status_code=status.HTTP_201_CREATED)
async def create_itinerary(
    data: ItineraryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = Itinerary(
        user_id=current_user.id,
        title=data.title,
        trip_date=data.trip_date,
        items=[item.model_dump() for item in data.items],
        status=data.status
    )
    return await repo.create(itinerary)

@router.get("/{itinerary_id}", response_model=ItineraryResponse)
async def get_itinerary(
    itinerary_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    return itinerary

@router.put("/{itinerary_id}", response_model=ItineraryResponse)
async def update_itinerary(
    itinerary_id: uuid.UUID,
    data: ItineraryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    
    if data.title is not None:
        itinerary.title = data.title
    if data.trip_date is not None:
        itinerary.trip_date = data.trip_date
    if data.items is not None:
        itinerary.items = [item.model_dump() for item in data.items]
    if data.status is not None:
        itinerary.status = data.status
        
    return await repo.update(itinerary)

@router.delete("/{itinerary_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_itinerary(
    itinerary_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itinerary = await repo.get_by_id(itinerary_id, current_user.id)
    if not itinerary:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    await repo.delete(itinerary)
    return None
