"""Admin "Map Database": our own places, their status, and the Review queue.

Every place has one status (see app/services/place_status.py):

    live      shown in the app
    pending   waiting in the Review queue
    hidden    taken out of the app by an admin
    rejected  a suggestion turned down; kept so Google cannot re-add it

Details are edited with PATCH and status is changed with POST .../status, so
an edit can never approve, hide or queue a place as a side effect — the old
single endpoint did exactly that, silently.
"""
import uuid
from typing import Literal, Optional

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import require_admin, verify_admin_token
from app.core.database import get_db
from app.schemas.attraction import (
    AdminPlace,
    AdminPlaceCreate,
    AdminPlaceDetail,
    AdminPlaceList,
    AdminPlaceUpdate,
    AdminPlaceUpdateResult,
    PlaceCountsResponse,
    PlaceStatusChange,
)
from app.services.attraction_service import AttractionService

router = APIRouter(prefix="/admin/attractions", tags=["Admin Map Database"])

StatusName = Literal["live", "pending", "hidden", "rejected"]
SourceName = Literal["google", "admin", "user", "seed", "unknown"]
SortName = Literal["newest", "oldest", "name", "updated", "queue"]


# Static paths are declared before "/{attraction_id}", or the UUID route would
# claim them and answer 422.

@router.get("/counts", response_model=PlaceCountsResponse)
async def place_counts(
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """How many places are in each status — the sidebar badge and tab counts."""
    return await AttractionService(db).admin_counts()


@router.get("", response_model=AdminPlaceList)
async def list_places(
    status_: StatusName = Query("live", alias="status"),
    q: Optional[str] = Query(None, max_length=200),
    source: Optional[SourceName] = None,
    reason: Optional[str] = Query(None, max_length=40),
    category_id: Optional[uuid.UUID] = None,
    submitted_by: Optional[uuid.UUID] = None,
    possible_duplicate: bool = False,
    sort: SortName = "newest",
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """One page of places in one status, plus every status's count under the
    same filters (for the tabs)."""
    return await AttractionService(db).admin_list(
        status=status_,
        page=page,
        page_size=page_size,
        sort=sort,
        q=q,
        source=source,
        reason=reason,
        category_id=category_id,
        submitted_by=submitted_by,
        possible_duplicate=possible_duplicate,
    )


@router.post("", response_model=AdminPlace, status_code=status.HTTP_201_CREATED)
async def create_place(
    data: AdminPlaceCreate,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """Add a place; it is live at once. 409 `possible_duplicate` when a similar
    place already exists within 25 m — resend with `confirm_duplicate: true`."""
    return await AttractionService(db).create_admin(data, admin)


@router.get("/{attraction_id}", response_model=AdminPlaceDetail)
async def get_place(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    return await AttractionService(db).admin_get(attraction_id)


@router.get("/{attraction_id}/nearby", response_model=list[AdminPlace])
async def nearby_places(
    attraction_id: uuid.UUID,
    radius_m: float = Query(150.0, ge=10.0, le=2000.0),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Places of any status around this one — the duplicate check in review."""
    return await AttractionService(db).admin_nearby(attraction_id, radius_m)


@router.patch("/{attraction_id}", response_model=AdminPlaceUpdateResult)
async def update_place(
    attraction_id: uuid.UUID,
    data: AdminPlaceUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Edit details (photos included). Never changes status."""
    return await AttractionService(db).update_place(attraction_id, data)


@router.post("/{attraction_id}/status", response_model=AdminPlace)
async def change_status(
    attraction_id: uuid.UUID,
    data: PlaceStatusChange,
    db: AsyncSession = Depends(get_db),
    admin: str = Depends(require_admin),
):
    """Approve, reject, hide, unhide, restore or reopen. 409 with a readable
    message for a move the rules do not allow."""
    return await AttractionService(db).change_status(
        attraction_id,
        target=data.status,
        reason=data.reason,
        note=data.note,
        admin=admin,
    )


@router.delete("/{attraction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_place(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Delete a place added by mistake. 409 `has_user_content` when people
    have reviewed or photographed it — hide it instead."""
    await AttractionService(db).hard_delete(attraction_id)
