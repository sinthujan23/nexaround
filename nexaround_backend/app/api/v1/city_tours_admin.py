"""City Tours in the admin panel: writing guides, reviewing them, creator logins.

Two kinds of people use these endpoints. Admins see every guide, approve or
send back what creators send, hide live guides and manage creator logins.
Content creators (creator_auth) see and edit only their own guides and send
them for review; nothing they write reaches the app until an admin approves
that exact version. Everything here sits under /admin, so the audit
middleware records every write with who made it.
"""
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, Request, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.v1.admin import verify_admin_token
from app.api.v1.experiences_admin import admin_place_search
from app.core.database import get_db
from app.core.security import decode_token, get_password_hash
from app.models.city_tour import CityTour, CityTourTap, ContentCreator
from app.models.experience import ExperiencePackage, ExperienceVendor
from app.schemas.city_tour import (
    CityTourDetail, CityTourListItem, CityTourReviewIn, CityTourSaveIn, CityTourVersionIn,
    CityTourVisibilityIn, ContentCreatorIn, ContentCreatorOut, ContentCreatorPatch,
)
from app.services import audit, city_tours, creator_auth, legal_service
from app.services.experience_service import package_to_card
from app.services.experience_upload import save_experience_images

router = APIRouter(prefix="/admin/city-tours", tags=["Admin City Tours"])


# ── Who is asking ────────────────────────────────────────────────────────────

@dataclass
class Editor:
    role: str  # "admin" | "creator"
    name: str
    creator_id: Optional[uuid.UUID] = None

    @property
    def is_admin(self) -> bool:
        return self.role == "admin"


async def require_editor(request: Request, authorization: str = Header(...)) -> Editor:
    """An admin, or a signed-in content creator."""
    token = authorization.split(" ")[1] if authorization.startswith("Bearer ") else ""
    payload = decode_token(token) or {}
    if payload.get("role") == creator_auth.ROLE:
        creator = await creator_auth.from_token(payload, request)
        if creator is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Access Denied: Invalid or expired credentials.",
            )
        audit.set_actor(
            request, actor_type=creator_auth.ACTOR, actor_id=str(creator.id),
            actor_label=creator.name, session_id=payload["sid"],
        )
        return Editor(role=creator_auth.ROLE, name=creator.name, creator_id=creator.id)
    await verify_admin_token(request, authorization)
    return Editor(role="admin", name=payload.get("sub") or "admin")


async def require_admin_editor(editor: Editor = Depends(require_editor)) -> Editor:
    if not editor.is_admin:
        raise HTTPException(status_code=403, detail="Only an admin can do that.")
    return editor


def _content_error(e: city_tours.ContentError) -> HTTPException:
    return HTTPException(status_code=422, detail=str(e))


# ── Experiences a guide can link to ──────────────────────────────────────────

def linked_package_ids(content: dict) -> set[uuid.UUID]:
    """The Experiences a guide links to."""
    ids = set()
    for _step, link in city_tours.links(content):
        if link.get("kind") == city_tours.EXPERIENCE and link.get("package_id"):
            ids.add(uuid.UUID(link["package_id"]))
    return ids


async def _listed_packages(
    db: AsyncSession, ids: Optional[set[uuid.UUID]] = None,
) -> dict[str, ExperiencePackage]:
    """Experiences the app shows today, by id: published, their vendor active
    and not held back by the Provider Agreement. `ids` narrows it to those."""
    if ids is not None and not ids:
        return {}
    query = (
        select(ExperiencePackage)
        .join(ExperiencePackage.vendor)
        .where(ExperiencePackage.is_published.is_(True), ExperienceVendor.is_active.is_(True))
        .options(selectinload(ExperiencePackage.vendor))
    )
    if ids is not None:
        query = query.where(ExperiencePackage.id.in_(ids))
    rows = (await db.execute(query)).scalars().all()
    hidden = set(await legal_service.hidden_vendor_ids(db)) if rows else set()
    return {str(p.id): p for p in rows if p.vendor_id not in hidden}


def package_view(package: ExperiencePackage) -> dict:
    """An Experience as a guide shows it: what its card in the app shows."""
    card = package_to_card(package)
    return {
        "id": str(package.id),
        "title": card.title,
        "vendor_name": card.vendor_name or "",
        "photo_url": card.cover_photo_url or "",
        "price_label": card.price_label or "",
        "place": card.region_label or card.country_name or "",
        "duration_label": card.duration_label or "",
    }


