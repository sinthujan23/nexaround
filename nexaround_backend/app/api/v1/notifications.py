"""User-facing notification inbox — what the app's bell icon shows."""
import uuid
from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy import select, func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.services.auth_service import AuthService
from app.models.notification import Notification

router = APIRouter(prefix="/notifications", tags=["Notifications"])


async def _current_user(authorization: str, db: AsyncSession):
    token = (authorization or "").replace("Bearer ", "")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return await AuthService(db).get_current_user(token)


def _serialize(n: Notification) -> dict:
    return {
        "id": str(n.id),
        "title": n.title,
        "body": n.body,
        "type": n.type,
        "is_read": n.is_read,
        "created_at": n.created_at.isoformat(),
    }


@router.get("")
async def list_notifications(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """The signed-in user's inbox, newest first."""
    user = await _current_user(authorization, db)
    res = await db.execute(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(100)
    )
    return [_serialize(n) for n in res.scalars().all()]


@router.get("/unread-count")
async def unread_count(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Badge count for the bell icon."""
    user = await _current_user(authorization, db)
    count = await db.scalar(
        select(func.count(Notification.id)).where(
            Notification.user_id == user.id,
            Notification.is_read.is_(False),
        )
    ) or 0
    return {"unread": int(count)}


@router.post("/{notification_id}/read")
async def mark_read(
    notification_id: uuid.UUID,
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    user = await _current_user(authorization, db)
    await db.execute(
        update(Notification)
        .where(Notification.id == notification_id, Notification.user_id == user.id)
        .values(is_read=True)
    )
    await db.commit()
    return {"status": "ok"}


@router.post("/read-all")
async def mark_all_read(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    user = await _current_user(authorization, db)
    await db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.is_read.is_(False))
        .values(is_read=True)
    )
    await db.commit()
    return {"status": "ok"}
