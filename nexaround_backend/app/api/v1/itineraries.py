from typing import List, Optional
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
    OdysseySwapRequest,
    OdysseyPartnerSwapRequest,
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
    start_dt_str = data.start_date or data.flight_start_date or data.hotel_check_in_date or ""
    end_dt_str = data.end_date or data.flight_end_date or data.hotel_check_out_date or ""

    trip_dt = None
    if start_dt_str:
        try:
            from datetime import datetime as dt
            trip_dt = dt.strptime(start_dt_str, "%Y-%m-%d").date()
        except Exception:
            pass

    meta = odyssey_ai_service.build_meta_item(
        destination=data.destination,
        mood=data.mood,
        budget=data.budget,
        currency=data.currency,
        days=data.days,
        nights=data.days - 1 if data.days > 1 else 0,
        travelers=data.travelers,
        start_date=start_dt_str,
        end_date=end_dt_str,
        departure_city=data.departure_city or "",
    )
    placeholder = Itinerary(
        user_id=current_user.id,
        title=f"Planning {data.destination}…" if data.destination else "Planning your Odyssey…",
        items=[meta],
        status="generating",
        trip_date=trip_dt,
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
        data.travelers,
        data.include_flights,
        data.departure_city,
        data.departure_country,
        data.flight_start_date,
        data.flight_end_date,
        data.include_hotels,
        data.hotel_check_in_date,
        data.hotel_check_out_date,
        data.start_date,
        data.end_date,
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
    travelers: int = 1,
    include_flights: bool = False,
    departure_city: str = "",
    departure_country: str = "",
    flight_start_date: Optional[str] = None,
    flight_end_date: Optional[str] = None,
    include_hotels: bool = False,
    hotel_check_in_date: Optional[str] = None,
    hotel_check_out_date: Optional[str] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
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
            print(f"[ODYSSEY] FAILED {itinerary_id}: gemini_api_key not configured", flush=True)
            itin.status = "failed"
            await repo.update(itin)
            return

        unsplash_api_key = await SettingsService(db).get_setting("unsplash_api_key")
        serpapi_key = await SettingsService(db).get_setting("serpapi_key")

        try:
            title, items = await odyssey_ai_service.generate_odyssey(
                destination=destination,
                mood=mood,
                budget=budget,
                days=days,
                currency=currency,
                travelers=travelers,
                api_key=api_key,
                unsplash_api_key=unsplash_api_key,
                serpapi_key=serpapi_key or "",
                include_flights=include_flights,
                departure_city=departure_city,
                departure_country=departure_country,
                flight_start_date=flight_start_date,
                flight_end_date=flight_end_date,
                include_hotels=include_hotels,
                hotel_check_in_date=hotel_check_in_date,
                hotel_check_out_date=hotel_check_out_date,
                start_date=start_date or "",
                end_date=end_date or "",
            )
            itin.title = title
            itin.items = items
            itin.status = "active"
            start_dt_str = start_date or flight_start_date or hotel_check_in_date
            if start_dt_str:
                try:
                    from datetime import datetime as dt
                    itin.trip_date = dt.strptime(start_dt_str, "%Y-%m-%d").date()
                except Exception:
                    pass
            print(f"[ODYSSEY] SUCCESS {itinerary_id}: {title}", flush=True)
        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            logger.error(f"Odyssey generation failed for {itinerary_id}: {e}")
            print(f"[ODYSSEY] FAILED {itinerary_id}: {e}\n{tb}", flush=True)
            itin.status = "failed"
        await repo.update(itin)

        if itin.status == "active":
            await _notify_odyssey_ready(db, user_id, itin.title, itinerary_id)


async def _notify_odyssey_ready(db, user_id, title, itinerary_id) -> None:
    """Best-effort push telling the user their Odyssey finished generating.
    Sends to every device the user is signed in on (Android + iOS) and prunes
    any tokens FCM reports as dead."""
    try:
        from sqlalchemy import select
        from app.models.user import User
        from app.services import fcm_service

        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            return
        prefs = user.preferences or {}
        tokens = list(prefs.get("fcm_tokens") or [])
        legacy = prefs.get("fcm_token")  # pre-multi-device single token
        if legacy and legacy not in tokens:
            tokens.append(legacy)
        if not tokens:
            logger.warning(f"Odyssey ready but user {user_id} has no device tokens")
            return

        invalid = await fcm_service.send_to_tokens(
            db,
            tokens,
            title="Your Odyssey is ready ✨",
            body=title or "Tap to view your trip plan.",
            data={"type": "odyssey_ready", "itinerary_id": str(itinerary_id)},
        )
        if invalid:
            new_prefs = {**prefs, "fcm_tokens": [t for t in tokens if t not in invalid]}
            new_prefs.pop("fcm_token", None)  # drop legacy if it was dead
            user.preferences = new_prefs
            await db.commit()
    except Exception as e:
        logger.error(f"Odyssey-ready notification failed for {itinerary_id}: {e}")


@router.post("/{itinerary_id}/odyssey/swap", response_model=ItineraryResponse)
async def swap_odyssey_activity(
    itinerary_id: uuid.UUID,
    data: OdysseySwapRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Replace a single activity in a saved Odyssey with an AI-suggested
    alternative (e.g. the user already visited it or isn't interested). Runs
    synchronously — a single place is fast — and returns the updated itinerary.
    """
    repo = ItineraryRepository(db)
    itin = await repo.get_by_id(itinerary_id, current_user.id)
    if not itin:
        raise HTTPException(status_code=404, detail="Itinerary not found")

    items = [dict(it) for it in (itin.items or [])]
    meta = next((it for it in items if it.get("kind") == "odyssey_meta"), {})
    if not meta:
        raise HTTPException(status_code=400, detail="Not an Odyssey")

    day_positions = [i for i, it in enumerate(items) if it.get("kind") == "day"]
    if data.day_index < 0 or data.day_index >= len(day_positions):
        raise HTTPException(status_code=400, detail="Invalid day index")
    pos = day_positions[data.day_index]
    day = dict(items[pos])
    activities = [dict(a) for a in (day.get("activities") or [])]
    if data.activity_index < 0 or data.activity_index >= len(activities):
        raise HTTPException(status_code=400, detail="Invalid activity index")

    api_key = await SettingsService(db).get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI is not configured")

    old = activities[data.activity_index]
    existing_names = [
        str(a.get("name") or "")
        for d in items if d.get("kind") == "day"
        for a in (d.get("activities") or [])
    ]

    try:
        replacement = await odyssey_ai_service.generate_replacement_activity(
            destination=str(meta.get("destination") or ""),
            mood=str(meta.get("mood") or ""),
            budget=float(meta.get("budget") or 0),
            currency=str(meta.get("currency") or "USD"),
            day_no=int(day.get("day") or data.day_index + 1),
            theme=str(day.get("theme") or ""),
            time_slot=str(old.get("time") or ""),
            old_name=str(old.get("name") or ""),
            reason=data.reason,
            existing_names=existing_names,
            api_key=api_key,
        )
    except Exception as e:
        logger.error(f"Odyssey swap failed for {itinerary_id}: {e}")
        raise HTTPException(status_code=502, detail="Could not generate a replacement")

    activities[data.activity_index] = replacement
    day["activities"] = activities
    items[pos] = day
    itin.items = items  # reassign whole list so SQLAlchemy persists the JSON change
    return await repo.update(itin)


@router.post("/{itinerary_id}/odyssey/swap-partner", response_model=ItineraryResponse)
async def swap_odyssey_partner(
    itinerary_id: uuid.UUID,
    data: OdysseyPartnerSwapRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Replace a single booking partner in a saved Odyssey with an AI-suggested
    alternative. Runs synchronously and returns the updated itinerary.
    """
    repo = ItineraryRepository(db)
    itin = await repo.get_by_id(itinerary_id, current_user.id)
    if not itin:
        raise HTTPException(status_code=404, detail="Itinerary not found")

    items = [dict(it) for it in (itin.items or [])]
    meta_idx = next((i for i, it in enumerate(items) if it.get("kind") == "odyssey_meta"), -1)
    if meta_idx == -1:
        raise HTTPException(status_code=400, detail="Not an Odyssey")
    
    meta = dict(items[meta_idx])
    partners = [dict(p) for p in (meta.get("booking_partners") or [])]
    
    # Find the partner to swap
    target_idx = next((i for i, p in enumerate(partners) if p.get("name") == data.partner_name), -1)
    if target_idx == -1:
        raise HTTPException(status_code=400, detail="Booking partner not found in this Odyssey")
    
    target_partner = partners[target_idx]
    partner_type = target_partner.get("type", "hotels")

    api_key = await SettingsService(db).get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI is not configured")

    # Collect existing names to avoid duplicates
    avoid_names = [str(p.get("name") or "") for p in partners]

    try:
        replacement = await odyssey_ai_service.generate_replacement_partner(
            destination=str(meta.get("destination") or ""),
            partner_name=data.partner_name,
            partner_type=partner_type,
            reason=data.reason,
            avoid_names=avoid_names,
            api_key=api_key,
        )
    except Exception as e:
        logger.error(f"Odyssey partner swap failed for {itinerary_id}: {e}")
        raise HTTPException(status_code=502, detail="Could not generate a replacement partner")

    partners[target_idx] = replacement
    meta["booking_partners"] = partners
    items[meta_idx] = meta
    itin.items = items  # reassign whole list so SQLAlchemy persists the JSON change
    return await repo.update(itin)


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

async def _heal_itinerary_cover_photo(itin: Itinerary, repo: ItineraryRepository, db: AsyncSession) -> None:
    items = itin.items or []
    if not (isinstance(items, list) and len(items) > 0):
        return
    meta = items[0]
    if not (isinstance(meta, dict) and meta.get("kind") == "odyssey_meta"):
        return
    
    if meta.get("cover_url"):
        return
        
    unsplash_key = await SettingsService(db).get_setting("unsplash_api_key")
    if not unsplash_key:
        return
        
    destination = meta.get("destination")
    if not destination:
        return
        
    cover_url = await odyssey_ai_service.fetch_unsplash_cover_photo(destination, unsplash_key)
    if cover_url:
        new_items = [dict(i) for i in items]
        new_items[0]["cover_url"] = cover_url
        itin.items = new_items
        await repo.update(itin)


@router.get("/", response_model=List[ItineraryResponse])
async def get_my_itineraries(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    repo = ItineraryRepository(db)
    itineraries = await repo.get_by_user(current_user.id)
    for itin in itineraries:
        try:
            await _heal_itinerary_cover_photo(itin, repo, db)
        except Exception as e:
            logger.error(f"Failed to heal itinerary {itin.id} cover: {e}")
    return itineraries


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
    try:
        await _heal_itinerary_cover_photo(itinerary, repo, db)
    except Exception as e:
        logger.error(f"Failed to heal itinerary {itinerary_id} cover: {e}")
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
