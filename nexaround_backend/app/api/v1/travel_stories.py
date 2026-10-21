import os
import io
import uuid
from typing import List, Optional
from PIL import Image
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Query

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
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
from app.utils.place_match import haversine_m
from app.services import image_preview, story_location, user_country
from app.services.trip_cost_floor import country_for

router = APIRouter(prefix="/travel-stories", tags=["travel-stories"])

# "Near you" groups stories by distance - same town, day trip, region, farther -
# and shows the newest first inside each group, so a story posted yesterday
# 3 km away is not stuck behind a year-old one 1 km away. Nothing is filtered
# out: with few stories, a radius would leave most travellers an empty row.
NEARBY_BANDS_M = (25_000, 150_000, 1_000_000)


def _distance_m(story, lat: float, lng: float) -> Optional[float]:
    """Metres from (lat, lng) to the story, or None when it has no position.

    (0, 0) counts as no position: it is the placeholder an unset location
    becomes, not a story posted in the Gulf of Guinea.
    """
    if story.latitude is None or story.longitude is None:
        return None
    if story.latitude == 0 and story.longitude == 0:
        return None
    return haversine_m(lat, lng, story.latitude, story.longitude)


def _order_nearby(pairs: list) -> list:
    """Sort (story, distance) pairs by distance band, then newest first.

    Stories with no position go after every band.
    """
    def band(distance: Optional[float]) -> int:
        if distance is None:
            return len(NEARBY_BANDS_M) + 1
        for i, bound in enumerate(NEARBY_BANDS_M):
            if distance <= bound:
                return i
        return len(NEARBY_BANDS_M)

    return sorted(
        pairs,
        key=lambda p: (band(p[1]), -(p[0].created_at.timestamp() if p[0].created_at else 0)),
    )


# TravelBytes - the stories the team posts - share one card at the front of
# the row, whatever the filter. App builds that draw that card ask for the set
# with `official_stack`; older builds draw each story as a card of its own, so
# they get only the first, and a growing number of TravelBytes can never push
# travellers' stories out of the row.
OFFICIAL_IN_STACK = 10
OFFICIAL_IN_OLD_FEED = 1


def _created_ts(story) -> float:
    return story.created_at.timestamp() if story.created_at else 0


def _order_official(pairs: list, first_country: Optional[str], limit: Optional[int]) -> list:
    """TravelBytes in the order the app shows them, at most `limit` (None: all).

    First the ones about `first_country` (ISO code: the country the traveller
    picked, or else the one they are in), nearest first; then every other one,
    newest first.
    """
    def is_first(story) -> bool:
        return bool(first_country) and country_for(story.country or "") == first_country

    first = sorted(
        (p for p in pairs if is_first(p[0])),
        key=lambda p: (p[1] is None, p[1] or 0, -_created_ts(p[0])),
    )
    rest = sorted((p for p in pairs if not is_first(p[0])), key=lambda p: -_created_ts(p[0]))
    return (first + rest)[:limit]


def _photo_urls(story) -> list[str]:
    """The story's photos as the app shows them: `image_urls`, else the one."""
    return story.image_urls or ([story.image_url] if story.image_url else [])


async def _previews(stories) -> dict[str, str]:
    """Blur previews for every photo of `stories` (see image_preview)."""
    return await image_preview.previews_for(u for s in stories for u in _photo_urls(s))


def _own_previews(story, previews: dict[str, str]) -> dict[str, str]:
    return {u: previews[u] for u in _photo_urls(story) if u in previews}


def _feed_response(s, viewer_id, distance: Optional[float], previews: dict[str, str]) -> TravelStoryResponse:
    """One story as the feed sends it, `is_liked` from `viewer_id`'s side."""
    comments_list = [
        TravelStoryCommentResponse(
            id=c.id, story_id=c.story_id, user_id=c.user_id,
            user_display_name=c.user.display_name, user_avatar_url=c.user.avatar_url,
            comment_text=c.comment_text, image_index=c.image_index, created_at=c.created_at
        )
        for c in s.comments
    ]
    return TravelStoryResponse(
        id=s.id, user_id=s.user_id, user_display_name=s.user.display_name,
        user_avatar_url=s.user.avatar_url, location_name=s.location_name,
        category=s.category, description=s.description, image_url=s.image_url,
        image_urls=s.image_urls, latitude=s.latitude, longitude=s.longitude,
        is_public=s.is_public, likes_count=len(s.likes),
        is_liked=any(like.user_id == viewer_id for like in s.likes),
        is_journal=s.is_journal, journal_date=s.journal_date,
        total_spend=s.total_spend, spend_currency=s.spend_currency,
        cloud_provider=s.cloud_provider, cloud_folder_url=s.cloud_folder_url,
        travel_date=s.travel_date, country=s.country,
        created_at=s.created_at, comments=comments_list,
        distance_m=round(distance) if distance is not None else None,
        is_official=s.is_official, title=s.title, article_md=s.article_md,
        image_previews=_own_previews(s, previews),
    )


