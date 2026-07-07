import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Integer, Boolean, Text, Float, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Museum(Base):
    """One of the world's top museums (e.g. State Hermitage Museum)."""
    __tablename__ = "museums"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    slug: Mapped[str] = mapped_column(
        String(120), unique=True, nullable=False, index=True,
        comment="URL-friendly identifier, e.g. 'state-hermitage-museum'",
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    city: Mapped[str] = mapped_column(String(120), nullable=False)
    country: Mapped[str] = mapped_column(String(120), nullable=False)
    annual_visitors: Mapped[int] = mapped_column(Integer, nullable=True)
    rank: Mapped[int] = mapped_column(Integer, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    ticket_url: Mapped[str | None] = mapped_column(
        String(512), nullable=True,
        comment="Affiliate / deep-link to buy fast-track tickets",
    )
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    masterpieces = relationship(
        "MuseumMasterpiece", back_populates="museum",
        cascade="all, delete-orphan", order_by="MuseumMasterpiece.rank",
    )

    def __repr__(self) -> str:
        return f"<Museum {self.name}>"


class MuseumMasterpiece(Base):
    """A must-see item inside a museum, tagged with duration flags."""
    __tablename__ = "museum_masterpieces"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    museum_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("museums.id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    rank: Mapped[int] = mapped_column(Integer, nullable=False)
    building: Mapped[str] = mapped_column(String(255), nullable=False)
    room_gallery: Mapped[str] = mapped_column(String(255), nullable=False)
    must_see_item: Mapped[str] = mapped_column(String(255), nullable=False)
    artist: Mapped[str] = mapped_column(String(255), nullable=True)
    category: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(
        Text, nullable=True,
        comment="Why it's in the top 100",
    )
    included_5h: Mapped[bool] = mapped_column(Boolean, default=False)
    included_1d: Mapped[bool] = mapped_column(Boolean, default=False)
    included_2d: Mapped[bool] = mapped_column(Boolean, default=False)

    # Relationships
    museum = relationship("Museum", back_populates="masterpieces")

    def __repr__(self) -> str:
        return f"<MuseumMasterpiece #{self.rank}: {self.must_see_item}>"
