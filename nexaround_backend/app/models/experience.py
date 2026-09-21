"""Vendor-supplied experiences: the first-party marketplace layer.

Everything else in Discovery is a Google Places row cached into `attractions` —
owned by nobody, sellable by nobody. These three tables are the opposite: rows
an admin types in, attached to a real agency the client has signed, which a
traveller can enquire about.

The shape that matters is `ExperiencePackage.location`. Discovery lists one card
per *package*, so the nearest-first query has to sort packages by distance. That
sort is a PostGIS KNN scan over a GiST index, and an index only exists on a real
column — sorting by the vendor's point through a join would throw the index away
and degrade to a full scan plus sort as soon as the vendor table grows. So the
vendor's point is copied onto every package it owns, and `uses_vendor_location`
records whether the copy still tracks the vendor (the common case) or the admin
has given this one package its own meeting point.
"""

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    ARRAY, Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String, Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geometry

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ExperienceVendor(Base):
    """An agency the client has signed: boat rides, guided tours, water sports."""

    __tablename__ = "experience_vendors"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)

    # Positioned by the admin through Google location search. PostGIS POINT,
    # SRID 4326 — the same convention as `attractions.location`.
    location = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False
    )
    address: Mapped[str] = mapped_column(String(500), nullable=True)
    google_place_id: Mapped[str] = mapped_column(String(255), nullable=True, index=True)
    city: Mapped[str] = mapped_column(String(120), nullable=True)
    country_code: Mapped[str] = mapped_column(String(2), nullable=True)

    contact_phone: Mapped[str] = mapped_column(String(32), nullable=True)
    contact_whatsapp: Mapped[str] = mapped_column(String(32), nullable=True)
    contact_email: Mapped[str] = mapped_column(String(255), nullable=True)
    website: Mapped[str] = mapped_column(String(500), nullable=True)

    logo_url: Mapped[str] = mapped_column(String(500), nullable=True)
    photo_urls: Mapped[list] = mapped_column(ARRAY(String), default=list)

    rating: Mapped[float] = mapped_column(Numeric(3, 2), nullable=True)
    review_count: Mapped[int] = mapped_column(Integer, default=0)

    # Admin-only. Never included in any app-facing schema.
    internal_notes: Mapped[str] = mapped_column(Text, nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    packages = relationship(
        "ExperiencePackage",
        back_populates="vendor",
        lazy="select",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    def __repr__(self) -> str:
        return f"<ExperienceVendor {self.name}>"


class ExperiencePackage(Base):
    """One sellable thing: "Sunset Boat Ride, 2 hours, LKR 4,500 per person"."""

    __tablename__ = "experience_packages"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    title: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    summary: Mapped[str] = mapped_column(String(500), nullable=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)

    # Drives the sub-category chips on the Experiences tab.
    category: Mapped[str] = mapped_column(String(60), nullable=True, index=True)
    tags: Mapped[list] = mapped_column(ARRAY(String), default=list)
    photo_urls: Mapped[list] = mapped_column(ARRAY(String), default=list)

    # Numeric, not Float: this is money and it is displayed verbatim.
    price_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=True)
    price_currency: Mapped[str] = mapped_column(String(10), default="LKR")
    # per_person | per_group | from
    price_basis: Mapped[str] = mapped_column(String(20), default="per_person")

    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=True)
    max_participants: Mapped[int] = mapped_column(Integer, nullable=True)
    inclusions: Mapped[list] = mapped_column(ARRAY(String), default=list)
    languages: Mapped[list] = mapped_column(ARRAY(String), default=list)

    # Denormalised from the vendor — see the module docstring. NOT NULL, because
    # the nearest-first query sorts on it and a NULL here would drop the package
    # out of Discovery entirely.
    location = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False
    )
    uses_vendor_location: Mapped[bool] = mapped_column(Boolean, default=True)
    meeting_point_address: Mapped[str] = mapped_column(String(500), nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    # Derived: vendor.is_active AND package.is_active, recomputed by the service
    # on any vendor or package save. Denormalised for the same reason as
    # `location` — it lets the Discovery query be a single-table partial index
    # scan with no join predicate, which is what keeps the KNN plan.
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)

    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    vendor = relationship("ExperienceVendor", back_populates="packages", lazy="select")

    def __repr__(self) -> str:
        return f"<ExperiencePackage {self.title}>"


class ExperienceEnquiry(Base):
    """A traveller asking a vendor about a package.

    Both foreign keys are nullable and mirrored by `*_snapshot` columns: an
    enquiry is a record of demand the client shows vendors during negotiation,
    so deleting a package must not delete the evidence that people wanted it.
    """

    __tablename__ = "experience_enquiries"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    package_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_packages.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True
    )

    package_title_snapshot: Mapped[str] = mapped_column(String(255), nullable=True)
    vendor_name_snapshot: Mapped[str] = mapped_column(String(255), nullable=True)

    contact_name: Mapped[str] = mapped_column(String(120), nullable=False)
    contact_phone: Mapped[str] = mapped_column(String(32), nullable=False)
    contact_email: Mapped[str] = mapped_column(String(255), nullable=True)
    preferred_date: Mapped[date] = mapped_column(Date, nullable=True)
    party_size: Mapped[int] = mapped_column(Integer, nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=True)

    # new | contacted | closed
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)
    admin_notes: Mapped[str] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    def __repr__(self) -> str:
        return f"<ExperienceEnquiry {self.contact_name} -> {self.vendor_name_snapshot}>"
