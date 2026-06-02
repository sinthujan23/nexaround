from typing import List
import logging
import uuid
import json
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db, async_session
from app.api.deps import get_current_user
from app.models.user import User
from app.models.itinerary import Itinerary
from app.repositories.itinerary_repository import ItineraryRepository
from app.repositories.attraction_repository import AttractionRepository
from app.services.ai_service import ai_service
from app.services import odyssey_ai_service
from app.services.settings_service import SettingsService
from app.schemas.itinerary import (
    ItineraryCreate,
    ItineraryUpdate,
    ItineraryResponse,
    OdysseyGenerateRequest,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/itineraries", tags=["itineraries"])


@router.post("/odyssey/generate", response_model=ItineraryResponse, status_code=status.HTTP_202_ACCEPTED)
async def generate_odyssey(
    data: OdysseyGenerateRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Kick off a server-side AI Odyssey. Returns a 'generating' itinerary
    immediately; a background task fills in the plan (or marks it 'failed').

    The mobile app polls GET /itineraries to see the status flip to 'active'.
    """
    repo = ItineraryRepository(db)
    meta = odyssey_ai_service.build_meta_item(
        destination=data.destination,
        mood=data.mood,
        budget=data.budget,
        currency=data.currency,
        days=data.days,
        nights=data.days - 1 if data.days > 1 else 0,
    )
    placeholder = Itinerary(
        user_id=current_user.id,
        title=f"Planning {data.destination}…" if data.destination else "Planning your Odyssey…",
        items=[meta],
        status="generating",
    )
    saved = await repo.create(placeholder)

    background_tasks.add_task(
        _run_odyssey_generation,
        saved.id,
        current_user.id,
        data.destination,
        data.mood,
        data.budget,
        data.days,
        data.currency,
    )
    return saved


async def _run_odyssey_generation(
    itinerary_id: uuid.UUID,
    user_id: uuid.UUID,
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
) -> None:
    """Runs after the response is sent. Uses its own DB session because the
    request-scoped one is already closed."""
    async with async_session() as db:
        repo = ItineraryRepository(db)
        itin = await repo.get_by_id(itinerary_id, user_id)
        if itin is None:
            return

        api_key = await SettingsService(db).get_setting("gemini_api_key")
        if not api_key:
            logger.error("Odyssey generation skipped: gemini_api_key not configured")
            itin.status = "failed"
            await repo.update(itin)
            return

        try:
            title, items = await odyssey_ai_service.generate_odyssey(
                destination=destination,
                mood=mood,
                budget=budget,
                days=days,
                currency=currency,
                api_key=api_key,
            )
            itin.title = title
            itin.items = items
            itin.status = "active"
        except Exception as e:
            logger.error(f"Odyssey generation failed for {itinerary_id}: {e}")
            itin.status = "failed"
        await repo.update(itin)

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
