import os
import uuid
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy import select, func, or_
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.travel_story import TravelStory, TravelStoryLike, TravelStoryComment
from app.schemas.travel_story import (
    TravelStoryCreate,
    TravelStoryResponse,
    TravelStoryCommentCreate,
    TravelStoryCommentResponse
)

router = APIRouter(prefix="/travel-stories", tags=["travel-stories"])


@router.get("", response_model=List[TravelStoryResponse])
async def get_travel_stories(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get all travel stories, sorted newest first."""
    stmt = select(TravelStory).where(
        or_(TravelStory.is_public == True, TravelStory.user_id == current_user.id)
    ).order_by(TravelStory.created_at.desc())
    res = await db.execute(stmt)
    stories = res.scalars().all()
    
    response_list = []
    for s in stories:
        # Check if logged-in user liked this story
        is_liked = any(like.user_id == current_user.id for like in s.likes)
        
        comments_list = []
        for c in s.comments:
            comments_list.append(
                TravelStoryCommentResponse(
                    id=c.id,
                    story_id=c.story_id,
                    user_id=c.user_id,
                    user_display_name=c.user.display_name,
                    user_avatar_url=c.user.avatar_url,
                    comment_text=c.comment_text,
                    created_at=c.created_at
                )
            )
            
        response_list.append(
            TravelStoryResponse(
                id=s.id,
                user_id=s.user_id,
                user_display_name=s.user.display_name,
                user_avatar_url=s.user.avatar_url,
                location_name=s.location_name,
                category=s.category,
                description=s.description,
                image_url=s.image_url,
                is_public=s.is_public,
                likes_count=len(s.likes),
                is_liked=is_liked,
                created_at=s.created_at,
                comments=comments_list
            )
        )
        
    return response_list


@router.post("", response_model=TravelStoryResponse, status_code=status.HTTP_201_CREATED)
async def create_travel_story(
    data: TravelStoryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Post a new travel story."""
    story = TravelStory(
        user_id=current_user.id,
        location_name=data.location_name,
        category=data.category,
        description=data.description,
        image_url=data.image_url,
        is_public=data.is_public
    )
    db.add(story)
    await db.flush()  # Populate id and created_at
    await db.commit()
    
    # Refresh/load user model relationship details
    stmt = select(TravelStory).where(TravelStory.id == story.id)
    res = await db.execute(stmt)
    refreshed_story = res.scalar_one()

    return TravelStoryResponse(
        id=refreshed_story.id,
        user_id=refreshed_story.user_id,
        user_display_name=current_user.display_name,
        user_avatar_url=current_user.avatar_url,
        location_name=refreshed_story.location_name,
        category=refreshed_story.category,
        description=refreshed_story.description,
        image_url=refreshed_story.image_url,
        is_public=refreshed_story.is_public,
        likes_count=0,
        is_liked=False,
        created_at=refreshed_story.created_at,
        comments=[]
    )


@router.post("/{story_id}/like")
async def toggle_like(
    story_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Like or unlike a travel story."""
    # Check if story exists
    stmt_story = select(TravelStory).where(TravelStory.id == story_id)
    res_story = await db.execute(stmt_story)
    story = res_story.scalar_one_or_none()
    if not story:
        raise HTTPException(status_code=404, detail="Travel story not found")

    # Check if like exists
    stmt_like = select(TravelStoryLike).where(
        TravelStoryLike.story_id == story_id,
        TravelStoryLike.user_id == current_user.id
    )
    res_like = await db.execute(stmt_like)
    like = res_like.scalar_one_or_none()
    
    if like:
        await db.delete(like)
        liked = False
    else:
        new_like = TravelStoryLike(story_id=story_id, user_id=current_user.id)
        db.add(new_like)
        liked = True
        
    await db.commit()
    
    # Fetch final count
    stmt_count = select(func.count()).select_from(TravelStoryLike).where(TravelStoryLike.story_id == story_id)
    count_res = await db.execute(stmt_count)
    count = count_res.scalar() or 0
    
    return {"liked": liked, "likes_count": count}


@router.post("/{story_id}/comment", response_model=TravelStoryCommentResponse)
async def create_comment(
    story_id: uuid.UUID,
    data: TravelStoryCommentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Post a comment on a travel story."""
    # Check if story exists
    stmt_story = select(TravelStory).where(TravelStory.id == story_id)
    res_story = await db.execute(stmt_story)
    story = res_story.scalar_one_or_none()
    if not story:
        raise HTTPException(status_code=404, detail="Travel story not found")

    comment = TravelStoryComment(
        story_id=story_id,
        user_id=current_user.id,
        comment_text=data.comment_text
    )
    db.add(comment)
    await db.flush()
    await db.commit()

    return TravelStoryCommentResponse(
        id=comment.id,
        story_id=comment.story_id,
        user_id=comment.user_id,
        user_display_name=current_user.display_name,
        user_avatar_url=current_user.avatar_url,
        comment_text=comment.comment_text,
        created_at=comment.created_at
    )


@router.post("/upload")
async def upload_story_image(
    file: UploadFile = File(...)
):
    """Upload an image for a travel story."""
    upload_dir = "app/static/uploads"
    os.makedirs(upload_dir, exist_ok=True)
    
    file_ext = os.path.splitext(file.filename)[1] if file.filename else ".jpg"
    unique_filename = f"{uuid.uuid4()}{file_ext}"
    file_path = os.path.join(upload_dir, unique_filename)
    
    content = await file.read()
    with open(file_path, "wb") as buffer:
        buffer.write(content)
        
    return {"url": f"/static/uploads/{unique_filename}"}


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_travel_story(
    story_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Delete a travel story. Only the owner can delete their story."""
    stmt = select(TravelStory).where(TravelStory.id == story_id)
    res = await db.execute(stmt)
    story = res.scalar_one_or_none()
    if not story:
        raise HTTPException(status_code=404, detail="Travel story not found")
    
    # Only owner can delete
    if story.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to delete this story")
    
    await db.delete(story)
    await db.commit()
    return None

