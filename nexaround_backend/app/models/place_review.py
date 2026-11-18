"""Travellers' own ratings and reviews of map places (TL, 2026-11-18).

Works for every place the app shows, whatever its source, so a place is
identified by the id the app uses rather than by a foreign key:

  - a Google place id ("ChIJ..."),
  - a free-map-data id ("op_..." Overture, "ga_..." Geoapify),
  - one of our own `attractions` rows (its uuid as text).

A place we hold in `attractions` with a Google id is stored under that Google
id (`place_reviews.canonical_key`), and both ids are read together, so the
first visit (Google id) and later ones (our uuid) add up to one place.

Published the moment it is written; an admin can hide it (`status =
"hidden"`), which takes it out of every average and list. The reviewer's name
and the place's name and position are snapshots, so the admin list reads the
same after either is gone.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint, DateTime, Float, ForeignKey, Index, SmallInteger, String, Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class PlaceReview(Base):
    __tablename__ = "place_reviews"
    __table_args__ = (
        UniqueConstraint("user_id", "place_key", name="uq_place_reviews_user_place"),
        CheckConstraint("rating BETWEEN 1 AND 5", name="ck_place_reviews_rating"),
        # A place's list and its average read one place's published rows.
        Index("ix_place_reviews_place_status", "place_key", "status", "created_at"),
        # The admin list: everything, newest first, optionally one status.
        Index("ix_place_reviews_status_created", "status", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    place_key: Mapped[str] = mapped_column(String(255), nullable=False)
    # Deleting an account deletes its reviews (auth_service.delete_account).
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    reviewer_name: Mapped[str] = mapped_column(String(80), nullable=False)
    place_name: Mapped[str] = mapped_column(String(255), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=True)
    longitude: Mapped[float] = mapped_column(Float, nullable=True)

    # 1-5; the range is also checked in the database.
    rating: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    comment: Mapped[str] = mapped_column(Text, nullable=True)
    # "published" | "hidden"
    status: Mapped[str] = mapped_column(String(12), default="published", nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # Set only when the traveller changes their review after posting it.
    edited_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    hidden_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
