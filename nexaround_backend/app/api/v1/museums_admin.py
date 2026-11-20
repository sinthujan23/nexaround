"""Museums in the admin panel: data entry in the shape the app shows them.

Before this, museums came from spreadsheets loaded by scripts
(app/scripts/import_museum_itinerary.py). Now the admin and team members given
Museums (creator_auth.MUSEUMS) type them in: the museum's card (name, place,
visitors, world rank, photo), the guide page's opening hours and website, and
the must-see items with the tours (3 hours / 5 hours / 1 day / 2 days) each one
is part of and its stop in each.

A new museum starts hidden, so a half-entered one never shows in the app;
whoever enters it switches it on. Deleting a museum is the admin's alone.
"""
import hashlib
import io
import re
import unicodedata
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from PIL import Image, ImageOps
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import defer, selectinload

from app.api.v1.admin import allow_team, verify_admin_token
from app.api.v1.museums import museum_image_url
from app.core.database import get_db
from app.models.museum import Museum, MuseumMasterpiece
from app.schemas.museum import (
    DURATIONS, MuseumAdminCreate, MuseumAdminDetail, MuseumAdminListItem, MuseumAdminSave,
    MuseumItemOut, MuseumVisibilityIn,
)
from app.services.creator_auth import MUSEUMS
from app.services.experience_upload import ALLOWED_IMAGE_FORMATS, MAX_FILE_SIZE

router = APIRouter(prefix="/admin/museums", tags=["Admin Museums"])

allow_museums = allow_team(MUSEUMS)

# The photo as stored: big enough for the guide's full-width header.
PHOTO_MAX_SIDE = 1600
PHOTO_QUALITY = 85


def _slugify(name: str) -> str:
    """"Musée d'Orsay" → "musee-dorsay", as the seeded rows are."""
    ascii_name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    ascii_name = ascii_name.replace("'", "").replace("’", "")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_name.lower()).strip("-")
    return (slug or "museum")[:110]


async def _free_slug(db: AsyncSession, name: str) -> str:
    base = _slugify(name)
    taken = set((
        await db.execute(select(Museum.slug).where(Museum.slug.like(f"{base}%")))
    ).scalars().all())
    if base not in taken:
        return base
    n = 2
    while f"{base}-{n}" in taken:
        n += 1
    return f"{base}-{n}"


async def _get(db: AsyncSession, museum_id: uuid.UUID) -> Museum:
    museum = (
        await db.execute(
            select(Museum)
            .where(Museum.id == museum_id)
            .options(defer(Museum.image_data), selectinload(Museum.masterpieces))
        )
    ).scalar_one_or_none()
    if museum is None:
        raise HTTPException(status_code=404, detail="Museum not found")
    return museum


async def _has_photo(db: AsyncSession, museum_id: uuid.UUID) -> bool:
    return bool((
        await db.execute(select(Museum.image_data.isnot(None)).where(Museum.id == museum_id))
    ).scalar_one())


async def _detail(db: AsyncSession, museum: Museum) -> MuseumAdminDetail:
    categories = (
        await db.execute(
            select(MuseumMasterpiece.category)
            .group_by(MuseumMasterpiece.category)
            .order_by(func.count().desc(), MuseumMasterpiece.category)
            .limit(300)
        )
    ).scalars().all()
    items = sorted(museum.masterpieces, key=lambda mp: mp.rank)
    return MuseumAdminDetail(
        id=museum.id, slug=museum.slug, name=museum.name, city=museum.city,
        country=museum.country, annual_visitors=museum.annual_visitors, rank=museum.rank,
        image_url=museum_image_url(museum, await _has_photo(db, museum.id)),
        opening_hours=museum.opening_hours, website=museum.website, is_hidden=museum.is_hidden,
        items=[MuseumItemOut.model_validate(mp) for mp in items],
        categories=list(categories),
    )


@router.get("", response_model=list[MuseumAdminListItem])
async def list_museums(db: AsyncSession = Depends(get_db), _=Depends(allow_museums)):
    """Every museum, hidden ones too, in the app's order (world rank)."""
    rows = (
        await db.execute(
            select(Museum, Museum.image_data.isnot(None).label("has_image"))
            .options(defer(Museum.image_data))
            .order_by(Museum.rank.asc().nulls_last(), Museum.name)
        )
    ).all()
    stats = {
        museum_id: (count, tours)
        for museum_id, count, *tours in (
            await db.execute(
                select(
                    MuseumMasterpiece.museum_id, func.count(),
                    *[func.bool_or(getattr(MuseumMasterpiece, f"included_{d}")) for d in DURATIONS],
                ).group_by(MuseumMasterpiece.museum_id)
            )
        ).all()
    }
    out = []
    for museum, has_image in rows:
        count, tours = stats.get(museum.id, (0, [False] * len(DURATIONS)))
        out.append(MuseumAdminListItem(
            id=museum.id, slug=museum.slug, name=museum.name, city=museum.city,
            country=museum.country, annual_visitors=museum.annual_visitors, rank=museum.rank,
            image_url=museum_image_url(museum, has_image), item_count=count,
            tours=[d for d, on in zip(DURATIONS, tours) if on], is_hidden=museum.is_hidden,
        ))
    return out


