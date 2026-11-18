"""Photos travellers send for places that have none (TL, 2026-11-18).

The app offers "Add a photo" on a place showing its category icon. The photo
waits for an admin in Admin › Media; once approved it shows for that place to
everyone. See services/place_photos.py.
"""
import asyncio
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.models.attraction import Attraction
from app.models.place_photo import PlacePhoto
from app.models.user import User
from app.services import experience_reviews, place_photos, place_reviews
from app.utils.geo_utils import get_lat_lng

router = APIRouter(prefix="/places", tags=["Place photos"])
admin_router = APIRouter(prefix="/admin/place-photos", tags=["Admin: place photos"])


class MyPlacePhoto(BaseModel):
    id: uuid.UUID
    status: str
    url: Optional[str] = None
    reject_reason: Optional[str] = None
    created_at: datetime


class PlacePhotoAdmin(BaseModel):
    id: uuid.UUID
    place_key: str
    place_name: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    user_id: uuid.UUID
    uploader_name: str
    url: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    size_bytes: Optional[int] = None
    status: str
    reject_reason: Optional[str] = None
    created_at: datetime
    reviewed_at: Optional[datetime] = None


class PlacePhotoAdminList(BaseModel):
    photos: list[PlacePhotoAdmin]
    total: int
    page: int = 1
    page_size: int = 24


class PlacePhotoAdminUpdate(BaseModel):
    status: str = Field(..., max_length=12)
    reason: Optional[str] = Field(None, max_length=200)


def _mine(p: PlacePhoto) -> MyPlacePhoto:
    return MyPlacePhoto(id=p.id, status=p.status, url=p.url,
                        reject_reason=p.reject_reason, created_at=p.created_at)


def _admin(p: PlacePhoto) -> PlacePhotoAdmin:
    return PlacePhotoAdmin(
        id=p.id, place_key=p.place_key, place_name=p.place_name,
        latitude=p.latitude, longitude=p.longitude, user_id=p.user_id,
        uploader_name=p.uploader_name, url=p.url, width=p.width, height=p.height,
        size_bytes=p.size_bytes, status=p.status, reject_reason=p.reject_reason,
        created_at=p.created_at, reviewed_at=p.reviewed_at,
    )


def _check_id(place_id: str) -> None:
    if not place_reviews.valid_place_id(place_id):
        raise HTTPException(status_code=404, detail="Place not found")


@router.post("/{place_id}/photos", response_model=MyPlacePhoto,
             status_code=status.HTTP_201_CREATED)
