import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Text, DateTime, JSON, Float, Integer, Boolean, ForeignKey, ARRAY, Computed
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geometry
from app.core.database import Base


class Attraction(Base):
    __tablename__ = "attractions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    history: Mapped[str] = mapped_column(Text, nullable=True)

    # PostGIS geometry column for location (POINT with SRID 4326 = WGS84)
    location = mapped_column(Geometry(geometry_type="POINT", srid=4326), nullable=False)

    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("categories.id"), nullable=True
    )
    address: Mapped[str] = mapped_column(String(500), nullable=True)

    # The Google place this row was seeded from, when it was seeded from one.
    # Nullable: admin-curated rows have no upstream, and rows seeded before the
    # column existed resolve lazily on first detail view.
    google_place_id: Mapped[str] = mapped_column(String(255), nullable=True, index=True)
    details_fetched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    opening_hours: Mapped[dict] = mapped_column(JSON, default=dict)
    entry_fee: Mapped[float] = mapped_column(Float, nullable=True, default=0.0)
    currency: Mapped[str] = mapped_column(String(10), default="USD")
    rating: Mapped[float] = mapped_column(Float, default=0.0)
    review_count: Mapped[int] = mapped_column(Integer, default=0)
    accessibility: Mapped[dict] = mapped_column(JSON, default=dict)
    photo_urls: Mapped[list] = mapped_column(ARRAY(String), default=list)
    tags: Mapped[list] = mapped_column(ARRAY(String), default=list)
    geofence_radius_m: Mapped[int] = mapped_column(Integer, default=100)

    # Lifecycle. `status` is the one source of truth — see
    # app/services/place_status.py for what each value means and which moves
    # between them are allowed. `is_active` is generated from it by Postgres so
    # every reader that filters on it keeps working; it cannot be written.
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="live")
    status_reason: Mapped[str] = mapped_column(String(40), nullable=True)
    status_note: Mapped[str] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="unknown")
    submitted_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    # The admin's login name (admins are not rows in `users`), or "merge-script".
    reviewed_by: Mapped[str] = mapped_column(String(100), nullable=True)
    is_active: Mapped[bool] = mapped_column(
        Boolean, Computed("status = 'live'", persisted=True)
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # Relationships
    category = relationship("Category", back_populates="attractions", lazy="selectin")
    # `lazy="selectin"` on these two meant every attraction query — including
    # the three ring queries behind every Around You section — also fetched
    # every review and every media row for all ~300 places it returned, then
    # threw them away: nothing reads `.reviews` or `.media` off an Attraction
    # anywhere in the codebase. That eager load was 3.5s of a 4s cold response,
    # and its `SELECT reviews...` is what sat holding pooled connections.
    #
    # Deferred instead of removed so the relationships stay available. Under
    # async they now raise MissingGreenlet if something touches them outside a
    # session, which is the right failure: loud, at the call site, rather than a
    # silent per-row query on a hot path.
    reviews = relationship("Review", back_populates="attraction", lazy="select")
    media = relationship("Media", back_populates="attraction", lazy="select")

    # `is_active` is computed by the database. Without this, reading it after an
    # INSERT or UPDATE would need a lazy refresh, which raises MissingGreenlet
    # under async; with it the value comes back in the same statement.
    __mapper_args__ = {"eager_defaults": True}

    def __repr__(self) -> str:
        return f"<Attraction {self.name}>"


class AttractionAlias(Base):
    """An id that used to be its own row and now resolves to another.

    Written when duplicate copies are merged, so a favourite or a link holding
    a deleted copy's id still opens the place that was kept.
    """
    __tablename__ = "attraction_aliases"

    old_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    attraction_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("attractions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
