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
        TravelStory.is_journal == False,
        or_(TravelStory.is_public == True, TravelStory.user_id == current_user.id)
    ).order_by(TravelStory.created_at.desc())
    res = await db.execute(stmt)
    stories = res.scalars().all()
    
    response_list = []
    for s in stories:
        is_liked = any(like.user_id == current_user.id for like in s.likes)
        
        comments_list = []
        for c in s.comments:
            comments_list.append(
                TravelStoryCommentResponse(
                    id=c.id, story_id=c.story_id, user_id=c.user_id,
                    user_display_name=c.user.display_name, user_avatar_url=c.user.avatar_url,
                    comment_text=c.comment_text, image_index=c.image_index, created_at=c.created_at
                )
            )
            
        response_list.append(
            TravelStoryResponse(
                id=s.id, user_id=s.user_id, user_display_name=s.user.display_name,
                user_avatar_url=s.user.avatar_url, location_name=s.location_name,
                category=s.category, description=s.description, image_url=s.image_url,
                image_urls=s.image_urls, latitude=s.latitude, longitude=s.longitude,
                is_public=s.is_public, likes_count=len(s.likes), is_liked=is_liked,
                is_journal=s.is_journal, journal_date=s.journal_date,
                total_spend=s.total_spend, spend_currency=s.spend_currency,
                cloud_provider=s.cloud_provider, cloud_folder_url=s.cloud_folder_url,
                created_at=s.created_at, comments=comments_list
            )
        )
        
    return response_list

@router.get("/journal", response_model=List[TravelStoryResponse])
async def get_travel_journal(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get all private journal entries for the current user, ordered by journal_date."""
    stmt = select(TravelStory).where(
        TravelStory.user_id == current_user.id,
        TravelStory.is_journal == True
    ).order_by(TravelStory.journal_date.desc().nulls_last(), TravelStory.created_at.desc())
    
    res = await db.execute(stmt)
    stories = res.scalars().all()
    
    response_list = []
    for s in stories:
        comments_list = []
        for c in s.comments:
            comments_list.append(
                TravelStoryCommentResponse(
                    id=c.id, story_id=c.story_id, user_id=c.user_id,
                    user_display_name=c.user.display_name, user_avatar_url=c.user.avatar_url,
                    comment_text=c.comment_text, image_index=c.image_index, created_at=c.created_at
                )
            )
            
        response_list.append(
            TravelStoryResponse(
                id=s.id, user_id=s.user_id, user_display_name=s.user.display_name,
                user_avatar_url=s.user.avatar_url, location_name=s.location_name,
                category=s.category, description=s.description, image_url=s.image_url,
                image_urls=s.image_urls, latitude=s.latitude, longitude=s.longitude,
                is_public=s.is_public, likes_count=len(s.likes), is_liked=False,
                is_journal=s.is_journal, journal_date=s.journal_date,
                total_spend=s.total_spend, spend_currency=s.spend_currency,
                cloud_provider=s.cloud_provider, cloud_folder_url=s.cloud_folder_url,
                created_at=s.created_at, comments=comments_list
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
        image_urls=data.image_urls,
        latitude=data.latitude,
        longitude=data.longitude,
        is_public=data.is_public,
        is_journal=data.is_journal,
        journal_date=data.journal_date,
        total_spend=data.total_spend,
        spend_currency=data.spend_currency,
        cloud_provider=data.cloud_provider,
        cloud_folder_url=data.cloud_folder_url
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
        image_urls=refreshed_story.image_urls,
        latitude=refreshed_story.latitude,
        longitude=refreshed_story.longitude,
        is_public=refreshed_story.is_public,
        is_journal=refreshed_story.is_journal,
        journal_date=refreshed_story.journal_date,
        total_spend=refreshed_story.total_spend,
        spend_currency=refreshed_story.spend_currency,
        cloud_provider=refreshed_story.cloud_provider,
        cloud_folder_url=refreshed_story.cloud_folder_url,
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
        comment_text=data.comment_text,
        image_index=data.image_index
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
        image_index=comment.image_index,
        created_at=comment.created_at
    )


@router.post("/upload")
async def upload_story_images(
    files: List[UploadFile] = File(...)
):
    """Upload multiple images for a travel story."""
    upload_dir = "app/static/uploads"
    os.makedirs(upload_dir, exist_ok=True)
    
    urls = []
    for file in files:
        file_ext = os.path.splitext(file.filename)[1] if file.filename else ".jpg"
        unique_filename = f"{uuid.uuid4()}{file_ext}"
        file_path = os.path.join(upload_dir, unique_filename)
        
        content = await file.read()
        with open(file_path, "wb") as buffer:
            buffer.write(content)
            
        urls.append(f"/static/uploads/{unique_filename}")
        
    return {"urls": urls}


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

@router.put("/{story_id}", response_model=TravelStoryResponse)
async def update_travel_story(
    story_id: uuid.UUID,
    data: TravelStoryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Update a travel story."""
    stmt = select(TravelStory).where(TravelStory.id == story_id)
    res = await db.execute(stmt)
    story = res.scalar_one_or_none()
    
    if not story:
        raise HTTPException(status_code=404, detail="Travel story not found")
        
    if story.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to edit this story")
        
    # Update fields
    story.location_name = data.location_name
    story.category = data.category
    story.description = data.description
    story.image_url = data.image_url
    story.image_urls = data.image_urls
    story.latitude = data.latitude
    story.longitude = data.longitude
    story.is_public = data.is_public
    
    await db.commit()
    await db.refresh(story)
    
    # Needs to match response model shape exactly
    # Check if logged-in user liked this story
    is_liked = any(like.user_id == current_user.id for like in story.likes)
    
    comments_list = []
    for c in story.comments:
        comments_list.append(
            TravelStoryCommentResponse(
                id=c.id,
                story_id=c.story_id,
                user_id=c.user_id,
                user_display_name=c.user.display_name,
                user_avatar_url=c.user.avatar_url,
                comment_text=c.comment_text,
                image_index=c.image_index,
                created_at=c.created_at
            )
        )
        
    return TravelStoryResponse(
        id=story.id,
        user_id=story.user_id,
        user_display_name=story.user.display_name,
        user_avatar_url=story.user.avatar_url,
        location_name=story.location_name,
        category=story.category,
        description=story.description,
        image_url=story.image_url,
        image_urls=story.image_urls,
        latitude=story.latitude,
        longitude=story.longitude,
        is_public=story.is_public,
        likes_count=len(story.likes),
        is_liked=is_liked,
        created_at=story.created_at,
        comments=comments_list
    )
