"""
Museum Masterpieces – curated itineraries for the world's top museums.

Endpoints
---------
GET  /museums/               → list all museums
GET  /museums/{slug}         → full museum detail with all masterpieces
GET  /museums/{slug}/itinerary?duration=5h  → time-filtered walking route
"""

from collections import OrderedDict
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.repositories.museum_repository import MuseumRepository
from app.schemas.museum import (
    MuseumListItem,
    MuseumDetail,
    MuseumItinerary,
    BuildingSection,
    MasterpieceOut,
)

router = APIRouter(prefix="/museums", tags=["Museums"])


@router.get("/", response_model=list[MuseumListItem])
async def list_museums(db: AsyncSession = Depends(get_db)):
    """Return every museum ordered by global visitor rank."""
    museums = await MuseumRepository.get_all(db)
    items = []
    for m in museums:
        count = await MuseumRepository.get_masterpiece_count(db, m.id)
        items.append(
            MuseumListItem(
                id=m.id,
                slug=m.slug,
                name=m.name,
                city=m.city,
                country=m.country,
                annual_visitors=m.annual_visitors,
                rank=m.rank,
                image_url=m.image_url,
                masterpiece_count=count,
            )
        )
    return items


@router.get("/{slug}", response_model=MuseumDetail)
async def get_museum(slug: str, db: AsyncSession = Depends(get_db)):
    """Return full museum detail including all masterpieces."""
    museum = await MuseumRepository.get_by_slug(db, slug)
    if museum is None:
        raise HTTPException(status_code=404, detail="Museum not found")
    return museum


@router.get("/{slug}/itinerary", response_model=MuseumItinerary)
async def get_museum_itinerary(
    slug: str,
    duration: str = Query("1d", regex="^(5h|1d|2d)$"),
    db: AsyncSession = Depends(get_db),
):
    """Return a walking route filtered by available time.

    Query params:
      - duration: one of ``5h``, ``1d``, ``2d``
    """
    museum, masterpieces = await MuseumRepository.get_itinerary(db, slug, duration)
    if museum is None:
        raise HTTPException(status_code=404, detail="Museum not found")

    # Group by building, preserving order of first appearance
    grouped: OrderedDict[str, list] = OrderedDict()
    for mp in masterpieces:
        grouped.setdefault(mp.building, []).append(MasterpieceOut.model_validate(mp))

    sections = [
        BuildingSection(building=building, items=items)
        for building, items in grouped.items()
    ]

    return MuseumItinerary(
        museum_name=museum.name,
        museum_slug=museum.slug,
        duration=duration.lower(),
        total_items=len(masterpieces),
        buildings=sections,
    )
