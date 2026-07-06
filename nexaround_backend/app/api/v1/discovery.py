from typing import List
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.discovery_history import DiscoveryHistory
from app.repositories.discovery_history_repository import DiscoveryHistoryRepository
from app.schemas.discovery_history import DiscoveryHistoryCreate, DiscoveryHistoryResponse

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
