"""Photos travellers send for places (TL, 2026-11-18).

First offered only on a place showing its category icon; since 2026-11-20
(Explorer Points) any place can take one photo per traveller, and the place
page lists them. A photo waits for an admin in Admin › Media; once approved it
shows for everyone and earns its sender points (more for the first photo of a
place that had none). See services/place_photos.py, services/explorer_points.py.
"""
import asyncio
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, UploadFile, status,
)
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.models.attraction import Attraction
from app.models.place_photo import PlacePhoto
from app.models.user import User
from app.services import experience_reviews, explorer_points, place_photos, place_reviews
from app.utils.geo_utils import get_lat_lng

router = APIRouter(prefix="/places", tags=["Place photos"])
admin_router = APIRouter(prefix="/admin/place-photos", tags=["Admin: place photos"])


class MyPlacePhoto(BaseModel):
    id: uuid.UUID
    status: str
    url: Optional[str] = None
    reject_reason: Optional[str] = None
    created_at: datetime
    # First photo of a place that had none: worth the Trailblazer bonus.
    trailblazer: bool = False
    # What it earns once approved (already earned when approved).
    points: int = 0


class PlacePhotoPublic(BaseModel):
    """A traveller photo on the place page: first name and last initial only."""
    id: uuid.UUID
    url: str
    card_url: str
    width: Optional[int] = None
    height: Optional[int] = None
    uploader_name: str
    uploader_level: Optional[int] = None
    uploader_level_name: Optional[str] = None
    created_at: datetime


class PlacePhotoList(BaseModel):
    photos: list[PlacePhotoPublic]
    total: int


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
    trailblazer: bool = False


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
                        reject_reason=p.reject_reason, created_at=p.created_at,
                        trailblazer=bool(p.trailblazer),
                        points=explorer_points.photo_points(bool(p.trailblazer)))


def _admin(p: PlacePhoto) -> PlacePhotoAdmin:
    return PlacePhotoAdmin(
        id=p.id, place_key=p.place_key, place_name=p.place_name,
        latitude=p.latitude, longitude=p.longitude, user_id=p.user_id,
        uploader_name=p.uploader_name, url=p.url, width=p.width, height=p.height,
        size_bytes=p.size_bytes, status=p.status, reject_reason=p.reject_reason,
        created_at=p.created_at, reviewed_at=p.reviewed_at,
        trailblazer=bool(p.trailblazer),
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
    """Send a photo for a place: one per traveller per place (a rejected one
    can be replaced). It shows once an admin approves it."""
    _check_id(place_id)
    if not consent:
        raise HTTPException(
            status_code=400,
            detail="Please confirm you took this photo and allow nexAround to show it.",
        )
    key, keys = await place_reviews.canonical_key(db, place_id)

    own = await db.scalar(
        select(PlacePhoto.status).where(
            PlacePhoto.place_key.in_(keys), PlacePhoto.user_id == current_user.id,
            PlacePhoto.status.in_((place_photos.PENDING, place_photos.APPROVED)),
        ).order_by(PlacePhoto.created_at.desc()).limit(1)
    )
    if own == place_photos.PENDING:
        raise HTTPException(
            status_code=409,
            detail="Your photo for this place is already waiting for our team.",
        )
    if own == place_photos.APPROVED:
        raise HTTPException(
            status_code=409, detail="You have already added a photo of this place.",
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
    # Nothing shows for this place yet: the Trailblazer bonus, if it is still
    # the first traveller photo when an admin approves it.
    trailblazer = not await place_photos.place_has_photo(db, keys)
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
        status=place_photos.PENDING, created_at=now, trailblazer=trailblazer,
    )
    db.add(photo)
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        place_photos.delete_file(url)
        raise
    await db.refresh(photo)
    await explorer_points.bust(current_user.id)
    return _mine(photo)


@router.get("/{place_id}/photos", response_model=PlacePhotoList)
async def list_place_photos(
    place_id: str,
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """A place's approved traveller photos, newest first, with each sender's
    Explorer level. Public."""
    _check_id(place_id)
    _, keys = await place_reviews.canonical_key(db, place_id)
    rows = await place_photos.approved_photos(db, keys, limit=limit)
    levels = await explorer_points.levels_for(db, [p.user_id for p in rows])
    google_on = await place_photos._google_on()
    photos = []
    for p in rows:
        lv = levels.get(p.user_id)
        photos.append(PlacePhotoPublic(
            id=p.id, url=p.url,
            card_url=place_photos.sized_url(p.url, card=True, google_on=google_on),
            width=p.width, height=p.height, uploader_name=p.uploader_name,
            uploader_level=lv, uploader_level_name=explorer_points.level_name(lv) if lv else None,
            created_at=p.created_at,
        ))
    return PlacePhotoList(photos=photos, total=len(photos))


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
    background_tasks: BackgroundTasks,
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
    newly_approved = data.status == place_photos.APPROVED and photo.status != place_photos.APPROVED
    before = (await explorer_points.total_for(db, photo.user_id, fresh=True)).total
    if newly_approved and photo.trailblazer:
        # Another traveller's photo of this place went live first.
        cand = await place_reviews._candidate_keys(db, [photo.place_key])
        keys = cand.get(photo.place_key) or [photo.place_key]
        first = not await db.scalar(
            select(PlacePhoto.id).where(
                PlacePhoto.place_key.in_(keys), PlacePhoto.status == place_photos.APPROVED,
                PlacePhoto.id != photo.id,
            ).limit(1)
        )
        photo.trailblazer = first
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
    if newly_approved:
        background_tasks.add_task(
            explorer_points.after_photo_approved, photo.user_id, photo.place_name,
            explorer_points.photo_points(bool(photo.trailblazer)), before,
        )
    else:
        background_tasks.add_task(explorer_points.after_change, photo.user_id, before)
    return _admin(photo)
