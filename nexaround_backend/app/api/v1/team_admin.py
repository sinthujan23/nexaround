"""Team logins: the people, other than the admin, who sign in to the admin
panel (creator_auth). The admin creates each login, ticks the areas it opens
(City Guides, Experiences, TravelBytes) and, for City Guides, whether the
member puts guides live themselves or sends each version for review.

Any change to what a login may do, a new password or switching it off signs
the member out everywhere at once, so their panel never shows stale areas.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import require_admin
from app.core.database import get_db
from app.core.security import get_password_hash
from app.models.city_tour import CityTour, ContentCreator
from app.schemas.city_tour import ContentCreatorIn, ContentCreatorOut, ContentCreatorPatch
from app.services import audit, creator_auth

router = APIRouter(prefix="/admin/team", tags=["Admin Team"])


async def _member_out(db: AsyncSession, member: ContentCreator) -> ContentCreatorOut:
    counts = (
        await db.execute(
            select(func.count(CityTour.id), func.count(CityTour.live_content))
            .where(CityTour.creator_id == member.id)
        )
    ).one()
    return ContentCreatorOut(
        id=member.id, name=member.name, email=member.email, is_active=member.is_active,
        sections=list(member.sections or []), can_publish_guides=member.can_publish_guides,
        created_at=member.created_at, last_login_at=member.last_login_at,
        tour_count=counts[0], live_count=counts[1],
    )


@router.get("", response_model=list[ContentCreatorOut])
async def list_members(db: AsyncSession = Depends(get_db), _: str = Depends(require_admin)):
    members = (
        await db.execute(select(ContentCreator).order_by(ContentCreator.created_at))
    ).scalars().all()
    return [await _member_out(db, m) for m in members]


@router.post("", response_model=ContentCreatorOut, status_code=201)
async def create_member(
    data: ContentCreatorIn,
    db: AsyncSession = Depends(get_db),
    _: str = Depends(require_admin),
):
    email = creator_auth.normalize_email(str(data.email))
    exists = (
        await db.execute(select(ContentCreator.id).where(ContentCreator.email == email))
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=409, detail="There is already a team login with that email.")
    now = datetime.now(timezone.utc)
    member = ContentCreator(
        name=data.name.strip(), email=email, password_hash=get_password_hash(data.password),
        is_active=True, sections=list(data.sections), can_publish_guides=data.can_publish_guides,
        created_at=now, password_changed_at=now,
    )
    db.add(member)
    await db.commit()
    await db.refresh(member)
    return await _member_out(db, member)


@router.patch("/{member_id}", response_model=ContentCreatorOut)
async def update_member(
    member_id: uuid.UUID,
    data: ContentCreatorPatch,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """Rename, change the areas or the City Guides setting, switch the login
    off or on, or set a new password. Anything but a rename or switching on
    signs the member out everywhere."""
    member = await db.get(ContentCreator, member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Team member not found")
    sign_out = False
    if data.name is not None:
        member.name = data.name.strip()
    if data.is_active is not None:
        sign_out = sign_out or (member.is_active and not data.is_active)
        member.is_active = data.is_active
    if data.sections is not None and list(data.sections) != list(member.sections or []):
        member.sections = list(data.sections)
        sign_out = True
    if data.can_publish_guides is not None and data.can_publish_guides != member.can_publish_guides:
        member.can_publish_guides = data.can_publish_guides
        sign_out = True
    if data.password is not None:
        member.password_hash = get_password_hash(data.password)
        member.password_changed_at = datetime.now(timezone.utc)
        sign_out = True
    await db.commit()
    await db.refresh(member)
    if sign_out:
        await audit.revoke_sessions_for(
            actor_type=creator_auth.ACTOR, actor_id=str(member.id), reason="admin", by=admin,
        )
    return await _member_out(db, member)


@router.delete("/{member_id}")
async def delete_member(
    member_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """Remove a login. Their guides stay, under their name, for the admin to
    keep or delete."""
    member = await db.get(ContentCreator, member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Team member not found")
    await db.delete(member)
    await db.commit()
    await audit.revoke_sessions_for(
        actor_type=creator_auth.ACTOR, actor_id=str(member_id), reason="admin", by=admin,
    )
    return {"status": "deleted"}
