import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Text, DateTime, JSON, Float, Integer, Boolean, ForeignKey, ARRAY
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
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
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

    def __repr__(self) -> str:
        return f"<Attraction {self.name}>"
