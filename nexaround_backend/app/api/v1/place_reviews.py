"""Travellers' own ratings and reviews of map places (TL, 2026-11-18).

Any place the app shows can be rated: Google places, free-map-data places and
our own. One review per traveller per place; a second send edits the first.
Published at once; an admin can hide it from Admin › Place reviews.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_current_user_optional
from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.models.attraction import Attraction
from app.models.place_review import PlaceReview
from app.models.user import User
from app.schemas.place_review import (
    PlaceReviewAdmin, PlaceReviewAdminList, PlaceReviewAdminUpdate, PlaceReviewIn,
    PlaceReviewList, PlaceReviewMine, PlaceReviewPublic, PlaceReviewSummary, PointsChange,
)
from app.services import experience_reviews, explorer_points, place_reviews
from app.utils.geo_utils import get_lat_lng

router = APIRouter(prefix="/places", tags=["Place reviews"])
admin_router = APIRouter(prefix="/admin/place-reviews", tags=["Admin: place reviews"])


def _mine(r: PlaceReview) -> PlaceReviewMine:
    return PlaceReviewMine(
        id=r.id, rating=r.rating, comment=r.comment, status=r.status,
        created_at=r.created_at, edited_at=r.edited_at,
    )


def _public(r: PlaceReview, level: Optional[int] = None) -> PlaceReviewPublic:
    return PlaceReviewPublic(
        id=r.id, reviewer_name=r.reviewer_name, rating=r.rating, comment=r.comment,
        created_at=r.created_at, edited=r.edited_at is not None,
        reviewer_level=level,
        reviewer_level_name=explorer_points.level_name(level) if level else None,
    )


def _admin(r: PlaceReview) -> PlaceReviewAdmin:
    return PlaceReviewAdmin(
        id=r.id, place_key=r.place_key, place_name=r.place_name,
        latitude=r.latitude, longitude=r.longitude, user_id=r.user_id,
        reviewer_name=r.reviewer_name, rating=r.rating, comment=r.comment,
        status=r.status, created_at=r.created_at, edited_at=r.edited_at,
        hidden_at=r.hidden_at,
    )


def _check_id(place_id: str) -> None:
    if not place_reviews.valid_place_id(place_id):
        raise HTTPException(status_code=404, detail="Place not found")


@router.get("/{place_id}/reviews", response_model=PlaceReviewList)
async def list_place_reviews(
    place_id: str,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    """A place's published reviews from our travellers, newest first, with
    their average and the five-to-one breakdown."""
    _check_id(place_id)
    _, keys = await place_reviews.canonical_key(db, place_id)
    summary = await place_reviews.breakdown(db, keys)
    rows = (await db.scalars(
        place_reviews.place_reviews_query(keys).limit(limit).offset(offset)
    )).all()
    levels = await explorer_points.levels_for(db, [r.user_id for r in rows])
    return PlaceReviewList(
        summary=PlaceReviewSummary(**summary),
        reviews=[_public(r, levels.get(r.user_id)) for r in rows],
        total=summary["count"], limit=limit, offset=offset,
    )


@router.get("/{place_id}/review/mine", response_model=Optional[PlaceReviewMine])
async def my_place_review(
    place_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The signed-in traveller's own review of this place, or null."""
    _check_id(place_id)
    _, keys = await place_reviews.canonical_key(db, place_id)
    review = await place_reviews.user_review(db, current_user.id, keys)
    return _mine(review) if review is not None else None


