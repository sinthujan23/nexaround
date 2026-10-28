"""City Tours in the app: the approved guides, and taps on their partner links.

Only `live_content` is ever read here: what an admin approved, never a
creator's working copy. The partner links come out ready to tap. Affiliate
links point at our /go/city-tour address, which counts the tap and sends the
traveller on through Travelpayouts; Experience links carry the package, which
the app opens on its own detail page after telling us of the tap.
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_optional
from app.api.v1.city_tours_admin import _listed_packages, linked_package_ids, package_view
from app.core.config import settings
from app.core.database import get_db
from app.core.rate_limiter import RateLimiter, get_client_ip, get_redis_client
from app.models.city_tour import CityTour, CityTourTap
from app.services import city_tours

router = APIRouter(prefix="/city-tours", tags=["City Tours"])

# A tap is one row; a page reloaded in a loop must not fill the table or the report.
tap_limiter = RateLimiter(requests_per_minute=30, window_seconds=60)


async def tap_allowed(ip: str) -> bool:
    key = f"rate_limit:city_tour_tap:ip:{ip}"
    try:
        return not await tap_limiter._check_rate_limit(key, await get_redis_client())
    except Exception:
        return not await tap_limiter._check_rate_limit(key, None)


def go_url(tour_id, link_id: str) -> str:
    return f"{settings.PUBLIC_BASE_URL.rstrip('/')}/api/v1/go/city-tour/{tour_id}/{link_id}"


def _live():
    return select(CityTour).where(CityTour.live_content.isnot(None), CityTour.is_hidden.is_(False))


async def live_tour(db: AsyncSession, tour_id: uuid.UUID) -> CityTour:
    tour = (await db.execute(_live().where(CityTour.id == tour_id))).scalar_one_or_none()
    if tour is None:
        raise HTTPException(status_code=404, detail="This guide is no longer available.")
    return tour


@router.get("")
async def list_city_tours(db: AsyncSession = Depends(get_db)):
    """Every live guide as a card; the app groups them into cities."""
    tours = (await db.execute(_live().order_by(CityTour.published_at))).scalars().all()
    return {
        "tours": [
            {"id": str(t.id), **city_tours.card(t.live_content), "updated_at": t.live_updated_at}
            for t in tours
        ],
    }


@router.get("/{tour_id}")
async def get_city_tour(tour_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    """One guide, stops numbered, partner links resolved. An Experience that is
    no longer listed drops out of its step."""
    tour = await live_tour(db, tour_id)
    listed = await _listed_packages(db, linked_package_ids(tour.live_content))
    view = city_tours.app_view(
        tour.live_content,
        tap_url=lambda link_id: go_url(tour.id, link_id),
        package_view=lambda package_id: package_view(listed[package_id]) if package_id in listed else None,
    )
    return {"id": str(tour.id), **view, "updated_at": tour.live_updated_at}


@router.post("/{tour_id}/links/{link_id}/tap", status_code=204)
async def record_tap(
    tour_id: uuid.UUID,
    link_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user_optional),
):
    """The app opened an Experience from a guide. Counted like a /go tap."""
    tour = await live_tour(db, tour_id)
    link = city_tours.find_link(tour.live_content, link_id)
    if link is None or link.get("kind") != city_tours.EXPERIENCE:
        raise HTTPException(status_code=404, detail="Link not found")
    if await tap_allowed(get_client_ip(request)):
        db.add(CityTourTap(
            tour_id=tour.id, link_id=link["id"], partner=city_tours.EXPERIENCE,
            package_id=uuid.UUID(link["package_id"]) if link.get("package_id") else None,
            user_id=user.id if user is not None else None,
        ))
        await db.commit()
    return Response(status_code=204)
