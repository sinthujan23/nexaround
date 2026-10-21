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
from typing import Optional

from sqlalchemy import (
    ARRAY, Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, Numeric, SmallInteger,
    String, Text, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geometry

from app.core.database import Base
from app.services import enquiry_lifecycle


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
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True
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
    # Uploaded clips, served from `/api/v1/experiences/videos/`. Added by the
    # admin panel; the partner portal neither sets nor clears it.
    video_urls: Mapped[list] = mapped_column(
        ARRAY(String), default=list, server_default="{}"
    )

    # Dates this package cannot be booked, as inclusive ISO ranges:
    # [{"start": "2026-11-01", "end": "2026-11-05"}]. Empty means available
    # every day. Kept merged and sorted by `merge_date_ranges`.
    unavailable_ranges: Mapped[list] = mapped_column(
        JSONB, default=list, server_default="[]"
    )

    # Numeric, not Float: this is money and it is displayed verbatim.
    # The vendor's own price, in the vendor's currency.
    price_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=True)
    price_currency: Mapped[str] = mapped_column(String(10), default="LKR")
    # The same price in US dollars, typed by the admin and shown in brackets
    # ("QAR 499 ($137)"). Never converted: both figures carry the commission,
    # and a daily rate would move it. Admin panel only; NULL shows no bracket.
    price_usd: Mapped[float] = mapped_column(Numeric(12, 2), nullable=True)
    # per_person | per_group | from
    price_basis: Mapped[str] = mapped_column(String(20), default="per_person")

    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=True)
    max_participants: Mapped[int] = mapped_column(Integer, nullable=True)
    # How many days ahead a traveller may ask for a date, set by the vendor or
    # the admin. NULL means the platform default
    # (experience_format.DEFAULT_BOOKING_WINDOW_DAYS).
    booking_window_days: Mapped[int] = mapped_column(Integer, nullable=True)
    inclusions: Mapped[list] = mapped_column(ARRAY(String), default=list)
    languages: Mapped[list] = mapped_column(ARRAY(String), default=list)

    # Denormalised from the vendor — see the module docstring. NULL when the
    # vendor is listed by country only: such a package appears in the
    # by-country list and is left out of the nearest-first one, rather than
    # being given a made-up point.
    location = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True
    )
    uses_vendor_location: Mapped[bool] = mapped_column(Boolean, default=True)
    meeting_point_address: Mapped[str] = mapped_column(String(500), nullable=True)
    # Free text the admin types, e.g. "Kerala State · Munnar region". Shown in
    # the app with a pin icon so travellers know roughly where the package is,
    # without a map point or directions. Admin-only: not in the partner tuple.
    region_label: Mapped[str] = mapped_column(String(120), nullable=True)

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
    # Where the traveller wants picking up: a Google place they chose
    # ("Name, address") or whatever they typed. Optional.
    pickup_location: Mapped[str] = mapped_column(String(500), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=True)

    # The Experience Booking Terms version the traveller accepted with this
    # request, and when. NULL on requests from before the terms, or from an
    # app too old to show them (allowed during legal_service's grace period).
    terms_version: Mapped[int] = mapped_column(Integer, nullable=True)
    terms_accepted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # new | contacted | confirmed | closed | customer_cancelled |
    # provider_cancelled. The transitions are in enquiry_lifecycle.
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)

    # Set when the provider confirms: the booked day (the preferred date unless
    # they agreed another, and required for a "flexible" request). The 72-hour
    # rule counts back from it.
    confirmed_date: Mapped[date] = mapped_column(Date, nullable=True)
    confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Set by either side's cancellation; the status says whose.
    cancelled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    cancellation_reason: Mapped[str] = mapped_column(Text, nullable=True)
    # A traveller's cancellation of a confirmed booking inside the 72 hours.
    late_cancellation: Mapped[bool] = mapped_column(Boolean, nullable=True)
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

    @property
    def free_cancellation_last_day(self) -> Optional[date]:
        """Derived from `confirmed_date`, for the response schemas to read."""
        return enquiry_lifecycle.free_cancellation_last_day(self.confirmed_date)

    def __repr__(self) -> str:
        return f"<ExperienceEnquiry {self.contact_name} -> {self.vendor_name_snapshot}>"


class ExperienceReview(Base):
    """A signed-in traveller's rating of a package, and the provider's reply.

    Anyone with an account can review any published package, once: (`user_id`,
    `package_id`) is unique and a second send edits the first. That is a
    deliberate choice over limiting reviews to confirmed bookings, which left
    most packages with nothing to show. The safeguards are the account, the
    one-per-package rule, and the admin's power to hide a review.

    Published the moment it is written; an admin can hide it
    (`status = "hidden"`), which takes the stars out of every average and the
    text out of every list. The reviewer's name is a snapshot ("Anna K.") so it
    reads the same after the account or the package is gone.
    """

    __tablename__ = "experience_reviews"
    __table_args__ = (
        UniqueConstraint("user_id", "package_id", name="uq_experience_reviews_user_package"),
        CheckConstraint("rating BETWEEN 1 AND 5", name="ck_experience_reviews_rating"),
        # The package's review list and its average both read one package's
        # published rows, newest first.
        Index("ix_experience_reviews_package_status", "package_id", "status", "created_at"),
        Index("ix_experience_reviews_vendor_status", "vendor_id", "status", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    package_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_packages.id", ondelete="CASCADE"),
        nullable=False,
    )
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    reviewer_name: Mapped[str] = mapped_column(String(80), nullable=False)
    # 1-5; the range is also checked in the database.
    rating: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    comment: Mapped[str] = mapped_column(Text, nullable=True)
    # "published" | "hidden"
    status: Mapped[str] = mapped_column(String(12), default="published", nullable=False)

    # The provider's public answer, one per review. Written from the partner
    # portal; the admin can clear it.
    vendor_reply: Mapped[str] = mapped_column(Text, nullable=True)
    vendor_replied_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # Set only when the traveller changes their review after posting it.
    edited_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    hidden_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)

    package: Mapped["ExperiencePackage"] = relationship("ExperiencePackage", lazy="joined")

    def __repr__(self) -> str:
        return f"<ExperienceReview {self.rating}* on {self.package_id}>"


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