# ── Shapes ───────────────────────────────────────────────────────────────────

def _is_live(tour: CityTour) -> bool:
    return tour.live_content is not None


def _list_item(tour: CityTour, editor: Editor, taps: Optional[int]) -> dict:
    content = tour.content or {}
    return dict(
        id=tour.id,
        title=content.get("title") or "",
        city=content.get("city") or "",
        country=content.get("country") or "",
        cover_url=content.get("cover_url") or "",
        stop_count=len(city_tours.stops(content)),
        review_status=tour.review_status,
        review_note=tour.review_note,
        is_live=_is_live(tour),
        is_hidden=tour.is_hidden,
        has_changes=_is_live(tour) and tour.live_version != tour.version,
        author_name=tour.author_name,
        is_mine=editor.creator_id is not None and tour.creator_id == editor.creator_id,
        updated_at=tour.updated_at,
        submitted_at=tour.submitted_at,
        published_at=tour.published_at,
        taps=taps if editor.is_admin else None,
    )


async def _detail(db: AsyncSession, tour: CityTour, editor: Editor) -> CityTourDetail:
    listed = await _listed_packages(db, linked_package_ids(tour.content))
    link_taps = None
    if editor.is_admin:
        rows = (
            await db.execute(
                select(CityTourTap.link_id, func.count())
                .where(CityTourTap.tour_id == tour.id)
                .group_by(CityTourTap.link_id)
            )
        ).all()
        link_taps = {link_id: count for link_id, count in rows}
    item = _list_item(tour, editor, sum(link_taps.values()) if link_taps is not None else None)
    return CityTourDetail(
        **item,
        content=tour.content,
        version=tour.version,
        live_version=tour.live_version,
        reviewed_at=tour.reviewed_at,
        reviewed_by=tour.reviewed_by,
        problems=city_tours.problems(tour.content, package_ok=listed.__contains__),
        can_delete=editor.is_admin or not _is_live(tour),
        link_taps=link_taps,
    )


async def _get_tour(db: AsyncSession, tour_id: uuid.UUID, editor: Editor) -> CityTour:
    """The guide, if this editor may see it. A creator asking for someone
    else's gets the same 404 as for one that does not exist."""
    tour = await db.get(CityTour, tour_id)
    if tour is None or (not editor.is_admin and tour.creator_id != editor.creator_id):
        raise HTTPException(status_code=404, detail="Guide not found")
    return tour


def _check_version(tour: CityTour, version: Optional[int]) -> None:
    if version is not None and version != tour.version:
        raise HTTPException(
            status_code=409,
            detail="This guide was changed somewhere else since you opened it. Reload it to see the latest version.",
        )


# ── Supporting endpoints (before /{tour_id}, which would swallow their paths) ─

@router.get("/count")
async def count_waiting(
    db: AsyncSession = Depends(get_db), _: Editor = Depends(require_admin_editor),
):
    """Guides waiting for an admin: the sidebar badge."""
    pending = (
        await db.execute(
            select(func.count(CityTour.id)).where(CityTour.review_status == city_tours.PENDING)
        )
    ).scalar_one()
    return {"pending": pending}


@router.get("/partners")
async def list_partners(
    db: AsyncSession = Depends(get_db), _: Editor = Depends(require_editor),
):
    """What a guide can link to: the affiliate programs, and every Experience
    listed in the app (only what travellers see anyway, no vendor contacts)."""
    packages = sorted(
        (package_view(p) for p in (await _listed_packages(db)).values()),
        key=lambda p: (p["place"].casefold(), p["title"].casefold()),
    )
    return {
        "affiliates": [
            {"key": a.key, "name": a.name, "what": a.what, "domain": a.domains[0], "example": a.example}
            for a in city_tours.AFFILIATES.values()
        ],
        "experiences": packages,
        "transport_modes": [{"key": k, "label": v} for k, v in city_tours.TRANSPORT_MODES.items()],
    }


@router.get("/place-search")
async def place_search(
    query: str = Query(..., min_length=2),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    db: AsyncSession = Depends(get_db),
    _: Editor = Depends(require_editor),
):
    """Google search for a stop: the vendors' search, open to creators too."""
    return await admin_place_search(query=query, lat=lat, lng=lng, db=db, _=None)


