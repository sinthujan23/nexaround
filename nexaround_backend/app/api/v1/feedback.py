"""The app's side of feedback and the quarterly survey.

The explorer always comes from the token, never from the body. App version
and platform come from the X-App-Version / X-Platform headers the app sends on
every request. Rules live in app/services/feedback_service.py.
"""
import asyncio
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Header, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.rate_limiter import check_account_rate_limit
from app.models.user import User
from app.services import feedback_service as fb

router = APIRouter(tags=["Feedback"])


class FeedbackIn(BaseModel):
    type: str = Field(max_length=12)
    text: str = Field(max_length=5000)
    screenshots: List[str] = Field(default_factory=list, max_length=fb.MAX_SCREENSHOTS)
    can_reply: bool = True
    source_screen: Optional[str] = Field(default=None, max_length=40)
    # Set when "Tell us more" came from a quick rating.
    feature: Optional[str] = Field(default=None, max_length=32)
    ref_id: Optional[str] = Field(default=None, max_length=64)
    ref_label: Optional[str] = Field(default=None, max_length=200)
    os_version: Optional[str] = Field(default=None, max_length=80)


class QuickIn(BaseModel):
    feature: str = Field(max_length=32)
    ref_id: str = Field(max_length=64)
    ref_label: Optional[str] = Field(default=None, max_length=200)
    rating: str = Field(max_length=8)
    reasons: List[str] = Field(default_factory=list, max_length=8)


class SurveyAnswerIn(BaseModel):
    nps: int = Field(ge=0, le=10)
    features: List[str] = Field(default_factory=list, max_length=20)
    build_next: List[str] = Field(default_factory=list, max_length=fb.MAX_BUILD_NEXT_PICKS)
    build_next_other: Optional[str] = Field(default=None, max_length=300)
    would_pay: str = Field(max_length=6)
    price_range: Optional[str] = Field(default=None, max_length=8)
    why_not: List[str] = Field(default_factory=list, max_length=8)
    comment: Optional[str] = Field(default=None, max_length=2000)


@router.post("/feedback/screenshots")
async def upload_screenshot(file: UploadFile = File(...), user: User = Depends(get_current_user)):
    """One screenshot for a message being written. Sent with the message as
    its returned name; kept private (only the admin panel can open it)."""
    await check_account_rate_limit(str(user.id), action="feedback_shot", max_attempts=20, window_seconds=3600)
    content = await file.read(fb.MAX_SCREENSHOT_BYTES + 1)
    name = await asyncio.to_thread(fb.save_screenshot, user.id, content)
    return {"name": name}


@router.post("/feedback")
async def send_feedback(
    data: FeedbackIn,
    x_app_version: Optional[str] = Header(None),
    x_platform: Optional[str] = Header(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    item = await fb.create_message(
        db, user, type=data.type, text=data.text, screenshots=data.screenshots, can_reply=data.can_reply,
        source_screen=data.source_screen, feature=data.feature, ref_id=data.ref_id, ref_label=data.ref_label,
        app_version=x_app_version, platform=x_platform, os_version=data.os_version,
    )
    return {"id": str(item.id), "status": item.status}


@router.post("/feedback/quick")
async def quick_rating(
    data: QuickIn,
    x_app_version: Optional[str] = Header(None),
    x_platform: Optional[str] = Header(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    item = await fb.rate(
        db, user, feature=data.feature, ref_id=data.ref_id, ref_label=data.ref_label, rating=data.rating,
        reasons=data.reasons, app_version=x_app_version, platform=x_platform,
    )
    return {"id": str(item.id), "rating": item.type}


@router.get("/feedback/mine")
async def my_feedback(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """The explorer's own messages and the team's replies (My feedback)."""
    return {"items": await fb.mine(db, user.id)}


@router.get("/survey/current")
async def current_survey(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await fb.current_for(db, user)


@router.post("/survey/{round_id}/shown")
async def survey_shown(round_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """The survey popped up by itself (counts towards the 3-times limit)."""
    await fb.mark_shown(db, round_id, user.id)
    return {"ok": True}


@router.post("/survey/{round_id}/later")
async def survey_later(round_id: uuid.UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    """"Remind me later" or closed: no pop-up for 3 days (the Home card stays)."""
    await fb.snooze(db, round_id, user.id)
    return {"ok": True}


@router.post("/survey/{round_id}/answer")
async def survey_answer(
    round_id: uuid.UUID,
    data: SurveyAnswerIn,
    x_app_version: Optional[str] = Header(None),
    x_platform: Optional[str] = Header(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await fb.answer(
        db, user, round_id, nps=data.nps, features=data.features, build_next=data.build_next,
        build_next_other=data.build_next_other, would_pay=data.would_pay, price_range=data.price_range,
        why_not=data.why_not, comment=data.comment, app_version=x_app_version, platform=x_platform,
    )
    return {"ok": True}
