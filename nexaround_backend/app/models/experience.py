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
    ARRAY, Boolean, Date, DateTime, ForeignKey, Index, Integer, Numeric, String, Text,
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
    contact_instagram: Mapped[str] = mapped_column(String(255), nullable=True)
    contact_facebook: Mapped[str] = mapped_column(String(500), nullable=True)
    contact_x: Mapped[str] = mapped_column(String(255), nullable=True)
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
    # The vendor's own note, kept apart from `admin_notes` deliberately. That
    # column already holds the admin's private commentary about vendors and
    # travellers, so sharing it would leak the backlog the day the portal ships
    # - and two sides writing one textarea silently clobber each other.
    vendor_notes: Mapped[str] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    def __repr__(self) -> str:
        return f"<ExperienceEnquiry {self.contact_name} -> {self.vendor_name_snapshot}>"


class VendorUser(Base):
    """A login for the partner portal, belonging to exactly one vendor.

    Deliberately NOT a row in `users`, and deliberately not an owner column on
    `ExperienceVendor`.

    Not `users`, because `get_current_user` validates only the signature, that
    `sub` resolves to a `users` row, and `is_active` - no role check and no
    token-type check. A vendor sitting in that table would therefore be handed
    the entire traveller API, `DELETE /api/v1/auth/me` included, and the only
    defence would be a role check retrofitted onto every existing endpoint.
    Keeping the row out of `users` makes the isolation a property of the schema
    rather than of a code path someone can forget. (`users.email` is unique
    too, and a vendor's owner is very likely also a traveller.)

    Not a column on the vendor, because an agency will eventually want an owner
    plus a manager login; `vendor_id` here gives many-to-one for free.
    """

    __tablename__ = "vendor_users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    # Null until the invite is accepted. `verify_password` already returns
    # False for a null hash, so an unaccepted invite simply cannot log in.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str] = mapped_column(String(120), nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    last_login_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # The only way to end sessions other than this one on a password reset: we
    # never hold their jti values, so there is nothing to blacklist. Tokens
    # issued before this moment are refused by `get_current_vendor`.
    password_changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # When this login last opened the portal's notification panel. Activity
    # after it, by anyone but this login, is the bell's unread count. Per
    # login, not per vendor: one teammate reading the feed must not clear it
    # for the others.
    activity_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    def __repr__(self) -> str:
        return f"<VendorUser {self.email}>"


class VendorActivity(Base):
    """One line of a vendor's activity feed: the bell in the partner portal.

    Written in the same transaction as the change it describes, so the feed
    can never claim something that was rolled back, nor miss something that
    was committed.

    `title` and `body` are rendered text, stored rather than rebuilt at read
    time: an enquiry's package or a package's title can change or disappear,
    and the feed should still say what it said when it happened. The actor is
    kept as an id plus a name snapshot for the same reason — the portal shows
    "You" when the id is the viewer's own login.
    """

    __tablename__ = "vendor_activities"
    __table_args__ = (
        # The feed, newest first, and the unread count both read one vendor's
        # rows in time order.
        Index("ix_vendor_activities_vendor_created", "vendor_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="CASCADE"),
        nullable=False,
    )
    # e.g. "enquiry.created", "package.updated"; see app/services/partner_activity.py.
    kind: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(String(500), nullable=True)

    # "traveller", "vendor" or "admin".
    actor: Mapped[str] = mapped_column(String(20), nullable=False)
    actor_login_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("vendor_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    actor_name: Mapped[str] = mapped_column(String(255), nullable=True)

    # What the row links to. SET NULL: the line outlives what it describes.
    enquiry_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_enquiries.id", ondelete="SET NULL"),
        nullable=True,
    )
    package_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_packages.id", ondelete="SET NULL"),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