@router.get("", response_model=List[TravelStoryResponse])
async def get_travel_stories(
    country: Optional[str] = None,
    lat: Optional[float] = Query(None, ge=-90, le=90),
    lng: Optional[float] = Query(None, ge=-180, le=180),
    official_stack: bool = Query(False),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get travel stories, newest first.

    With `lat` and `lng`, each story carries its `distance_m` from that point,
    and - unless a `country` is picked - the list is ordered "Near you" style
    (see `_order_nearby`). Without them the response is unchanged, so app
    builds that don't send a location keep their newest-first feed.

    TravelBytes lead the list under every filter (see `_order_official`):
    up to OFFICIAL_IN_STACK for app builds that send `official_stack`,
    otherwise one.
    """
    stmt = select(TravelStory).where(
        TravelStory.is_journal == False,
        or_(TravelStory.is_public == True, TravelStory.user_id == current_user.id)
    )
    if country:
        stmt = stmt.where(or_(TravelStory.country == country, TravelStory.is_official == True))
    stmt = stmt.order_by(TravelStory.created_at.desc())
    res = await db.execute(stmt)
    stories = res.scalars().all()

    near = lat is not None and lng is not None
    pairs = [(s, _distance_m(s, lat, lng) if near else None) for s in stories]
    official = [p for p in pairs if p[0].is_official]
    pairs = [p for p in pairs if not p[0].is_official]
    if near and not country:
        pairs = _order_nearby(pairs)
    if official:
        if country:
            first_country = country_for(country)
        elif near:
            first_country = await user_country.country_at(db, lat, lng)
        else:
            first_country = None
        limit = OFFICIAL_IN_STACK if official_stack else OFFICIAL_IN_OLD_FEED
        pairs = _order_official(official, first_country, limit) + pairs

    previews = await _previews(s for s, _ in pairs)
    return [_feed_response(s, current_user.id, distance, previews) for s, distance in pairs]


@router.get("/travelbytes", response_model=List[TravelStoryResponse])
async def get_travelbytes(
    lat: Optional[float] = Query(None, ge=-90, le=90),
    lng: Optional[float] = Query(None, ge=-180, le=180),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Every published TravelByte, for the app's Exclusive page.

    In the same order as the TravelByte card in the feed (`_order_official`,
    by the country at `lat`/`lng`), but all of them: the card carries at most
    OFFICIAL_IN_STACK.
    """
    stmt = (
        select(TravelStory)
        .where(TravelStory.is_official == True, TravelStory.is_public == True)
        .order_by(TravelStory.created_at.desc())
    )
    stories = (await db.execute(stmt)).scalars().all()

    near = lat is not None and lng is not None
    pairs = [(s, _distance_m(s, lat, lng) if near else None) for s in stories]
    first_country = await user_country.country_at(db, lat, lng) if near and pairs else None
    pairs = _order_official(pairs, first_country, None)
    previews = await _previews(s for s, _ in pairs)
    return [_feed_response(s, current_user.id, distance, previews) for s, distance in pairs]

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
                travel_date=s.travel_date, country=s.country,
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
    latitude, longitude = data.latitude, data.longitude
    if data.location_source is None and not data.is_journal:
        fixed = await story_location.corrected_location(
            data.location_name, data.country, latitude, longitude,
        )
        if fixed:
            latitude, longitude = fixed
    story = TravelStory(
        user_id=current_user.id,
        location_name=data.location_name,
        category=data.category,
        description=data.description,
        image_url=data.image_url,
        image_urls=data.image_urls,
        latitude=latitude,
        longitude=longitude,
        is_public=data.is_public,
        is_journal=data.is_journal,
        journal_date=data.journal_date,
        total_spend=data.total_spend,
        spend_currency=data.spend_currency,
        cloud_provider=data.cloud_provider,
        cloud_folder_url=data.cloud_folder_url,
        travel_date=data.travel_date,
        country=data.country
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
        travel_date=refreshed_story.travel_date,
        country=refreshed_story.country,
        likes_count=0,
        is_liked=False,
        created_at=refreshed_story.created_at,
        comments=[],
        image_previews=await _previews([refreshed_story]),
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

    if not story.is_public and story.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: this travel story is private")

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


async def _notify_story_comment(
    db: AsyncSession,
    story_owner_id: uuid.UUID,
    commenter_name: str,
    story_location: str,
    comment_text: str,
    story_id: uuid.UUID
) -> None:
    """Send an in-app notification and FCM push notification to the story owner."""
    try:
        import logging
        from app.models.notification import Notification
        from app.services import fcm_service

        snippet = comment_text[:100] + ("..." if len(comment_text) > 100 else "")
        loc_str = f" in {story_location}" if story_location else ""

        # 1. Create in-app notification for the bell icon
        notif = Notification(
            user_id=story_owner_id,
            title="💬 New Comment",
            body=f"{commenter_name} commented on your story{loc_str}: \"{snippet}\"",
            type="story_comment",
        )
        db.add(notif)
        await db.commit()

        # 2. Send FCM push notification
        res = await db.execute(select(User).where(User.id == story_owner_id))
        owner = res.scalar_one_or_none()
        if not owner:
            return

        prefs = owner.preferences or {}
        tokens = list(prefs.get("fcm_tokens") or [])
        legacy = prefs.get("fcm_token")
        if legacy and legacy not in tokens:
            tokens.append(legacy)

        if tokens:
            invalid = await fcm_service.send_to_tokens(
                db,
                tokens,
                title="💬 New Comment",
                body=f"{commenter_name} commented on your story{loc_str}: \"{snippet}\"",
                data={
                    "type": "story_comment",
                    "story_id": str(story_id),
                },
            )
            if invalid:
                new_prefs = {**prefs, "fcm_tokens": [t for t in tokens if t not in invalid]}
                new_prefs.pop("fcm_token", None)
                owner.preferences = new_prefs
                await db.commit()
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Failed to send comment notification to story owner {story_owner_id}: {e}")


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

    if not story.is_public and story.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: this travel story is private")

    comment = TravelStoryComment(
        story_id=story_id,
        user_id=current_user.id,
        comment_text=data.comment_text,
        image_index=data.image_index
    )
    db.add(comment)
    await db.flush()
    await db.commit()

    # Notify story owner if commenter is someone else. Nobody reads the
    # TravelByte account's notifications.
    if story.user_id != current_user.id and not story.is_official:
        await _notify_story_comment(
            db=db,
            story_owner_id=story.user_id,
            commenter_name=current_user.display_name or "Someone",
            story_location=story.location_name or "",
            comment_text=data.comment_text,
            story_id=story.id
        )

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
    files: List[UploadFile] = File(...),
    current_user: User = Depends(get_current_user)
):
    """Upload multiple images for a travel story (requires authentication & image validation)."""
    upload_dir = "app/static/uploads"
    os.makedirs(upload_dir, exist_ok=True)
    
    urls = []
    for file in files:
        filename = file.filename or ""
        file_ext = os.path.splitext(filename)[1].lower()
        if file_ext not in ALLOWED_IMAGE_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File extension '{file_ext}' is not allowed. Only JPG, PNG, WEBP, and GIF images are permitted."
            )

        content = await file.read()

        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File size exceeds maximum allowed limit (10MB)"
            )

        try:
            img = Image.open(io.BytesIO(content))
            img.verify()
            if img.format not in ["JPEG", "PNG", "WEBP", "GIF"]:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid image format"
                )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded file is not a valid image"
            )

        unique_filename = f"{uuid.uuid4()}{file_ext}"
        file_path = os.path.join(upload_dir, unique_filename)
        
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
        
    latitude, longitude = data.latitude, data.longitude
    place_changed = (
        data.location_name != story.location_name
        or latitude != story.latitude
        or longitude != story.longitude
    )
    if data.location_source is None and not story.is_journal and place_changed:
        fixed = await story_location.corrected_location(
            data.location_name, data.country or story.country, latitude, longitude,
        )
        if fixed:
            latitude, longitude = fixed

    # Update fields
    story.location_name = data.location_name
    story.category = data.category
    story.description = data.description
    story.image_url = data.image_url
    story.image_urls = data.image_urls
    story.latitude = latitude
    story.longitude = longitude
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
        comments=comments_list,
        image_previews=await _previews([story]),
    )
