"""Neva chat with real places on a map — see `app.services.neva_service`."""
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.schemas.place import PlaceResponse
from app.services import neva_service
from app.services.settings_service import SettingsService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/neva", tags=["neva"])


class NevaChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    latitude: Optional[float] = Field(None, ge=-90.0, le=90.0)
    longitude: Optional[float] = Field(None, ge=-180.0, le=180.0)
    area: Optional[str] = Field(None, max_length=200)


class NevaChatResponse(BaseModel):
    text: str
    # Empty unless Neva searched; then nearest first, pinned 1..n on the map.
    places: list[PlaceResponse] = []
    query: str = ""
    radius_m: int = 0


@router.post("/chat", response_model=NevaChatResponse)
async def neva_chat(
    body: NevaChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """One Neva reply. "Where is…" questions come back with real places to map."""
    raw_key = await SettingsService(db).get_setting("gemini_api_key")
    api_key = (raw_key or "").strip().strip('"').strip("'")
    if not api_key:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")
    has_location = body.latitude is not None and body.longitude is not None
    try:
        reply = await neva_service.chat(
            body.message,
            api_key=api_key,
            latitude=body.latitude if has_location else None,
            longitude=body.longitude if has_location else None,
            area=body.area or "",
            user_id=current_user.id,
        )
    except neva_service.NevaUnavailable as e:
        # The app answers through the plain proxy instead.
        logger.warning("Neva chat unavailable: %s", e)
        raise HTTPException(status_code=503, detail="Neva is unavailable right now.")
    if not reply["text"]:
        raise HTTPException(status_code=503, detail="Neva returned an empty reply.")
    return NevaChatResponse(**reply)
