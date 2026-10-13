import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import delete, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.attraction_repository import AttractionRepository
from app.models.analytics import PlaceVisit
from app.models.attraction import Attraction
from app.models.user import User
from app.schemas.attraction import (
    AdminPlace,
    AdminPlaceCreate,
    AdminPlaceDetail,
    AdminPlaceList,
    AdminPlaceUpdate,
    AdminPlaceUpdateResult,
    AttractionResponse,
    AttractionListResponse,
    AttractionSuggest,
    NearbyRequest,
    PlaceCountsResponse,
    PlaceStatusCounts,
    PlaceSubmitter,
    PlaceUsage,
)
from app.services import place_status, place_visibility
from app.utils.geo_utils import create_point, get_lat_lng
from app.core.exceptions import (
    BadRequestException,
    ConflictException,
    NotFoundException,
)
from fastapi import HTTPException, status as http_status

# Pending suggestions one app user may have waiting at once.
MAX_PENDING_SUGGESTIONS_PER_USER = 20


class AttractionService:
    """Business logic for Attraction management."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = AttractionRepository(db)

    def _map_to_response(
        self,
        attraction: Attraction,
        distance_m: Optional[float] = None,
        has_duplicate: bool = False
    ) -> AttractionResponse:
        """Helper to map a model to a response schema."""
        lat, lng = get_lat_lng(attraction.location)

        response_dict = {
            "id": attraction.id,
            "name": attraction.name,
            "description": attraction.description,
            "history": attraction.history,
            "latitude": lat,
            "longitude": lng,
            "category_id": attraction.category_id,
            "category_name": attraction.category.name if attraction.category else None,
            "address": attraction.address,
            "opening_hours": attraction.opening_hours,
            "entry_fee": attraction.entry_fee,
            "currency": attraction.currency,
            "rating": attraction.rating,
            "review_count": attraction.review_count,
            "photo_urls": attraction.photo_urls,
            "tags": attraction.tags,
            "geofence_radius_m": attraction.geofence_radius_m,
            "distance_m": distance_m,
            "is_active": attraction.is_active,
            "created_at": attraction.created_at,
            "has_duplicate_coordinates": has_duplicate
        }
        return AttractionResponse.model_validate(response_dict)

    # --- Public -----------------------------------------------------------

    async def get_live_attraction(self, attraction_id: uuid.UUID) -> Attraction:
        """The live row for an id, following a merged copy's alias.

        Anything not live is a 404: a hidden or rejected place, or one still in
        review, must not be readable by id either.
        """
        attraction = await self.repo.get_by_id(attraction_id)
        if attraction is None:
            target = await self.repo.resolve_alias(attraction_id)
            if target is not None:
                attraction = await self.repo.get_by_id(target)
        if attraction is None or attraction.status != place_status.LIVE:
            raise NotFoundException(detail="Attraction not found")
        return attraction

    async def get_attraction(self, attraction_id: uuid.UUID) -> AttractionResponse:
        """Get a live attraction by ID."""
        attraction = await self.get_live_attraction(attraction_id)

        # Check duplicate coordinates
        lat, lng = get_lat_lng(attraction.location)
        has_duplicate = False
        if lat is not None and lng is not None:
            dup = await self.repo.find_duplicate_by_coordinates(lat, lng, exclude_id=attraction.id)
            has_duplicate = dup is not None

        return self._map_to_response(attraction, has_duplicate=has_duplicate)

    async def list_attractions(
        self,
        page: int = 1,
        page_size: int = 20,
        category_id: Optional[uuid.UUID] = None,
        search_query: Optional[str] = None,
        is_active: Optional[bool] = None
    ) -> AttractionListResponse:
        """List attractions with pagination."""
        skip = (page - 1) * page_size
        attractions, total = await self.repo.list_attractions(
            skip=skip,
            limit=page_size,
            category_id=category_id,
            search_query=search_query,
            is_active=is_active
        )

        return AttractionListResponse(
            attractions=[self._map_to_response(a, has_duplicate=has_dup) for a, has_dup in attractions],
            total=total,
            page=page,
            page_size=page_size
        )

    async def get_nearby_attractions(self, request: NearbyRequest) -> list[AttractionResponse]:
        """Get live attractions near a coordinate."""
        nearby_data = await self.repo.get_nearby(
            latitude=request.latitude,
            longitude=request.longitude,
            radius_m=request.radius_m,
            category_id=request.category_id,
            limit=request.limit,
            sort_by_away=(request.sort == "away"),
        )

        return [self._map_to_response(a, dist) for a, dist in nearby_data]

    async def create_suggestion(self, data: AttractionSuggest, user: User) -> AttractionResponse:
        """An app user's proposed place. It waits for an admin in the Review queue."""
        waiting = await self.repo.count_pending_by_user(user.id)
        if waiting >= MAX_PENDING_SUGGESTIONS_PER_USER:
            raise HTTPException(
                status_code=http_status.HTTP_429_TOO_MANY_REQUESTS,
                detail="You have too many places waiting for review. "
                       "Please wait until some are checked.",
            )
        attraction = Attraction(
            name=data.name.strip(),
            description=data.description,
            location=create_point(data.latitude, data.longitude),
            category_id=data.category_id,
            address=data.address,
            status=place_status.PENDING,
            status_reason="user_suggestion",
            source="user",
            submitted_by_user_id=user.id,
        )
        attraction = await self.repo.create(attraction)
        full = await self.repo.get_by_id(attraction.id)
        return self._map_to_response(full)

    async def record_visit(self, attraction_id: uuid.UUID) -> None:
        """Count a detail open for the admin 'Places Visited' metric.
        Best-effort: analytics must never break the detail read."""
        try:
            self.db.add(PlaceVisit(attraction_id=attraction_id))
            await self.db.commit()
        except Exception:
            await self.db.rollback()

    # --- Admin: Map Database ----------------------------------------------

    def _admin_place(
        self,
        a: Attraction,
        *,
        has_duplicate: bool = False,
        distance_m: Optional[float] = None,
    ) -> AdminPlace:
        lat, lng = get_lat_lng(a.location)
        return AdminPlace(
            id=a.id,
            name=a.name,
            description=a.description,
            history=a.history,
            latitude=lat,
            longitude=lng,
            category_id=a.category_id,
            category_name=a.category.name if a.category else None,
            address=a.address,
            opening_hours=a.opening_hours or {},
            entry_fee=a.entry_fee or 0.0,
            currency=a.currency or "USD",
            rating=a.rating or 0.0,
            review_count=a.review_count or 0,
            photo_urls=a.photo_urls or [],
            tags=a.tags or [],
            geofence_radius_m=a.geofence_radius_m or 100,
            google_place_id=a.google_place_id,
            status=a.status,
            status_reason=a.status_reason,
            status_note=a.status_note,
            source=a.source,
            submitted_by_user_id=a.submitted_by_user_id,
            reviewed_at=a.reviewed_at,
            reviewed_by=a.reviewed_by,
            created_at=a.created_at,
            updated_at=a.updated_at,
            has_duplicate_coordinates=has_duplicate,
            distance_m=distance_m,
        )

    async def _get_or_404(self, attraction_id: uuid.UUID) -> Attraction:
        attraction = await self.repo.get_by_id(attraction_id)
        if attraction is None:
            raise NotFoundException(detail="Place not found")
        return attraction

    def _duplicate_payload(self, matches) -> list[dict]:
        return [
            {
                "id": str(a.id),
                "name": a.name,
                "status": a.status,
                "address": a.address,
                "distance_m": round(d or 0.0, 1),
            }
            for a, d in matches
        ]

    async def admin_list(
        self,
        *,
        status: str,
        page: int,
        page_size: int,
        sort: str,
        **filters,
    ) -> AdminPlaceList:
        rows, total = await self.repo.admin_list(
            status=status, sort=sort,
            offset=(page - 1) * page_size, limit=page_size,
            **filters,
        )
        counts = await self.repo.status_counts(**filters)
        return AdminPlaceList(
            items=[self._admin_place(a, has_duplicate=dup) for a, dup in rows],
            total=total,
            page=page,
            page_size=page_size,
            counts=PlaceStatusCounts(**counts),
        )

    async def admin_counts(self) -> PlaceCountsResponse:
        counts = await self.repo.status_counts()
        return PlaceCountsResponse(
            **counts, pending_user=await self.repo.count_pending_from_users()
        )

    async def admin_get(self, attraction_id: uuid.UUID) -> AdminPlaceDetail:
        a = await self._get_or_404(attraction_id)
        lat, lng = get_lat_lng(a.location)
        dup = await self.repo.find_duplicate_by_coordinates(lat, lng, exclude_id=a.id)
        submitter = None
        if a.submitted_by_user_id:
            user = await self.db.get(User, a.submitted_by_user_id)
            if user is not None:
                submitter = PlaceSubmitter(
                    id=user.id, display_name=user.display_name, email=user.email
                )
        return AdminPlaceDetail(
            **self._admin_place(a, has_duplicate=dup is not None).model_dump(),
            usage=PlaceUsage(**await self.repo.usage_counts(a.id)),
            submitter=submitter,
        )

    async def admin_nearby(self, attraction_id: uuid.UUID, radius_m: float) -> list[AdminPlace]:
        a = await self._get_or_404(attraction_id)
        lat, lng = get_lat_lng(a.location)
        rows = await self.repo.nearby_any_status(
            latitude=lat, longitude=lng, radius_m=radius_m, exclude_id=a.id,
        )
        seen = {r.id for r, _ in rows}
        if a.google_place_id:
            # Same Google place, wherever its row ended up.
            more = await self.repo.find_possible_duplicates(
                latitude=lat, longitude=lng, name=a.name,
                google_place_id=a.google_place_id, exclude_id=a.id,
            )
            rows += [(r, d) for r, d in more if r.id not in seen]
        return [self._admin_place(r, distance_m=d) for r, d in rows]

    async def create_admin(self, data: AdminPlaceCreate, admin: str) -> AdminPlace:
        """An admin adds a place. It goes live straight away, unless it looks
        like one we already hold, in which case the admin is asked first."""
        if not data.confirm_duplicate:
            matches = await self.repo.find_possible_duplicates(
                latitude=data.latitude, longitude=data.longitude, name=data.name,
            )
            if matches:
                raise ConflictException(detail={
                    "code": "possible_duplicate",
                    "message": "A place with a similar name already exists here.",
                    "matches": self._duplicate_payload(matches),
                })
        now = datetime.now(timezone.utc)
        attraction = Attraction(
            name=data.name.strip(),
            description=data.description,
            history=data.history,
            location=create_point(data.latitude, data.longitude),
            category_id=data.category_id,
            address=data.address,
            opening_hours=data.opening_hours,
            entry_fee=data.entry_fee,
            currency=data.currency,
            photo_urls=data.photo_urls,
            tags=data.tags,
            geofence_radius_m=data.geofence_radius_m,
            status=place_status.LIVE,
            source="admin",
            reviewed_at=now,
            reviewed_by=admin,
        )
        attraction = await self.repo.create(attraction)
        full = await self.repo.get_by_id(attraction.id)
        return self._admin_place(full)

    async def update_place(
        self, attraction_id: uuid.UUID, data: AdminPlaceUpdate
    ) -> AdminPlaceUpdateResult:
        """Edit details. Never changes status; a move onto another place's spot
        comes back as a warning for the admin to act on."""
        a = await self._get_or_404(attraction_id)
        changes = data.model_dump(exclude_unset=True)

        lat, lng = changes.pop("latitude", None), changes.pop("longitude", None)
        if (lat is None) != (lng is None):
            raise BadRequestException(detail="Send latitude and longitude together.")
        if "name" in changes and not (changes["name"] or "").strip():
            raise BadRequestException(detail="Name can't be empty.")

        moved_or_renamed = "name" in changes
        if lat is not None:
            cur_lat, cur_lng = get_lat_lng(a.location)
            if abs(cur_lat - lat) > 0.000001 or abs(cur_lng - lng) > 0.000001:
                a.location = create_point(lat, lng)
                moved_or_renamed = True

        for field, value in changes.items():
            if field == "name":
                value = value.strip()
            setattr(a, field, value)

        a = await self.repo.update(a)

        warnings = []
        final_lat, final_lng = get_lat_lng(a.location)
        if moved_or_renamed:
            matches = await self.repo.find_possible_duplicates(
                latitude=final_lat, longitude=final_lng, name=a.name, exclude_id=a.id,
            )
            if matches:
                warnings.append({
                    "code": "possible_duplicate",
                    "message": "Another place with a similar name is within 25 m.",
                    "matches": self._duplicate_payload(matches),
                })
        dup = await self.repo.find_duplicate_by_coordinates(
            final_lat, final_lng, exclude_id=a.id
        )
        full = await self.repo.get_by_id(a.id)
        return AdminPlaceUpdateResult(
            place=self._admin_place(full, has_duplicate=dup is not None),
            warnings=warnings,
        )

    async def change_status(
        self,
        attraction_id: uuid.UUID,
        *,
        target: str,
        reason: Optional[str],
        note: Optional[str],
        admin: str,
    ) -> AdminPlace:
        a = await self._get_or_404(attraction_id)
        try:
            stored_reason = place_status.check_transition(a.status, target, reason, note)
        except place_status.TransitionError as e:
            raise ConflictException(detail=str(e))

        if a.status == target:
            return self._admin_place(a)

        a.status = target
        a.status_reason = stored_reason
        a.status_note = (note or "").strip() or None
        a.reviewed_at = datetime.now(timezone.utc)
        a.reviewed_by = admin
        a = await self.repo.update(a)
        # Committed before telling the other processes, or a reload could
        # still read the old status.
        await self.db.commit()
        await place_visibility.bump()
        full = await self.repo.get_by_id(a.id)
        return self._admin_place(full)

    async def hard_delete(self, attraction_id: uuid.UUID) -> None:
        """Remove a place an admin created by mistake.

        Refused while people's reviews or photos hang off it — hiding keeps
        those intact. Visits are anonymous counts and are kept, unlinked, so
        the Engagement total does not drop.
        """
        a = await self._get_or_404(attraction_id)
        usage = await self.repo.usage_counts(a.id)
        if usage["reviews"] or usage["media"]:
            raise ConflictException(detail={
                "code": "has_user_content",
                "message": "People have added reviews or photos to this place. "
                           "Hide it instead of deleting it.",
                "reviews": usage["reviews"],
                "media": usage["media"],
            })
        await self.db.execute(
            update(PlaceVisit)
            .where(PlaceVisit.attraction_id == a.id)
            .values(attraction_id=None)
        )
        # A Core DELETE: the ORM delete would first lazy-load `reviews` and
        # `media` to unlink them, which async sessions cannot do.
        self.db.expunge(a)
        await self.db.execute(delete(Attraction).where(Attraction.id == attraction_id))
        await self.db.commit()
        await place_visibility.bump()
