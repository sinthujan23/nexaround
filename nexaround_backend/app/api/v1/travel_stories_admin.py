"""Official travel stories: the ones the team posts as TravelByte.

They live in `travel_stories` with `is_official` set, owned by the system
account in `app/services/official_stories.py`, so the app's feed, likes and
comments treat them like any other story. Hiding one is `is_public = False`,
which the feed already filters out. Photos go through the experiences upload
endpoint and the place through its place search, as the panel's other forms
do. Every write here is recorded by the audit middleware.
"""
import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.models.travel_story import TravelStory
from app.schemas.travel_story import OfficialStoryAdminOut, OfficialStoryIn
from app.services.official_stories import ensure_official_user, place_label

router = APIRouter(prefix="/admin/travel-stories", tags=["Admin Travel Stories"])


def _out(story: TravelStory) -> OfficialStoryAdminOut:
    return OfficialStoryAdminOut(
        id=story.id,
        title=story.title or "",
        description=story.description,
        article_md=story.article_md or "",
        location_name=story.location_name,
        country=story.country or "",
        latitude=story.latitude,
        longitude=story.longitude,
        category=story.category,
        region_label=story.region_label or "",
        image_urls=story.image_urls or [story.image_url],
        is_public=story.is_public,
        likes_count=len(story.likes),
        comments_count=len(story.comments),
        created_at=story.created_at,
    )


def _apply(story: TravelStory, data: OfficialStoryIn) -> None:
    urls = [u.strip() for u in data.image_urls if u.strip()]
    if not urls:
        raise HTTPException(status_code=422, detail="Add at least one photo.")
    if any(len(u) > 500 for u in urls):
        raise HTTPException(status_code=422, detail="A photo address is too long.")
    story.title = data.title.strip()
    story.description = data.description.strip()
    story.article_md = data.article_md.strip() or None
    story.location_name = data.location_name.strip()
    story.country = data.country.strip()
    story.latitude = data.latitude
    story.longitude = data.longitude
    story.region_label = data.region_label.strip() or None
    story.category = place_label(story.country, story.region_label)
    story.image_urls = urls
    story.image_url = urls[0]
    story.is_public = data.is_public


async def _get_official(db: AsyncSession, story_id: uuid.UUID) -> TravelStory:
    # populate_existing: a story this request just created is already in the
    # session with its likes/comments never loaded, and touching them then
    # would be a lazy load, which async sessions refuse.
    story = (
        await db.execute(
            select(TravelStory)
            .where(TravelStory.id == story_id, TravelStory.is_official.is_(True))
            .execution_options(populate_existing=True)
        )
    ).scalar_one_or_none()
    if not story:
        raise HTTPException(status_code=404, detail="Official story not found")
    return story


@router.get("", response_model=List[OfficialStoryAdminOut])
async def list_official_stories(
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Every official story, hidden ones included, newest first."""
    stories = (
        await db.execute(
            select(TravelStory)
            .where(TravelStory.is_official.is_(True))
            .order_by(TravelStory.created_at.desc())
        )
    ).scalars().all()
    return [_out(s) for s in stories]


@router.post("", response_model=OfficialStoryAdminOut, status_code=status.HTTP_201_CREATED)
async def create_official_story(
    data: OfficialStoryIn,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    owner_id = await ensure_official_user(db)
    story = TravelStory(id=uuid.uuid4(), user_id=owner_id, is_official=True, is_journal=False)
    _apply(story, data)
    db.add(story)
    await db.commit()
    return _out(await _get_official(db, story.id))


@router.put("/{story_id}", response_model=OfficialStoryAdminOut)
async def update_official_story(
    story_id: uuid.UUID,
    data: OfficialStoryIn,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    story = await _get_official(db, story_id)
    _apply(story, data)
    await db.commit()
    return _out(await _get_official(db, story_id))


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_official_story(
    story_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Delete for good, with its likes and comments. Hiding keeps them."""
    story = await _get_official(db, story_id)
    await db.delete(story)
    await db.commit()
    return None
