from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.review import Review
from app.repositories.review_repository import ReviewRepository
from app.schemas.review import ReviewCreate, ReviewResponse, AttractionRatingSummary
import uuid

from app.models.attraction import Attraction
from sqlalchemy import select

router = APIRouter(prefix="/reviews", tags=["reviews"])

@router.get("/attraction/{attraction_id}", response_model=List[ReviewResponse])
async def get_attraction_reviews(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db)
):
    repo = ReviewRepository(db)
    reviews = await repo.get_by_attraction(attraction_id)
    
    # Map to include user display name (simplification for now)
    responses = []
    for r in reviews:
        resp = ReviewResponse.model_validate(r)
        # Note: In production use joined loads
        responses.append(resp)
    return responses

@router.get("/attraction/{attraction_id}/summary", response_model=AttractionRatingSummary)
async def get_attraction_summary(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db)
):
    repo = ReviewRepository(db)
    avg, count = await repo.get_rating_summary(attraction_id)
    return AttractionRatingSummary(average_rating=avg, total_reviews=count)

@router.post("/", response_model=ReviewResponse, status_code=status.HTTP_201_CREATED)
async def create_review(
    data: ReviewCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # 1. Validate rating bounds
    if data.rating < 1.0 or data.rating > 5.0:
        raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")

    # 2. Verify attraction exists
    stmt_attr = select(Attraction).where(Attraction.id == data.attraction_id)
    res_attr = await db.execute(stmt_attr)
    attraction = res_attr.scalar_one_or_none()
    if not attraction:
        raise HTTPException(status_code=404, detail="Attraction not found")

    # 3. Check for existing review from this user (prevent duplicate spam)
    stmt_existing = select(Review).where(
        Review.attraction_id == data.attraction_id,
        Review.user_id == current_user.id
    )
    res_existing = await db.execute(stmt_existing)
    existing_review = res_existing.scalar_one_or_none()

    repo = ReviewRepository(db)
    if existing_review:
        existing_review.rating = data.rating
        existing_review.comment = data.comment
        return await repo.update(existing_review)

    review = Review(
        user_id=current_user.id,
        attraction_id=data.attraction_id,
        rating=data.rating,
        comment=data.comment
    )
    return await repo.create(review)
