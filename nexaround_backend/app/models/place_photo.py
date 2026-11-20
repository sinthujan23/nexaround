"""Photos travellers send for places that have none (TL, 2026-11-18).

A place showing only its category icon can be given a photo from the app. It
waits (`pending`) until an admin approves it in Admin › Media; an approved
photo is shown for that place to everyone, on every app version. A rejected
photo's file is deleted at once; the row stays so the uploader is told.

Places are identified the same way as reviews (models/place_review.py): the
id the app uses, stored under the Google id when we know it.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, Integer, String, false
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class PlacePhoto(Base):
    __tablename__ = "place_photos"
    __table_args__ = (
        # A place's approved photo, newest first.
        Index("ix_place_photos_place_status", "place_key", "status", "created_at"),
        # Admin › Media: one status, oldest waiting first.
        Index("ix_place_photos_status_created", "status", "created_at"),
        # A traveller's own photos: their Explorer Points and "one per place".
        Index("ix_place_photos_user", "user_id", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    place_key: Mapped[str] = mapped_column(String(255), nullable=False)
    # Deleting an account deletes its photo rows (auth_service.delete_account).
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    uploader_name: Mapped[str] = mapped_column(String(80), nullable=False)
    place_name: Mapped[str] = mapped_column(String(255), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=True)
    longitude: Mapped[float] = mapped_column(Float, nullable=True)

    # Public path of the re-encoded WebP (/static/uploads/place_photos/<uuid>.webp);
    # null once a rejected photo's file is deleted.
    url: Mapped[str] = mapped_column(String(255), nullable=True)
    width: Mapped[int] = mapped_column(Integer, nullable=True)
    height: Mapped[int] = mapped_column(Integer, nullable=True)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=True)

    # "pending" | "approved" | "rejected"
    status: Mapped[str] = mapped_column(String(12), default="pending", nullable=False)
    reject_reason: Mapped[str] = mapped_column(String(200), nullable=True)
    # The place showed no photo at all when this was sent, and no other
    # traveller photo of it was approved first: worth the Trailblazer bonus
    # (services/explorer_points.py). Settled when an admin approves it.
    trailblazer: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false(), nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
