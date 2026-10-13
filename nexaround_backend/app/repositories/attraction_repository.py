import uuid
from typing import List, Optional, Tuple
from sqlalchemy import select, func, desc, or_, cast, String, text
from sqlalchemy.dialects.postgresql import ARRAY as PG_ARRAY
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload, aliased
from app.utils.geo_utils import get_lat_lng
from geoalchemy2 import Geometry, Geography
from geoalchemy2.functions import ST_Distance, ST_DWithin
from app.models.attraction import Attraction, AttractionAlias
from app.models.category import Category
from app.utils.geo_utils import create_point
from app.utils.place_match import haversine_m, names_match


# ~33 m. Wide enough that a 25 m "same place" match at the edge of a seed
# batch still sees the tombstone.
_TOMBSTONE_PAD_DEG = 0.0003

# Columns the admin list can sort by, keyed by the API's `sort` value.
_ADMIN_SORTS = {
    "newest": lambda: (desc(Attraction.created_at),),
    "oldest": lambda: (Attraction.created_at,),
    "name": lambda: (func.lower(Attraction.name),),
    "updated": lambda: (desc(Attraction.updated_at),),
    # The Review queue: people's suggestions before old leftover copies,
    # each oldest first.
    "queue": lambda: (
        (Attraction.source != "user"),
        Attraction.created_at,
    ),
}