@router.post("/upload")
async def upload_photos(
    files: List[UploadFile] = File(...), _: Editor = Depends(require_editor),
):
    """Photos for a guide, with the same checks as every other upload."""
    return {"urls": await save_experience_images(files)}


@router.get("/taps")
async def tap_report(
    days: int = Query(30, ge=0, le=3650),
    db: AsyncSession = Depends(get_db),
    _: Editor = Depends(require_admin_editor),
):
    """Partner taps per link over the last `days` (0 = all time), for reporting
    to partners. Names come from the live guide, else the working copy."""
    query = (
        select(CityTourTap.tour_id, CityTourTap.link_id, CityTourTap.partner,
               CityTourTap.package_id, func.count(), func.max(CityTourTap.created_at))
        .group_by(CityTourTap.tour_id, CityTourTap.link_id, CityTourTap.partner, CityTourTap.package_id)
    )
    if days:
        query = query.where(CityTourTap.created_at >= datetime.now(timezone.utc) - timedelta(days=days))
    rows = (await db.execute(query)).all()

    tours = {
        t.id: t for t in (
            await db.execute(select(CityTour).where(CityTour.id.in_({r[0] for r in rows})))
        ).scalars().all()
    } if rows else {}
    package_ids = {r[3] for r in rows if r[3]}
    packages = {
        p.id: p for p in (
            await db.execute(
                select(ExperiencePackage).where(ExperiencePackage.id.in_(package_ids))
                .options(selectinload(ExperiencePackage.vendor))
            )
        ).scalars().all()
    } if package_ids else {}

    out = []
    for tour_id, link_id, partner, package_id, count, last in rows:
        tour = tours.get(tour_id)
        content = (tour.live_content or tour.content) if tour else {}
        link = city_tours.find_link(content, link_id) or {}
        step = next((s for s, l in city_tours.links(content) if l.get("id") == link_id), None)
        if partner == city_tours.EXPERIENCE:
            package = packages.get(package_id)
            partner_name = package.vendor.name if package and package.vendor else "Experience"
            target = package.title if package else "An experience no longer listed"
        else:
            affiliate = city_tours.AFFILIATES.get(partner)
            partner_name = affiliate.name if affiliate else partner
            target = link.get("url") or ""
        out.append({
            "tour_id": str(tour_id),
            "tour_title": content.get("title") or "A deleted guide",
            "city": content.get("city") or "",
            "link_id": link_id,
            "label": link.get("label") or "",
            "where": city_tours.step_name(content, step) if step else "",
            "partner": partner,
            "partner_name": partner_name,
            "target": target,
            "taps": count,
            "last_tap_at": last,
        })
    out.sort(key=lambda r: (r["partner_name"].casefold(), -r["taps"]))
    return {"days": days, "rows": out, "total": sum(r["taps"] for r in out)}


# ── Content creators (admin only) ────────────────────────────────────────────

async def _creator_out(db: AsyncSession, creator: ContentCreator) -> ContentCreatorOut:
    counts = (
        await db.execute(
            select(func.count(CityTour.id), func.count(CityTour.live_content))
            .where(CityTour.creator_id == creator.id)
        )
    ).one()
    return ContentCreatorOut(
        id=creator.id, name=creator.name, email=creator.email, is_active=creator.is_active,
        created_at=creator.created_at, last_login_at=creator.last_login_at,
        tour_count=counts[0], live_count=counts[1],
    )


@router.get("/creators", response_model=list[ContentCreatorOut])
async def list_creators(
    db: AsyncSession = Depends(get_db), _: Editor = Depends(require_admin_editor),
):
    creators = (
        await db.execute(select(ContentCreator).order_by(ContentCreator.created_at))
    ).scalars().all()
    return [await _creator_out(db, c) for c in creators]


@router.post("/creators", response_model=ContentCreatorOut, status_code=201)
async def create_creator(
    data: ContentCreatorIn,
    db: AsyncSession = Depends(get_db),
    _: Editor = Depends(require_admin_editor),
):
    email = creator_auth.normalize_email(str(data.email))
    exists = (
        await db.execute(select(ContentCreator.id).where(ContentCreator.email == email))
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=409, detail="There is already a creator with that email.")
    now = datetime.now(timezone.utc)
    creator = ContentCreator(
        name=data.name.strip(), email=email, password_hash=get_password_hash(data.password),
        is_active=True, created_at=now, password_changed_at=now,
    )
    db.add(creator)
    await db.commit()
    await db.refresh(creator)
    return await _creator_out(db, creator)


