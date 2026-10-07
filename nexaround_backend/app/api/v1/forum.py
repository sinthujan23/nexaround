import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user, get_current_user_optional
from app.models.user import User
from app.schemas.forum import (
    ForumCategoryResponse,
    ForumTopicCreate,
    ForumTopicResponse,
    ForumTopicDetailResponse,
    ForumPostCreate,
    ForumPostResponse,
    ForumHomeResponse,
)
from app.services.forum_service import ForumService

router = APIRouter(prefix="/forums", tags=["forums"])


@router.get("/home", response_model=ForumHomeResponse)
async def get_forum_home(
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Fetch TripAdvisor-style Forum Home data: Top destinations, regions, topics, and trending questions."""
    return await ForumService.get_forum_home(
        db, current_user_id=current_user.id if current_user else None
    )


@router.get("/categories", response_model=List[ForumCategoryResponse])
async def get_categories(
    category_type: Optional[str] = Query(None, description="region, destination, or topic"),
    parent_id: Optional[uuid.UUID] = Query(None, description="Filter subcategories by parent region"),
    db: AsyncSession = Depends(get_db),
):
    """List forum categories or destination subcategories."""
    return await ForumService.get_categories(db, category_type=category_type, parent_id=parent_id)


@router.get("/categories/{id_or_slug}", response_model=ForumCategoryResponse)
async def get_category(
    id_or_slug: str,
    db: AsyncSession = Depends(get_db),
):
    """Get category or destination details."""
    cat = await ForumService.get_category(db, id_or_slug)
    if not cat:
        raise HTTPException(status_code=404, detail="Forum category not found")
    return ForumCategoryResponse.model_validate(cat)


@router.get("/topics", response_model=List[ForumTopicResponse])
async def get_topics(
    category_id: Optional[uuid.UUID] = None,
    category_slug: Optional[str] = None,
    query: Optional[str] = None,
    sort_by: str = Query("recent", regex="^(recent|trending|unanswered)$"),
    tag: Optional[str] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Search and filter forum discussions."""
    return await ForumService.get_topics(
        db,
        category_id=category_id,
        category_slug=category_slug,
        query=query,
        sort_by=sort_by,
        tag=tag,
        skip=skip,
        limit=limit,
        current_user_id=current_user.id if current_user else None,
    )


@router.post("/topics", response_model=ForumTopicResponse, status_code=status.HTTP_201_CREATED)
async def create_topic(
    data: ForumTopicCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Ask a question / Start a discussion thread."""
    try:
        return await ForumService.create_topic(db, current_user, data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/topics/{topic_id}", response_model=ForumTopicDetailResponse)
async def get_topic_detail(
    topic_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Get full discussion thread and replies stream."""
    topic = await ForumService.get_topic_detail(
        db, topic_id, current_user_id=current_user.id if current_user else None
    )
    if not topic:
        raise HTTPException(status_code=404, detail="Forum topic not found")
    return topic


@router.post(
    "/topics/{topic_id}/replies",
    response_model=ForumPostResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_reply(
    topic_id: uuid.UUID,
    data: ForumPostCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Post an answer or reply to a topic."""
    try:
        return await ForumService.create_post(db, current_user, topic_id, data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/topics/{topic_id}/like")
async def toggle_topic_like(
    topic_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Toggle helpful upvote on a topic."""
    try:
        return await ForumService.toggle_topic_like(db, current_user, topic_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/posts/{post_id}/like")
async def toggle_post_like(
    post_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Toggle helpful upvote on a reply."""
    try:
        return await ForumService.toggle_post_like(db, current_user, post_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/topics/{topic_id}/bookmark")
async def toggle_bookmark(
    topic_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Save or unsave topic to bookmarks."""
    return await ForumService.toggle_bookmark(db, current_user, topic_id)


@router.post("/topics/{topic_id}/best-answer/{post_id}")
async def set_best_answer(
    topic_id: uuid.UUID,
    post_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark an answer as the best / verified answer."""
    try:
        return await ForumService.set_best_answer(db, current_user, topic_id, post_id)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
