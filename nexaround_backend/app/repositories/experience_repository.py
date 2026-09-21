"""Data access for the Experiences marketplace.

The one query that matters is `get_nearest_packages`. It is a PostGIS KNN scan
with **no radius ceiling at all**: vendors are sparse at launch, so a traveller
in a city with nothing nearby must still be shown the closest experiences on
earth rather than an empty screen.
"""

import uuid
from typing import Optional

from geoalchemy2 import Geography
from geoalchemy2.functions import ST_Distance
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.experience import (
    ExperienceEnquiry, ExperiencePackage, ExperienceVendor,
)
from app.utils.geo_utils import create_point


class ExperienceRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_nearest_packages(
        self,
        latitude: float,
        longitude: float,
        category: Optional[str] = None,
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
            .where(ExperiencePackage.is_published.is_(True))
            .order_by(location.op("<->")(center))
            .offset(offset)
            .limit(limit)
            .options(selectinload(ExperiencePackage.vendor))
        )
        if category:
            query = query.where(ExperiencePackage.category == category)

        result = await self.db.execute(query)
        return [(row[0], float(row[1])) for row in result.all()]

    async def count_published_packages(self, category: Optional[str] = None) -> int:
        query = select(func.count()).select_from(ExperiencePackage).where(
            ExperiencePackage.is_published.is_(True)
        )
        if category:
            query = query.where(ExperiencePackage.category == category)
        return int((await self.db.execute(query)).scalar() or 0)

    async def get_package(
        self, package_id: uuid.UUID, published_only: bool = True
    ) -> Optional[ExperiencePackage]:
        query = (
            select(ExperiencePackage)
            .where(ExperiencePackage.id == package_id)
            .options(selectinload(ExperiencePackage.vendor))
        )
        if published_only:
            query = query.where(ExperiencePackage.is_published.is_(True))
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