async def upload_place_photo(
    place_id: str,
    file: UploadFile = File(...),
    place_name: str = Form(..., min_length=1, max_length=255),
    latitude: Optional[float] = Form(None, ge=-90, le=90),
    longitude: Optional[float] = Form(None, ge=-180, le=180),
    consent: bool = Form(False),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Send a photo for a place. It shows once an admin approves it."""
    _check_id(place_id)
    if not consent:
        raise HTTPException(
            status_code=400,
            detail="Please confirm you took this photo and allow nexAround to show it.",
        )
    key, keys = await place_reviews.canonical_key(db, place_id)

    has_photo = await db.scalar(
        select(PlacePhoto.id).where(
            PlacePhoto.place_key.in_(keys), PlacePhoto.status == place_photos.APPROVED,
        ).limit(1)
    )
    if has_photo:
        raise HTTPException(status_code=409, detail="This place already has a photo.")
    waiting = await db.scalar(
        select(PlacePhoto.id).where(
            PlacePhoto.place_key.in_(keys), PlacePhoto.user_id == current_user.id,
            PlacePhoto.status == place_photos.PENDING,
        ).limit(1)
    )
    if waiting:
        raise HTTPException(
            status_code=409,
            detail="Your photo for this place is already waiting for our team.",
        )
    now = datetime.now(timezone.utc)
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today = await db.scalar(
        select(func.count()).select_from(PlacePhoto).where(
            PlacePhoto.user_id == current_user.id, PlacePhoto.created_at >= midnight,
        )
    )
    if (today or 0) >= place_photos.MAX_UPLOADS_PER_DAY:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="You have sent a lot of photos today. Please try again tomorrow.",
        )

    content = await file.read()
    # Decoding and re-encoding is CPU work: off the event loop.
    url, width, height, size = await asyncio.to_thread(place_photos.save_upload, content)
    name, lat, lng = place_name.strip(), latitude, longitude
    if place_reviews._is_uuid(place_id):
        row = await db.get(Attraction, uuid.UUID(place_id))
        if row is not None:
            name = row.name or name
            lat, lng = get_lat_lng(row.location)
    photo = PlacePhoto(
        id=uuid.uuid4(), place_key=key, user_id=current_user.id,
        uploader_name=experience_reviews.reviewer_display_name(current_user.display_name),
        place_name=name[:255], latitude=lat, longitude=lng,
        url=url, width=width, height=height, size_bytes=size,
        status=place_photos.PENDING, created_at=now,
    )
    db.add(photo)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        place_photos.delete_file(url)
        raise
    await db.refresh(photo)
    return _mine(photo)


@router.get("/{place_id}/photo/mine", response_model=Optional[MyPlacePhoto])
async def my_place_photo(
    place_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The newest photo this traveller sent for this place, or null."""
    _check_id(place_id)
    _, keys = await place_reviews.canonical_key(db, place_id)
    photo = await db.scalar(
        select(PlacePhoto)
        .where(PlacePhoto.place_key.in_(keys), PlacePhoto.user_id == current_user.id)
        .order_by(PlacePhoto.created_at.desc()).limit(1)
    )
    return _mine(photo) if photo is not None else None


# ── Admin › Media ───────────────────────────────────────────────────────────

@admin_router.get("", response_model=PlacePhotoAdminList)
async def admin_list_place_photos(
    status_filter: Optional[str] = Query(None, alias="status"),
    page: int = Query(1, ge=1),
    page_size: int = Query(24, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Photos sent by travellers. Waiting ones oldest first, the rest newest first."""
    if status_filter and status_filter not in place_photos.STATUSES:
        raise HTTPException(status_code=400, detail="Unknown status.")
    conditions = [PlacePhoto.status == status_filter] if status_filter else []
    order = (PlacePhoto.created_at.asc() if status_filter == place_photos.PENDING
             else PlacePhoto.created_at.desc())
    total = await db.scalar(select(func.count()).select_from(PlacePhoto).where(*conditions))
    rows = (await db.scalars(
        select(PlacePhoto).where(*conditions).order_by(order)
        .limit(page_size).offset((page - 1) * page_size)
    )).all()
    return PlacePhotoAdminList(photos=[_admin(p) for p in rows], total=total or 0,
                               page=page, page_size=page_size)


@admin_router.patch("/{photo_id}", response_model=PlacePhotoAdmin)
async def admin_review_place_photo(
    photo_id: uuid.UUID,
    data: PlacePhotoAdminUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Approve a photo (it shows for the place at once) or reject it (its file
    is deleted). An approved photo can also be rejected later to take it down."""
    if data.status not in (place_photos.APPROVED, place_photos.REJECTED):
        raise HTTPException(status_code=400, detail="Approve or reject.")
    photo = await db.get(PlacePhoto, photo_id)
    if photo is None:
        raise HTTPException(status_code=404, detail="Photo not found")
    if photo.status == place_photos.REJECTED:
        raise HTTPException(status_code=409, detail="A rejected photo is deleted and cannot be approved.")
    photo.status = data.status
    photo.reviewed_at = datetime.now(timezone.utc)
    if data.status == place_photos.REJECTED:
        photo.reject_reason = (data.reason or "").strip() or None
        place_photos.delete_file(photo.url)
        photo.url = None
    await db.commit()
    await db.refresh(photo)
    if photo.status == place_photos.APPROVED:
        place_photos.note_approved()
    return _admin(photo)
