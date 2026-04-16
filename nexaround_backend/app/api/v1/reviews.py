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
    repo = ReviewRepository(db)
    review = Review(
        user_id=current_user.id,
        attraction_id=data.attraction_id,
        rating=data.rating,
        comment=data.comment
    )
    return await repo.create(review)
