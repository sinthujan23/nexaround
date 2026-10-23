"""Data access for the Experiences marketplace.

The one query that matters is `get_nearest_packages`. It is a PostGIS KNN scan
with **no radius ceiling at all**: vendors are sparse at launch, so a traveller
in a city with nothing nearby must still be shown the closest experiences on
earth rather than an empty screen.
"""

import uuid
from typing import Optional, Sequence

from geoalchemy2 import Geography
from geoalchemy2.functions import ST_Distance
from sqlalchemy import func, select, true
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.experience import (
    ExperienceEnquiry, ExperiencePackage, ExperienceReview, ExperienceVendor,
)
from app.services.experience_reviews import PUBLISHED, round_average, summarize
from app.services.ride_apps_service import COUNTRY_NAMES
from app.utils.geo_utils import create_point


class ExperienceRepository:
    def __init__(
        self, db: AsyncSession, hidden_vendor_ids: Sequence[uuid.UUID] = ()
    ):
        """`hidden_vendor_ids`: vendors kept out of every app-facing query, today
        those who have not accepted the Provider Agreement in time
        (legal_service.hidden_vendor_ids). Admin and partner callers pass none."""
        self.db = db
        self.hidden_vendor_ids = list(hidden_vendor_ids)

    def _not_hidden(self):
        """A predicate on the package row alone: an id list, not a join, so the
        KNN query below keeps its single-table plan."""
        if not self.hidden_vendor_ids:
            return true()
        return ExperiencePackage.vendor_id.notin_(self.hidden_vendor_ids)

    async def get_nearest_packages(
        self,
        latitude: float,
        longitude: float,
        category: Optional[str] = None,
        country_code: Optional[str] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[tuple[ExperiencePackage, float]]:
        """Published packages, nearest first, unbounded.

        Two deliberate omissions, both load-bearing:

        * **No `ST_DWithin`.** A distance filter is exactly what would produce
          the empty screen this feature exists to avoid.
        * **No join and no second `ORDER BY` key.** `is_published` is
          denormalised onto the package so this stays a single-table scan, and
          adding a tiebreak column (`id`, `sort_order`) would stack a `Sort`
          node on top of the index scan and throw the KNN plan away. Packages
          sharing an exact coordinate — the normal case, since a vendor's
          packages all copy its point — may therefore reorder between pages.
          At this data scale that is a better trade than a full sort.
        """
        center = func.cast(create_point(latitude, longitude), Geography)
        location = func.geography(ExperiencePackage.location)

        distance = ST_Distance(location, center).label("distance_m")

        query = (
            select(ExperiencePackage, distance)
            .where(
                ExperiencePackage.is_published.is_(True),
                # Country-only vendors have no point; nearest-first cannot rank them.
                ExperiencePackage.location.isnot(None),
                self._not_hidden(),
            )
            .order_by(location.op("<->")(center))
            .offset(offset)
            .limit(limit)
            .options(selectinload(ExperiencePackage.vendor))
        )
        if category:
            query = query.where(ExperiencePackage.category == category)
        if country_code:
            cc = country_code.strip().upper()
            codes = ["LK", "94", "+94"] if cc in ("LK", "94", "+94") else [cc]
            query = query.join(ExperiencePackage.vendor).where(
                func.upper(ExperienceVendor.country_code).in_(codes)
            )

        result = await self.db.execute(query)
        return [(row[0], float(row[1])) for row in result.all()]

    async def get_packages_by_country(
        self,
        category: Optional[str] = None,
        country_code: Optional[str] = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[ExperiencePackage]:
        """Published packages for the by-country list, with no distance.

        Vendor order first (the admin's sort_order), then the package's own,
        then newest; `id` last so paging is stable. Includes vendors with no
        exact location, which is the point of this mode.
        """
        query = (
            select(ExperiencePackage)
            .join(ExperiencePackage.vendor)
            .where(ExperiencePackage.is_published.is_(True), self._not_hidden())
            .order_by(
                ExperienceVendor.sort_order.desc(),
                ExperiencePackage.sort_order.desc(),
                ExperiencePackage.created_at.desc(),
                ExperiencePackage.id,
            )
            .offset(offset)
            .limit(limit)
            .options(selectinload(ExperiencePackage.vendor))
        )
        if category:
            query = query.where(ExperiencePackage.category == category)
        if country_code:
            cc = country_code.strip().upper()
            codes = ["LK", "94", "+94"] if cc in ("LK", "94", "+94") else [cc]
            query = query.where(func.upper(ExperienceVendor.country_code).in_(codes))
        return list((await self.db.execute(query)).scalars().all())

    async def count_published_packages(
        self,
        category: Optional[str] = None,
        country_code: Optional[str] = None,
        located_only: bool = False,
    ) -> int:
        query = select(func.count()).select_from(ExperiencePackage).where(
            ExperiencePackage.is_published.is_(True), self._not_hidden()
        )
        if located_only:
            query = query.where(ExperiencePackage.location.isnot(None))
        if category:
            query = query.where(ExperiencePackage.category == category)
        if country_code:
            cc = country_code.strip().upper()
            codes = ["LK", "94", "+94"] if cc in ("LK", "94", "+94") else [cc]
            query = query.join(ExperiencePackage.vendor).where(
                func.upper(ExperienceVendor.country_code).in_(codes)
            )
        return int((await self.db.execute(query)).scalar() or 0)

    async def get_active_countries(self) -> list[dict]:
        """Returns distinct countries that have active, published packages."""
        query = (
            select(
                ExperienceVendor.country_code,
                func.count(ExperiencePackage.id).label("package_count"),
                func.avg(func.ST_Y(ExperiencePackage.location)).label("avg_lat"),
                func.avg(func.ST_X(ExperiencePackage.location)).label("avg_lng"),
            )
            .join(ExperiencePackage, ExperiencePackage.vendor_id == ExperienceVendor.id)
            .where(
                ExperiencePackage.is_published.is_(True),
                ExperienceVendor.country_code.isnot(None),
                self._not_hidden(),
            )
            .group_by(ExperienceVendor.country_code)
            .order_by(func.count(ExperiencePackage.id).desc())
        )
        result = await self.db.execute(query)
        rows = result.all()
        aggregated: dict[str, dict] = {}
        for code, count, avg_lat, avg_lng in rows:
            if not code:
                continue
            code_upper = code.strip().upper()
            if code_upper in ("94", "+94"):
                code_upper = "LK"
            name = COUNTRY_NAMES.get(code_upper, "Sri Lanka" if code_upper == "LK" else code_upper)
            if code_upper in aggregated:
                aggregated[code_upper]["count"] += count
            else:
                aggregated[code_upper] = {
                    "code": code_upper,
                    "name": name,
                    "count": count,
                    "latitude": float(avg_lat) if avg_lat is not None else None,
                    "longitude": float(avg_lng) if avg_lng is not None else None,
                }
        return sorted(aggregated.values(), key=lambda x: x["count"], reverse=True)

    async def get_package(
        self, package_id: uuid.UUID, published_only: bool = True
    ) -> Optional[ExperiencePackage]:
        query = (
            select(ExperiencePackage)
            .where(ExperiencePackage.id == package_id)
            .options(selectinload(ExperiencePackage.vendor))
        )
        if published_only:
            query = query.where(
                ExperiencePackage.is_published.is_(True), self._not_hidden()
            )
        return (await self.db.execute(query)).scalar_one_or_none()

    async def distance_to(
        self, package: ExperiencePackage, latitude: float, longitude: float
    ) -> Optional[float]:
        """Exact metres from a coordinate to one package."""
        center = func.cast(create_point(latitude, longitude), Geography)
        query = select(
            ST_Distance(func.geography(ExperiencePackage.location), center)
        ).where(ExperiencePackage.id == package.id)
        value = (await self.db.execute(query)).scalar()
        return float(value) if value is not None else None

    async def get_vendor(
        self, vendor_id: uuid.UUID, with_packages: bool = False
    ) -> Optional[ExperienceVendor]:
        query = select(ExperienceVendor).where(ExperienceVendor.id == vendor_id)
        if with_packages:
            query = query.options(selectinload(ExperienceVendor.packages))
        return (await self.db.execute(query)).scalar_one_or_none()

    async def list_vendors(
        self,
        search: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 50,
    ) -> tuple[list[ExperienceVendor], int]:
        query = select(ExperienceVendor)
        count_query = select(func.count()).select_from(ExperienceVendor)

        if search:
            clause = ExperienceVendor.name.ilike(f"%{search}%")
            query = query.where(clause)
            count_query = count_query.where(clause)
        if is_active is not None:
            query = query.where(ExperienceVendor.is_active.is_(is_active))
            count_query = count_query.where(ExperienceVendor.is_active.is_(is_active))

        total = int((await self.db.execute(count_query)).scalar() or 0)
        query = (
            query.order_by(
                ExperienceVendor.sort_order.desc(), ExperienceVendor.created_at.desc()
            )
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        rows = list((await self.db.execute(query)).scalars().all())
        return rows, total

    async def list_packages_for_vendor(
        self, vendor_id: uuid.UUID
    ) -> list[ExperiencePackage]:
        query = (
            select(ExperiencePackage)
            .where(ExperiencePackage.vendor_id == vendor_id)
            .order_by(
                ExperiencePackage.sort_order.desc(), ExperiencePackage.created_at.desc()
            )
        )
        return list((await self.db.execute(query)).scalars().all())

    async def list_enquiries(
        self,
        status: Optional[str] = None,
        vendor_id: Optional[uuid.UUID] = None,
        page: int = 1,
        page_size: int = 50,
    ) -> tuple[list[ExperienceEnquiry], int]:
        query = select(ExperienceEnquiry)
        count_query = select(func.count()).select_from(ExperienceEnquiry)

        if status:
            query = query.where(ExperienceEnquiry.status == status)
            count_query = count_query.where(ExperienceEnquiry.status == status)
        if vendor_id:
            query = query.where(ExperienceEnquiry.vendor_id == vendor_id)
            count_query = count_query.where(ExperienceEnquiry.vendor_id == vendor_id)

        total = int((await self.db.execute(count_query)).scalar() or 0)
        query = (
            query.order_by(ExperienceEnquiry.created_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        rows = list((await self.db.execute(query)).scalars().all())
        return rows, total

    # ── Partner portal: scope lives in the query ────────────────────────────
    #
    # These exist so no partner endpoint has to fetch a row and then remember
    # to compare its vendor_id. That pattern is correct the day it is written
    # and rots the moment someone copies the fetch without the comparison; a
    # query that cannot return another vendor's row has no such failure mode.

    async def get_package_for_vendor(
        self, package_id: uuid.UUID, vendor_id: uuid.UUID
    ) -> Optional[ExperiencePackage]:
        """One package, only if this vendor owns it. None otherwise."""
        query = select(ExperiencePackage).where(
            ExperiencePackage.id == package_id,
            ExperiencePackage.vendor_id == vendor_id,
        )
        return (await self.db.execute(query)).scalar_one_or_none()

    async def vendor_stats(self, vendor_id: uuid.UUID) -> dict:
        """Counts for the portal's dashboard, scoped to one vendor: packages,
        and requests still waiting for the vendor's answer."""
        from app.models.experience import ExperienceEnquiry
        from app.services import enquiry_lifecycle

        pkg = select(
            func.count().label("total"),
            func.count().filter(ExperiencePackage.is_published.is_(True)).label("live"),
        ).select_from(ExperiencePackage).where(
            ExperiencePackage.vendor_id == vendor_id
        )
        pkg_row = (await self.db.execute(pkg)).one()
        waiting = await self.db.scalar(
            select(func.count()).select_from(ExperienceEnquiry).where(
                ExperienceEnquiry.vendor_id == vendor_id,
                ExperienceEnquiry.status.in_(enquiry_lifecycle.VENDOR_CAN_RESPOND),
                ExperienceEnquiry.vendor_response.is_(None),
            )
        )

        return {
            "packages_total": int(pkg_row.total or 0),
            "packages_published": int(pkg_row.live or 0),
            "requests_waiting": int(waiting or 0),
        }


    # ── Reviews ──────────────────────────────────────────────────────────────
    # Only published reviews count anywhere a traveller can see a number: a
    # hidden review leaves the average, the count and the list together.

    async def rating_summaries(
        self, package_ids: Sequence[uuid.UUID]
    ) -> dict[uuid.UUID, tuple[Optional[float], int]]:
        """`{package_id: (average, count)}` for the packages that have a review.
        One grouped query for a whole page of cards."""
        if not package_ids:
            return {}
        rows = (await self.db.execute(
            select(
                ExperienceReview.package_id,
                func.count(),
                func.sum(ExperienceReview.rating),
            )
            .where(
                ExperienceReview.package_id.in_(list(package_ids)),
                ExperienceReview.status == PUBLISHED,
            )
            .group_by(ExperienceReview.package_id)
        )).all()
        return {pid: (round_average(float(total), int(n)), int(n)) for pid, n, total in rows}

    async def vendor_rating_summaries(
        self, vendor_ids: Sequence[uuid.UUID]
    ) -> dict[uuid.UUID, tuple[Optional[float], int]]:
        """The same, per provider, across all of its packages."""
        if not vendor_ids:
            return {}
        rows = (await self.db.execute(
            select(
                ExperienceReview.vendor_id,
                func.count(),
                func.sum(ExperienceReview.rating),
            )
            .where(
                ExperienceReview.vendor_id.in_(list(vendor_ids)),
                ExperienceReview.status == PUBLISHED,
            )
            .group_by(ExperienceReview.vendor_id)
        )).all()
        return {vid: (round_average(float(total), int(n)), int(n)) for vid, n, total in rows}

    async def package_review_summary(self, package_id: uuid.UUID) -> dict:
        """Average, count and the 1-5 breakdown for one package."""
        rows = (await self.db.execute(
            select(ExperienceReview.rating, func.count())
            .where(
                ExperienceReview.package_id == package_id,
                ExperienceReview.status == PUBLISHED,
            )
            .group_by(ExperienceReview.rating)
        )).all()
        return summarize([rating for rating, n in rows for _ in range(int(n))])

    async def list_package_reviews(
        self, package_id: uuid.UUID, limit: int, offset: int
    ) -> list[ExperienceReview]:
        return list((await self.db.execute(
            select(ExperienceReview)
            .where(
                ExperienceReview.package_id == package_id,
                ExperienceReview.status == PUBLISHED,
            )
            .order_by(ExperienceReview.created_at.desc())
            .limit(limit)
            .offset(offset)
        )).scalars().all())

    async def reviews_by_user(
        self, user_id: uuid.UUID, package_ids: Sequence[uuid.UUID]
    ) -> dict[uuid.UUID, ExperienceReview]:
        """One traveller's own reviews of these packages, by package. A hidden
        review is still theirs: they see it as theirs."""
        if not package_ids:
            return {}
        rows = (await self.db.execute(
            select(ExperienceReview).where(
                ExperienceReview.user_id == user_id,
                ExperienceReview.package_id.in_(list(package_ids)),
            )
        )).scalars().all()
        return {r.package_id: r for r in rows}

    async def get_user_review(
        self, user_id: uuid.UUID, package_id: uuid.UUID
    ) -> Optional[ExperienceReview]:
        return (await self.db.execute(
            select(ExperienceReview).where(
                ExperienceReview.user_id == user_id,
                ExperienceReview.package_id == package_id,
            )
        )).scalar_one_or_none()

    async def get_review_for_vendor(
        self, review_id: uuid.UUID, vendor_id: uuid.UUID
    ) -> Optional[ExperienceReview]:
        """One published review, only if it is on this vendor's package. A hidden
        review is not the vendor's to see or answer."""
        return (await self.db.execute(
            select(ExperienceReview).where(
                ExperienceReview.id == review_id,
                ExperienceReview.vendor_id == vendor_id,
                ExperienceReview.status == PUBLISHED,
            )
        )).scalar_one_or_none()

    async def list_reviews_for_vendor(
        self,
        vendor_id: uuid.UUID,
        *,
        unanswered_only: bool = False,
        page: int = 1,
        page_size: int = 25,
    ) -> tuple[list[ExperienceReview], int]:
        """A vendor's published reviews, newest first, and how many there are."""
        conditions = [
            ExperienceReview.vendor_id == vendor_id,
            ExperienceReview.status == PUBLISHED,
        ]
        if unanswered_only:
            conditions.append(ExperienceReview.vendor_reply.is_(None))
        total = (await self.db.execute(
            select(func.count()).select_from(ExperienceReview).where(*conditions)
        )).scalar() or 0
        rows = (await self.db.execute(
            select(ExperienceReview)
            .where(*conditions)
            .order_by(ExperienceReview.created_at.desc())
            .limit(page_size)
            .offset((page - 1) * page_size)
        )).scalars().all()
        return list(rows), int(total)

    async def list_reviews_admin(
        self,
        *,
        status: Optional[str] = None,
        package_id: Optional[uuid.UUID] = None,
        vendor_id: Optional[uuid.UUID] = None,
        rating: Optional[int] = None,
        page: int = 1,
        page_size: int = 25,
    ) -> tuple[list[ExperienceReview], int]:
        conditions = []
        if status:
            conditions.append(ExperienceReview.status == status)
        if package_id:
            conditions.append(ExperienceReview.package_id == package_id)
        if vendor_id:
            conditions.append(ExperienceReview.vendor_id == vendor_id)
        if rating:
            conditions.append(ExperienceReview.rating == rating)
        total = (await self.db.execute(
            select(func.count()).select_from(ExperienceReview).where(*conditions)
        )).scalar() or 0
        rows = (await self.db.execute(
            select(ExperienceReview)
            .where(*conditions)
            .order_by(ExperienceReview.created_at.desc())
            .limit(page_size)
            .offset((page - 1) * page_size)
        )).scalars().all()
        return list(rows), int(total)

    async def get_review(self, review_id: uuid.UUID) -> Optional[ExperienceReview]:
        return (await self.db.execute(
            select(ExperienceReview).where(ExperienceReview.id == review_id)
        )).scalar_one_or_none()
