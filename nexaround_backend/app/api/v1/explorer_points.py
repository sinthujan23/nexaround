"""Explorer Points: a traveller's points and level, and the public explainer
behind the app's "?" buttons (TL, 2026-11-20). See services/explorer_points.py.
"""
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.explorer_points import ExplorerPointEvent
from app.models.user import User
from app.services import explorer_points

router = APIRouter(prefix="/points", tags=["Explorer points"])


class CarryOverIn(BaseModel):
    model_config = {"extra": "forbid"}

    # The XP the app kept on the phone before points moved to the server.
    xp: int = Field(..., ge=0, le=10_000_000)


@router.get("/info")
async def points_info():
    """Levels, how to earn and the rules: what the "?" explainer shows. Public."""
    return explorer_points.info()


@router.get("/me")
async def my_points(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The signed-in traveller's points, level and what they came from."""
    totals = await explorer_points.total_for(db, current_user.id)
    return explorer_points.summary(totals)


@router.post("/carry-over")
async def carry_over(
    data: CarryOverIn,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Bring the old phone-only XP over, once per account. It only tops the
    traveller up to what they had (capped): the trips that earned it are
    already counted here. A repeat send changes nothing."""
    totals = await explorer_points.total_for(db, current_user.id, fresh=True)
    if not totals.carried_over:
        points = explorer_points.carry_over_points(data.xp, totals.trip_points)
        db.add(ExplorerPointEvent(
            id=uuid.uuid4(), user_id=current_user.id,
            kind=explorer_points.EVENT_CARRY_OVER, ref="once", points=points,
        ))
        try:
            await db.commit()
        except IntegrityError:
            await db.rollback()      # a second tap that raced the first
        await explorer_points.bust(current_user.id)
        # No "level up" message: the old XP is not a new achievement.
        totals = await explorer_points.total_for(db, current_user.id, fresh=True)
    return explorer_points.summary(totals)