@router.patch("/creators/{creator_id}", response_model=ContentCreatorOut)
async def update_creator(
    creator_id: uuid.UUID,
    data: ContentCreatorPatch,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_admin_editor),
):
    """Rename, switch the login off or on, or set a new password. Switching
    off or a new password signs the creator out everywhere at once."""
    creator = await db.get(ContentCreator, creator_id)
    if creator is None:
        raise HTTPException(status_code=404, detail="Creator not found")
    sign_out = False
    if data.name is not None:
        creator.name = data.name.strip()
    if data.is_active is not None:
        sign_out = sign_out or (creator.is_active and not data.is_active)
        creator.is_active = data.is_active
    if data.password is not None:
        creator.password_hash = get_password_hash(data.password)
        creator.password_changed_at = datetime.now(timezone.utc)
        sign_out = True
    await db.commit()
    await db.refresh(creator)
    if sign_out:
        await audit.revoke_sessions_for(
            actor_type=creator_auth.ACTOR, actor_id=str(creator.id),
            reason="admin", by=editor.name,
        )
    return await _creator_out(db, creator)


@router.delete("/creators/{creator_id}")
async def delete_creator(
    creator_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_admin_editor),
):
    """Remove a login. Their guides stay, under their name, for admins to keep
    or delete."""
    creator = await db.get(ContentCreator, creator_id)
    if creator is None:
        raise HTTPException(status_code=404, detail="Creator not found")
    await db.delete(creator)
    await db.commit()
    await audit.revoke_sessions_for(
        actor_type=creator_auth.ACTOR, actor_id=str(creator_id), reason="admin", by=editor.name,
    )
    return {"status": "deleted"}


# ── Guides ───────────────────────────────────────────────────────────────────