@router.post("", response_model=MuseumAdminDetail, status_code=201)
async def create_museum(
    data: MuseumAdminCreate, db: AsyncSession = Depends(get_db), _=Depends(allow_museums),
):
    """Start a museum: hidden from the app until it is switched on."""
    museum = Museum(
        slug=await _free_slug(db, data.name), name=data.name, city=data.city,
        country=data.country, is_hidden=True,
    )
    db.add(museum)
    await db.commit()
    return await _detail(db, await _get(db, museum.id))


@router.get("/{museum_id}", response_model=MuseumAdminDetail)
async def get_museum(
    museum_id: uuid.UUID, db: AsyncSession = Depends(get_db), _=Depends(allow_museums),
):
    return await _detail(db, await _get(db, museum_id))


@router.put("/{museum_id}", response_model=MuseumAdminDetail)
async def save_museum(
    museum_id: uuid.UUID,
    data: MuseumAdminSave,
    db: AsyncSession = Depends(get_db),
    _=Depends(allow_museums),
):
    """Save the museum and its whole item list, as the editor holds it.

    `items` order is the museum's full list (rank 1..n). Each tour is ordered
    by the stop numbers sent, as the app orders it (a missing stop falls back
    to the item's rank), then renumbered 1..n, so the app's stops never skip.
    Items left out are removed.
    """
    museum = await _get(db, museum_id)
    museum.name = data.name
    museum.city = data.city
    museum.country = data.country
    museum.annual_visitors = data.annual_visitors
    museum.rank = data.rank
    museum.opening_hours = data.opening_hours
    museum.website = data.website

    existing = {mp.id: mp for mp in museum.masterpieces}
    kept: list[tuple[MuseumMasterpiece, object]] = []
    for position, item in enumerate(data.items, start=1):
        mp = existing.pop(item.id, None) if item.id else None
        if mp is None:
            mp = MuseumMasterpiece()
            museum.masterpieces.append(mp)
        mp.rank = position
        mp.building = item.building
        mp.room_gallery = item.room_gallery
        mp.must_see_item = item.must_see_item
        mp.artist = item.artist
        mp.category = item.category
        mp.description = item.description
        for d in DURATIONS:
            setattr(mp, f"included_{d}", getattr(item, f"included_{d}"))
        kept.append((mp, item))
    for gone in existing.values():
        museum.masterpieces.remove(gone)  # delete-orphan removes the row

    for d in DURATIONS:
        in_tour = [(mp, item) for mp, item in kept if getattr(item, f"included_{d}")]
        in_tour.sort(key=lambda pair: (getattr(pair[1], f"stop_{d}") or pair[0].rank, pair[0].rank))
        for stop, (mp, _item) in enumerate(in_tour, start=1):
            setattr(mp, f"stop_{d}", stop)
        for mp, item in kept:
            if not getattr(item, f"included_{d}"):
                setattr(mp, f"stop_{d}", None)

    await db.commit()
    db.expire_all()
    return await _detail(db, await _get(db, museum_id))


@router.post("/{museum_id}/visibility", response_model=MuseumAdminDetail)
async def set_visibility(
    museum_id: uuid.UUID,
    data: MuseumVisibilityIn,
    db: AsyncSession = Depends(get_db),
    _=Depends(allow_museums),
):
    """Show the museum in the app, or take it out for now."""
    museum = await _get(db, museum_id)
    museum.is_hidden = data.hidden
    await db.commit()
    return await _detail(db, museum)


@router.post("/{museum_id}/photo", response_model=MuseumAdminDetail)
async def upload_photo(
    museum_id: uuid.UUID,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    _=Depends(allow_museums),
):
    """The museum's photo (list card and guide header), kept in the database
    like every museum photo, as a JPEG no wider or taller than 1600 px."""
    museum = await _get(db, museum_id)
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail=f"The photo is larger than {MAX_FILE_SIZE // (1024 * 1024)} MB.")
    try:
        img = Image.open(io.BytesIO(content))
        if img.format not in ALLOWED_IMAGE_FORMATS:
            raise ValueError(img.format)
        img.load()
    except Exception:
        raise HTTPException(status_code=400, detail="That file is not a photo (JPEG, PNG, WebP or GIF).")
    img = ImageOps.exif_transpose(img).convert("RGB")
    img.thumbnail((PHOTO_MAX_SIDE, PHOTO_MAX_SIDE))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=PHOTO_QUALITY, optimize=True)
    data = buf.getvalue()
    museum.image_data = data
    museum.image_content_type = "image/jpeg"
    # A new address per photo, so the app's image cache does not keep the old one.
    museum.image_url = f"/api/v1/museums/{museum.slug}/image?v={hashlib.md5(data).hexdigest()[:10]}"
    await db.commit()
    return await _detail(db, await _get(db, museum_id))


@router.delete("/{museum_id}")
async def delete_museum(
    museum_id: uuid.UUID, db: AsyncSession = Depends(get_db), _=Depends(verify_admin_token),
):
    """Remove a museum and its items for good. Admin only."""
    museum = await _get(db, museum_id)
    await db.delete(museum)
    await db.commit()
    return {"status": "deleted"}
