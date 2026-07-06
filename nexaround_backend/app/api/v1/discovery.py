import uuid
import logging
from typing import List
from fastapi import APIRouter, Depends, status, BackgroundTasks
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db, async_session
from app.api.deps import get_current_user
from app.models.user import User
from app.models.discovery_history import DiscoveryHistory
from app.repositories.discovery_history_repository import DiscoveryHistoryRepository
from app.schemas.discovery_history import DiscoveryHistoryCreate, DiscoveryHistoryResponse, DiscoveryGenerateRequest
from app.services import discovery_ai_service
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/discovery", tags=["discovery"])


@router.post("/history", response_model=DiscoveryHistoryResponse, status_code=status.HTTP_201_CREATED)
async def create_discovery_history(
    data: DiscoveryHistoryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Saves a Neva AI Discovery itinerary result in user's search history."""
    repo = DiscoveryHistoryRepository(db)
    item = DiscoveryHistory(
        user_id=current_user.id,
        location=data.location,
        mode=data.mode,
        result=data.result,
    )
    saved_item = await repo.create(item)

    # Send FCM push notification when Neva finishes generating
    try:
        from app.services import fcm_service
        prefs = current_user.preferences or {}
        tokens = list(prefs.get("fcm_tokens") or [])
        legacy = prefs.get("fcm_token")
        if legacy and legacy not in tokens:
            tokens.append(legacy)
        if tokens:
            await fcm_service.send_to_tokens(
                db,
                tokens,
                title="✨ Neva Discovery Ready",
                body=f"Your itinerary for {data.location} is ready!",
                data={"type": "discovery_ready"},
            )
    except Exception as e:
        # Ignore push notification failure so it doesn't block the history saving flow
        pass

    return saved_item


@router.get("/history", response_model=List[DiscoveryHistoryResponse])
async def get_discovery_history(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retrieves previous AI Discovery itineraries for the authenticated user."""
    repo = DiscoveryHistoryRepository(db)
    return await repo.get_by_user(current_user.id)


@router.post("/generate", status_code=status.HTTP_202_ACCEPTED)
async def generate_discovery(
    data: DiscoveryGenerateRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Kick off backend Gemini discovery generation asynchronously."""
    background_tasks.add_task(
        _run_discovery_generation,
        user_id=current_user.id,
        data=data,
    )
    return {"status": "generating"}


async def _run_discovery_generation(
    user_id: uuid.UUID,
    data: DiscoveryGenerateRequest,
) -> None:
    async with async_session() as db:
        repo = DiscoveryHistoryRepository(db)

        # Get Gemini Key
        api_key = await SettingsService(db).get_setting("gemini_api_key")
        if not api_key:
            logger.error("Discovery generation skipped: gemini_api_key not configured")
            return

        try:
            # 1. Call Gemini to generate the itinerary
            from datetime import date
            date_str = date.today().strftime("%Y-%m-%d")

            raw_response = await discovery_ai_service.generate_discovery_itinerary(
                location=data.location,
                mode=data.mode,
                date_str=date_str,
                time_str=data.time_of_day,
                weather=data.weather,
                time_available=data.time_available,
                mood=data.mood,
                budget=data.budget,
                companions=data.companions,
                api_key=api_key,
            )

            # 2. Filter hallucinated stops
            hallucinated = await discovery_ai_service.find_hallucinated_places(
                text=raw_response,
                location_context=data.location,
                center_lat=data.latitude,
                center_lng=data.longitude,
            )

            filtered_response = discovery_ai_service.filter_hallucinated_stops(raw_response, hallucinated)
            clean_response = discovery_ai_service.clean_raw_urls(filtered_response)

            # 3. Save to database history
            item = DiscoveryHistory(
                user_id=user_id,
                location=data.location,
                mode=data.mode,
                result=clean_response,
            )
            await repo.create(item)

            # 4. Notify user via push notification
            user_result = await db.execute(
                select(User).where(User.id == user_id)
            )
            user = user_result.scalar_one_or_none()
            if user:
                prefs = user.preferences or {}
                tokens = list(prefs.get("fcm_tokens") or [])
                legacy = prefs.get("fcm_token")
                if legacy and legacy not in tokens:
                    tokens.append(legacy)

                if tokens:
                    from app.services import fcm_service
                    await fcm_service.send_to_tokens(
                        db=db,
                        tokens=tokens,
                        title="✨ Neva Discovery Ready",
                        body=f"Your itinerary for {data.location} is ready!",
                        data={"type": "discovery_ready"},
                    )
                else:
                    logger.warning(f"Discovery ready but user {user_id} has no device tokens")
        except Exception as e:
            logger.error(f"Discovery generation failed for user {user_id}: {e}", exc_info=True)