@router.put("/{place_id}/review", response_model=PlaceReviewMine)
async def review_place(
    place_id: str,
    data: PlaceReviewIn,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Rate a place, or change the rating already given. Published at once.
    The answer says what it did to the traveller's Explorer Points."""
    _check_id(place_id)
    key, keys = await place_reviews.canonical_key(db, place_id)
    before = (await explorer_points.total_for(db, current_user.id, fresh=True)).total
    now = datetime.now(timezone.utc)
    comment = experience_reviews.clean_comment(data.comment)

    review = await place_reviews.user_review(db, current_user.id, keys)
    if review is not None:
        if review.rating != data.rating or review.comment != comment:
            review.rating = data.rating
            review.comment = comment
            review.edited_at = now
    else:
        midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
        today = await db.scalar(
            select(func.count()).select_from(PlaceReview).where(
                PlaceReview.user_id == current_user.id,
                PlaceReview.created_at >= midnight,
            )
        )
        if (today or 0) >= place_reviews.MAX_NEW_PER_DAY:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="You have rated a lot of places today. Please try again tomorrow.",
            )
        name = data.place_name.strip()
        lat, lng = data.latitude, data.longitude
        # One of our own places: its stored name and position, not the app's copy.
        if place_reviews._is_uuid(place_id):
            row = await db.get(Attraction, uuid.UUID(place_id))
            if row is not None:
                name = row.name or name
                lat, lng = get_lat_lng(row.location)
        review = PlaceReview(
            id=uuid.uuid4(),
            place_key=key,
            user_id=current_user.id,
            reviewer_name=experience_reviews.reviewer_display_name(current_user.display_name),
            place_name=name[:255],
            latitude=lat,
            longitude=lng,
            rating=data.rating,
            comment=comment,
            status=place_reviews.PUBLISHED,
            created_at=now,
        )
        db.add(review)
    try:
        await db.commit()
    except IntegrityError:
        # A second tap that raced the first.
        await db.rollback()
        raise HTTPException(status_code=409, detail="You have already rated this place.")
    await db.refresh(review)
    if review.status == place_reviews.PUBLISHED:
        place_reviews.note_published()
    await explorer_points.bust(current_user.id)
    after = (await explorer_points.total_for(db, current_user.id, fresh=True)).total
    background_tasks.add_task(explorer_points.notify_level_up, current_user.id, before, after)
    out = _mine(review)
    out.points = PointsChange(**explorer_points.change(before, after))
    return out


@router.delete("/{place_id}/review", status_code=status.HTTP_204_NO_CONTENT)
async def delete_place_review(
    place_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete the signed-in traveller's own review of this place."""
    _check_id(place_id)
    _, keys = await place_reviews.canonical_key(db, place_id)
    review = await place_reviews.user_review(db, current_user.id, keys)
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")
    await db.delete(review)
    await db.commit()
    await explorer_points.bust(current_user.id)
    return None


# ── Admin › Place reviews ───────────────────────────────────────────────────

@admin_router.get("", response_model=PlaceReviewAdminList)
async def admin_list_place_reviews(
    status_filter: Optional[str] = Query(None, alias="status"),
    rating: Optional[int] = Query(None, ge=1, le=5),
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Every place review, hidden ones included, newest first."""
    if status_filter and status_filter not in place_reviews.STATUSES:
        raise HTTPException(status_code=400, detail="Unknown status.")
    conditions = []
    if status_filter:
        conditions.append(PlaceReview.status == status_filter)
    if rating:
        conditions.append(PlaceReview.rating == rating)
    if q and q.strip():
        conditions.append(place_reviews.admin_search_clause(q))
    total = await db.scalar(
        select(func.count()).select_from(PlaceReview).where(*conditions)
    )
    rows = (await db.scalars(
        select(PlaceReview).where(*conditions)
        .order_by(PlaceReview.created_at.desc())
        .limit(page_size).offset((page - 1) * page_size)
    )).all()
    return PlaceReviewAdminList(
        reviews=[_admin(r) for r in rows], total=total or 0,
        page=page, page_size=page_size,
    )


@admin_router.patch("/{review_id}", response_model=PlaceReviewAdmin)
async def admin_update_place_review(
    review_id: uuid.UUID,
    data: PlaceReviewAdminUpdate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Hide or restore a review. A hidden review leaves every average and list
    at once, and comes back the same way."""
    if data.status not in place_reviews.STATUSES:
        raise HTTPException(status_code=400, detail="Unknown status.")
    review = await db.get(PlaceReview, review_id)
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")
    changed = data.status != review.status
    before = (await explorer_points.total_for(db, review.user_id, fresh=True)).total if changed else 0
    if changed:
        review.status = data.status
        review.hidden_at = (
            datetime.now(timezone.utc) if data.status == place_reviews.HIDDEN else None
        )
    await db.commit()
    await db.refresh(review)
    if changed:
        # Hidden: its points go; restored: they come back.
        background_tasks.add_task(explorer_points.after_change, review.user_id, before)
    return _admin(review)