class AttractionRepository:
    """Data access layer for Attraction operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, attraction_id: uuid.UUID) -> Optional[Attraction]:
        """Get an attraction by its UUID."""
        result = await self.db.execute(
            select(Attraction)
            .where(Attraction.id == attraction_id)
            .options(selectinload(Attraction.category))
        )
        return result.scalar_one_or_none()

    async def find_by_google_place_id(
        self, google_place_id: str
    ) -> Optional[Attraction]:
        """The row for an upstream place, if we already hold it.

        Preferred over a coordinate match when seeding: it is the identity
        Google itself uses, so it still matches after a place's coordinates are
        nudged by a few metres between refreshes — which a 0.000001-degree
        coordinate comparison does not.
        """
        stmt = (
            select(Attraction)
            .where(Attraction.google_place_id == google_place_id)
            .order_by(Attraction.is_active.desc())
            .limit(1)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def find_existing_for_seed(
        self,
        *,
        min_lat: float,
        min_lng: float,
        max_lat: float,
        max_lng: float,
        google_place_ids: List[str],
    ) -> Tuple[dict, dict]:
        """Every row a seed batch might already hold, in two queries.

        Returns `(by_google_place_id, by_rounded_coordinate)` so the caller can
        match each incoming place in memory instead of asking the database twice
        per place. Sixty places used to mean ~120 sequential round trips holding
        a pooled connection for the duration — see `get_coordinates_in_bounds`,
        which makes the same argument for the coordinate check alone.

        Coordinates are rounded to six decimals to agree with the < 1e-6
        tolerance `find_duplicate_by_coordinates` applies.

        The third element lists hidden and rejected rows within ~30 m of the
        batch as `(lat, lng, name, row)`. A Google result a few metres from a
        rejected place, under a similar name, is that place again, so the
        seeder must not insert it as a fresh live row.
        """
        by_gid: dict = {}
        if google_place_ids:
            res = await self.db.execute(
                select(Attraction).where(
                    Attraction.google_place_id.in_(google_place_ids)
                ).order_by(Attraction.is_active.desc())
            )
            for row in res.scalars().all():
                # First wins, and actives are ordered first — same preference
                # find_by_google_place_id applies.
                by_gid.setdefault(row.google_place_id, row)

        res = await self.db.execute(
            select(Attraction).where(
                func.ST_Y(Attraction.location).between(min_lat, max_lat),
                func.ST_X(Attraction.location).between(min_lng, max_lng),
            ).order_by(Attraction.is_active.desc())
        )
        by_coord: dict = {}
        for row in res.scalars().all():
            lat, lng = get_lat_lng(row.location)
            by_coord.setdefault((round(lat, 6), round(lng, 6)), row)

        pad = _TOMBSTONE_PAD_DEG
        res = await self.db.execute(
            select(Attraction).where(
                Attraction.status.in_(("hidden", "rejected")),
                func.ST_Y(Attraction.location).between(min_lat - pad, max_lat + pad),
                func.ST_X(Attraction.location).between(min_lng - pad, max_lng + pad),
            )
        )
        tombstones = []
        for row in res.scalars().all():
            lat, lng = get_lat_lng(row.location)
            tombstones.append((lat, lng, row.name, row))

        return by_gid, by_coord, tombstones

    async def find_duplicate_by_coordinates(
        self, 
        latitude: float, 
        longitude: float, 
        exclude_id: Optional[uuid.UUID] = None
    ) -> Optional[Attraction]:
        """Find an existing attraction with the same coordinates (within a very small tolerance)."""
        stmt = select(Attraction).where(
            func.abs(func.ST_X(Attraction.location) - longitude) < 0.000001,
            func.abs(func.ST_Y(Attraction.location) - latitude) < 0.000001
        )
        if exclude_id:
            stmt = stmt.where(Attraction.id != exclude_id)
        stmt = stmt.limit(1)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def list_attractions(
        self, 
        skip: int = 0, 
        limit: int = 20, 
        category_id: Optional[uuid.UUID] = None,
        search_query: Optional[str] = None,
        is_active: Optional[bool] = None
    ) -> Tuple[List[Tuple[Attraction, bool]], int]:
        """Get a list of attractions with optional filtering, search, and duplicate status."""
        alias = aliased(Attraction)
        
        # Subquery to check duplicate coordinates (distance < 0.000001 degrees ~ 11cm)
        dup_exists = select(1).select_from(alias).where(
            alias.id != Attraction.id,
            func.ST_DWithin(alias.location, Attraction.location, 0.000001)
        ).exists()
        
        query = select(Attraction, dup_exists.label("has_duplicate")).options(selectinload(Attraction.category))
        
        if is_active is not None:
            query = query.where(Attraction.is_active == is_active)
        
        if category_id:
            query = query.where(Attraction.category_id == category_id)
        
        if search_query:
            query = query.where(
                or_(
                    Attraction.name.ilike(f"%{search_query}%"),
                    Attraction.description.ilike(f"%{search_query}%")
                )
            )
            
        # Get total count
        count_query = select(func.count()).select_from(query.subquery())
        total = await self.db.scalar(count_query) or 0
        
        # Get actual results
        results = await self.db.execute(
            query.order_by(Attraction.name, Attraction.id).offset(skip).limit(limit)
        )
        return [(row[0], bool(row[1])) for row in results.all()], total

    def _admin_filters(
        self,
        *,
        q: Optional[str] = None,
        source: Optional[str] = None,
        reason: Optional[str] = None,
        category_id: Optional[uuid.UUID] = None,
        submitted_by: Optional[uuid.UUID] = None,
        possible_duplicate: bool = False,
    ) -> list:
        """WHERE clauses shared by the admin list and its per-status counts."""
        clauses = []
        if q:
            like = f"%{q.strip()}%"
            clauses.append(or_(Attraction.name.ilike(like), Attraction.address.ilike(like)))
        if source:
            clauses.append(Attraction.source == source)
        if reason:
            clauses.append(Attraction.status_reason == reason)
        if category_id:
            clauses.append(Attraction.category_id == category_id)
        if submitted_by:
            clauses.append(Attraction.submitted_by_user_id == submitted_by)
        if possible_duplicate:
            clauses.append(self._duplicate_exists())
        return clauses

    @staticmethod
    def _duplicate_exists():
        """Another row of any status at the same coordinates (~11 cm)."""
        other = aliased(Attraction)
        return select(1).select_from(other).where(
            other.id != Attraction.id,
            func.ST_DWithin(other.location, Attraction.location, 0.000001),
        ).exists()

    async def admin_list(
        self,
        *,
        status: str,
        sort: str = "newest",
        offset: int = 0,
        limit: int = 50,
        **filters,
    ) -> Tuple[List[Tuple[Attraction, bool]], int]:
        """One page of places in one status, for the admin panel.

        Always ordered, with `id` last, so paging never repeats or skips a row.
        """
        clauses = self._admin_filters(**filters)
        base = select(Attraction).where(Attraction.status == status, *clauses)
        total = await self.db.scalar(
            select(func.count()).select_from(base.subquery())
        ) or 0
        order = _ADMIN_SORTS.get(sort, _ADMIN_SORTS["newest"])()
        query = (
            select(Attraction, self._duplicate_exists().label("has_duplicate"))
            .where(Attraction.status == status, *clauses)
            .options(selectinload(Attraction.category))
            .order_by(*order, Attraction.id)
            .offset(offset)
            .limit(limit)
        )
        rows = (await self.db.execute(query)).all()
        return [(r[0], bool(r[1])) for r in rows], total

    async def status_counts(self, **filters) -> dict:
        """How many places sit in each status, under the same filters."""
        clauses = self._admin_filters(**filters)
        rows = (await self.db.execute(
            select(Attraction.status, func.count())
            .where(*clauses)
            .group_by(Attraction.status)
        )).all()
        counts = {"live": 0, "pending": 0, "hidden": 0, "rejected": 0}
        counts.update({status: n for status, n in rows})
        return counts

    async def count_pending_from_users(self) -> int:
        return await self.db.scalar(
            select(func.count()).select_from(Attraction).where(
                Attraction.status == "pending", Attraction.source == "user"
            )
        ) or 0

    async def count_pending_by_user(self, user_id: uuid.UUID) -> int:
        return await self.db.scalar(
            select(func.count()).select_from(Attraction).where(
                Attraction.status == "pending",
                Attraction.submitted_by_user_id == user_id,
            )
        ) or 0

    async def find_possible_duplicates(
        self,
        *,
        latitude: float,
        longitude: float,
        name: str,
        google_place_id: Optional[str] = None,
        exclude_id: Optional[uuid.UUID] = None,
        radius_m: float = 25.0,
    ) -> List[Tuple[Attraction, float]]:
        """Rows that look like the same place: the same Google id, or within
        `radius_m` under a similar name. Rejected rows count — creating a place
        an admin already turned down deserves the same warning."""
        rows = await self.nearby_any_status(
            latitude=latitude, longitude=longitude, radius_m=radius_m,
            exclude_id=exclude_id, limit=50,
        )
        matches = [(a, d) for a, d in rows if names_match(a.name, name)]
        if google_place_id:
            seen = {a.id for a, _ in matches}
            res = await self.db.execute(
                select(Attraction).where(
                    Attraction.google_place_id == google_place_id,
                    *([Attraction.id != exclude_id] if exclude_id else []),
                ).options(selectinload(Attraction.category))
            )
            for a in res.scalars().all():
                if a.id not in seen:
                    alat, alng = get_lat_lng(a.location)
                    matches.append((a, haversine_m(latitude, longitude, alat, alng)))
        return matches

    async def nearby_any_status(
        self,
        *,
        latitude: float,
        longitude: float,
        radius_m: float,
        exclude_id: Optional[uuid.UUID] = None,
        limit: int = 30,
    ) -> List[Tuple[Attraction, float]]:
        """Every row near a point whatever its status, nearest first — what an
        admin needs to see before approving or creating a place there."""
        center = func.cast(create_point(latitude, longitude), Geography)
        distance = ST_Distance(func.geography(Attraction.location), center)
        query = (
            select(Attraction, distance.label("distance"))
            .where(ST_DWithin(func.geography(Attraction.location), center, radius_m))
            .options(selectinload(Attraction.category))
            .order_by("distance")
            .limit(limit)
        )
        if exclude_id:
            query = query.where(Attraction.id != exclude_id)
        rows = (await self.db.execute(query)).all()
        return [(r[0], r[1]) for r in rows]

    async def usage_counts(self, attraction_id: uuid.UUID) -> dict:
        """User content tied to a place, which decides whether it may be deleted."""
        row = (await self.db.execute(text("""
            SELECT
                (SELECT count(*) FROM reviews WHERE attraction_id = :id),
                (SELECT count(*) FROM media WHERE attraction_id = :id),
                (SELECT count(*) FROM place_visits WHERE attraction_id = :id)
        """), {"id": attraction_id})).one()
        return {"reviews": row[0], "media": row[1], "visits": row[2]}

    async def resolve_alias(self, attraction_id: uuid.UUID) -> Optional[uuid.UUID]:
        """The id a merged copy now resolves to, if `attraction_id` was one."""
        return await self.db.scalar(
            select(AttractionAlias.attraction_id).where(
                AttractionAlias.old_id == attraction_id
            )
        )

    async def get_coordinates_in_bounds(
        self,
        min_lat: float,
        min_lng: float,
        max_lat: float,
        max_lng: float,
    ) -> set:
        """Coordinates of every attraction inside a bounding box.

        The duplicate check when seeding used to run find_duplicate_by_coordinates
        once per incoming place, which is one database round trip each — sixty
        places meant sixty queries. This pulls the same information in one, and
        the caller matches in memory.

        Rounded to six decimals to match the tolerance find_duplicate_by_coordinates
        applies (< 1e-6), so the two agree on what counts as the same spot.
        """
        stmt = select(
            func.ST_Y(Attraction.location),
            func.ST_X(Attraction.location),
        ).where(
            func.ST_Y(Attraction.location).between(min_lat, max_lat),
            func.ST_X(Attraction.location).between(min_lng, max_lng),
        )
        result = await self.db.execute(stmt)
        return {(round(lat, 6), round(lng, 6)) for lat, lng in result.all()}

    async def get_nearby(
        self,
        latitude: float,
        longitude: float,
        radius_m: float,
        category_id: Optional[uuid.UUID] = None,
        limit: int = 50,
        order_by_prominence: bool = False,
        sort_by_away: bool = False,
        visible_only: bool = True,
        min_radius_m: Optional[float] = None,
        category_ids: Optional[List[uuid.UUID]] = None,
        any_tags: Optional[List[str]] = None,
        any_name_ilike: Optional[List[str]] = None
    ) -> List[Tuple[Attraction, float]]:
        """Get attractions within a certain radius, with distance calculation.

        Live places only unless `visible_only=False`. That is meant for
        de-duplication against everything we hold, never for a list a user
        sees; defaulting to safe is what keeps a new caller from leaking hidden
        places, as three callers did when the default was "everything".
        """
        center_point = create_point(latitude, longitude)
        
        # ST_Distance returns distance in degrees for 4326 unless we use geography
        # But we want meters. ST_Distance(geography(location), geography(point))
        # Or just use the model field if it's geography. Our model is Geometry(4326).
        distance_func = ST_Distance(
            func.geography(Attraction.location), 
            func.cast(center_point, Geography)
        )
        
        query = select(Attraction, distance_func.label("distance")).where(
            ST_DWithin(
                func.geography(Attraction.location),
                func.cast(center_point, Geography),
                radius_m
            )
        ).options(selectinload(Attraction.category))
        
        if min_radius_m is not None:
            query = query.where(distance_func >= min_radius_m)
            
        if visible_only:
            query = query.where(Attraction.status == "live")
            
        if category_id:
            query = query.where(Attraction.category_id == category_id)

        # POI absorbed the older 'Attractions'/'Nature'/'Experiences' categories,
        # so a band query has to match every name a place may have been seeded
        # under or most of the existing rows stay invisible to it.
        if category_ids:
            query = query.where(Attraction.category_id.in_(category_ids))

        # Relevance pre-filter, applied before the row limit.
        #
        # Several sections read from one shared pool — Nature's rows sit among
        # POI's, Medical's among Hospital's. Judging relevance only in Python
        # meant `limit` was spent on rows that were then thrown away: in a
        # temple-dense area the forty nearest rows were all temples, so Nature
        # came back with one place while a hundred more sat unexamined further
        # down. Filtering here makes the limit count rows that could plausibly
        # belong. Python still has the final say — this net is deliberately
        # looser than `is_relevant`, never tighter.
        if any_tags or any_name_ilike:
            clauses = []
            if any_tags:
                # `tags` is declared with SQLAlchemy's generic ARRAY, which has
                # no .overlap(); cast to the Postgres type to reach `&&`.
                clauses.append(
                    Attraction.tags.op("&&")(cast(any_tags, PG_ARRAY(String)))
                )
            for pattern in (any_name_ilike or []):
                clauses.append(Attraction.name.ilike(pattern))
            query = query.where(or_(*clauses))


        if order_by_prominence:
            # Most-visited first, then best-rated, then nearest.
            #
            # `limit` is applied after this, so the ordering decides which rows
            # survive at all — ordering by distance meant a band took its
            # nearest N and a well-known place just outside that cut never
            # reached the ranking downstream. Review count leads because it is
            # evidence of what people actually go to, where rating alone is
            # thin: five reviews at 5.0 outrank a landmark at 4.6.
            query = query.order_by(
                desc(Attraction.review_count),
                desc(Attraction.rating),
                desc("distance") if sort_by_away else "distance",
            )
        elif min_radius_m is not None:
            query = query.order_by(desc(Attraction.rating), desc("distance") if sort_by_away else "distance")
        else:
            if sort_by_away:
                query = query.order_by(desc("distance"))
            else:
                query = query.order_by("distance")

        query = query.limit(limit)
        
        results = await self.db.execute(query)
        return [(row[0], row[1]) for row in results.all()]

    async def create(self, attraction: Attraction) -> Attraction:
        self.db.add(attraction)
        await self.db.flush()
        await self.db.refresh(attraction)
        return attraction

    async def update(self, attraction: Attraction) -> Attraction:
        await self.db.flush()
        await self.db.refresh(attraction)
        return attraction

    async def delete(self, attraction: Attraction) -> None:
        await self.db.delete(attraction)
        await self.db.flush()

    async def search_by_name(
        self,
        name: str,
        latitude: float,
        longitude: float,
        radius_m: float = 50000.0,
        limit: int = 5,
    ) -> List[Tuple[Attraction, float]]:
        """Search attractions by name (ILIKE fuzzy match) within a radius.

        Used by the trending resolution flow to check the local DB before
        calling Google Text Search, saving API costs.
        """
        center_point = create_point(latitude, longitude)
        distance_func = ST_Distance(
            func.geography(Attraction.location),
            func.cast(center_point, Geography),
        )

        query = (
            select(Attraction, distance_func.label("distance"))
            .where(
                ST_DWithin(
                    func.geography(Attraction.location),
                    func.cast(center_point, Geography),
                    radius_m,
                ),
                Attraction.status == "live",
                Attraction.name.ilike(f"%{name}%"),
            )
            .options(selectinload(Attraction.category))
            .order_by("distance")
            .limit(limit)
        )
        results = await self.db.execute(query)
        return [(row[0], row[1]) for row in results.all()]