@router.get("", response_model=list[CityTourListItem])
async def list_tours(
    review_status: Optional[str] = Query(None, alias="status"),
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    """Every guide for an admin, a creator's own for a creator. `status`
    narrows to one review status, or "live" / "hidden"."""
    query = select(CityTour)
    if not editor.is_admin:
        query = query.where(CityTour.creator_id == editor.creator_id)
    if review_status in city_tours.STATUSES:
        query = query.where(CityTour.review_status == review_status)
    elif review_status == "live":
        query = query.where(CityTour.live_content.isnot(None), CityTour.is_hidden.is_(False))
    elif review_status == "hidden":
        query = query.where(CityTour.is_hidden.is_(True))
    if review_status == city_tours.PENDING:
        # The review queue: first sent, first reviewed.
        query = query.order_by(CityTour.submitted_at.asc().nulls_last())
    else:
        query = query.order_by(CityTour.updated_at.desc())
    tours = (await db.execute(query)).scalars().all()

    taps: dict = {}
    if editor.is_admin and tours:
        taps = dict((
            await db.execute(
                select(CityTourTap.tour_id, func.count())
                .where(CityTourTap.tour_id.in_([t.id for t in tours]))
                .group_by(CityTourTap.tour_id)
            )
        ).all())
    return [_list_item(t, editor, taps.get(t.id, 0)) for t in tours]


@router.post("", response_model=CityTourDetail, status_code=201)
async def create_tour(
    data: CityTourSaveIn,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    try:
        content = city_tours.normalize(data.content)
    except city_tours.ContentError as e:
        raise _content_error(e)
    tour = CityTour(
        creator_id=editor.creator_id,
        author_name=editor.name if editor.creator_id else "Admin",
        content=content, version=1, review_status=city_tours.DRAFT, is_hidden=False,
    )
    db.add(tour)
    await db.commit()
    await db.refresh(tour)
    return await _detail(db, tour, editor)


@router.get("/{tour_id}", response_model=CityTourDetail)
async def get_tour(
    tour_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    return await _detail(db, await _get_tour(db, tour_id, editor), editor)


@router.put("/{tour_id}", response_model=CityTourDetail)
async def save_tour(
    tour_id: uuid.UUID,
    data: CityTourSaveIn,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    """Save the working copy. The app keeps showing the approved version; a
    guide that was sent or live goes back to draft until it is sent again."""
    tour = await _get_tour(db, tour_id, editor)
    _check_version(tour, data.version)
    try:
        content = city_tours.normalize(data.content)
    except city_tours.ContentError as e:
        raise _content_error(e)
    if content != tour.content:
        tour.content = content
        tour.version += 1
        if content == tour.live_content:
            # Edited back to exactly what is live: nothing left to review.
            tour.review_status = city_tours.APPROVED
            tour.review_note = None
            tour.live_version = tour.version
        elif not (editor.is_admin and tour.review_status == city_tours.PENDING):
            # An admin tidying a guide in the queue keeps it there.
            tour.review_status = city_tours.status_after_edit(tour.review_status)
        await db.commit()
        await db.refresh(tour)
    return await _detail(db, tour, editor)


@router.post("/{tour_id}/submit", response_model=CityTourDetail)
async def submit_tour(
    tour_id: uuid.UUID,
    data: CityTourVersionIn,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    """Send the guide to an admin. It must be complete first."""
    tour = await _get_tour(db, tour_id, editor)
    _check_version(tour, data.version)
    if not city_tours.can_submit(tour.review_status):
        raise HTTPException(
            status_code=409,
            detail="Already waiting for review." if tour.review_status == city_tours.PENDING
            else "Nothing new to send: this version is already live.",
        )
    listed = await _listed_packages(db, linked_package_ids(tour.content))
    missing = city_tours.problems(tour.content, package_ok=listed.__contains__)
    if missing:
        raise HTTPException(status_code=422, detail="Before sending it: " + " ".join(missing))
    tour.review_status = city_tours.PENDING
    tour.submitted_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(tour)
    return await _detail(db, tour, editor)


@router.post("/{tour_id}/review", response_model=CityTourDetail)
async def review_tour(
    tour_id: uuid.UUID,
    data: CityTourReviewIn,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_admin_editor),
):
    """Approve the version the admin looked at (it goes live in the app as it
    is), or send it back to its creator with a note."""
    tour = await _get_tour(db, tour_id, editor)
    _check_version(tour, data.version)
    now = datetime.now(timezone.utc)
    note = data.note.strip()

    if data.decision == "request_changes":
        if tour.review_status != city_tours.PENDING:
            raise HTTPException(status_code=409, detail="Only a guide waiting for review can be sent back.")
        if not note:
            raise HTTPException(status_code=422, detail="Say what needs changing.")
        tour.review_status = city_tours.CHANGES_REQUESTED
        tour.review_note = note
    else:
        if tour.review_status == city_tours.APPROVED:
            raise HTTPException(status_code=409, detail="This version is already live.")
        listed = await _listed_packages(db, linked_package_ids(tour.content))
        missing = city_tours.problems(tour.content, package_ok=listed.__contains__)
        if missing:
            raise HTTPException(status_code=422, detail="Before it can go live: " + " ".join(missing))
        tour.review_status = city_tours.APPROVED
        tour.review_note = None
        tour.live_content = tour.content
        tour.live_version = tour.version
        tour.published_at = tour.published_at or now
        tour.live_updated_at = now
    tour.reviewed_at = now
    tour.reviewed_by = editor.name
    await db.commit()
    await db.refresh(tour)
    return await _detail(db, tour, editor)


@router.post("/{tour_id}/visibility", response_model=CityTourDetail)
async def set_visibility(
    tour_id: uuid.UUID,
    data: CityTourVisibilityIn,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_admin_editor),
):
    """Take a live guide off the app, or put it back."""
    tour = await _get_tour(db, tour_id, editor)
    tour.is_hidden = data.hidden
    await db.commit()
    await db.refresh(tour)
    return await _detail(db, tour, editor)


@router.delete("/{tour_id}")
async def delete_tour(
    tour_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    editor: Editor = Depends(require_editor),
):
    """A creator may delete a guide that never went live; a live one only an
    admin can, and its tap counts go with it."""
    tour = await _get_tour(db, tour_id, editor)
    if not editor.is_admin and _is_live(tour):
        raise HTTPException(status_code=403, detail="This guide is live. Ask an admin to take it down.")
    await db.delete(tour)
    await db.commit()
    return {"status": "deleted"}
