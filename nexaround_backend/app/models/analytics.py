import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import DateTime, Integer, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base


class PlaceVisit(Base):
    """One row per place-detail open — the real source for the 'Places Visited'
    engagement metric. user_id is nullable so anonymous views still count."""
    __tablename__ = "place_visits"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    attraction_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("attractions.id"), index=True, nullable=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), index=True, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class UserSession(Base):
    """A finished app session reported by the client when it backgrounds — the
    real source for the 'Avg Session Length' metric."""
    __tablename__ = "user_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), index=True, nullable=True
    )
    duration_seconds: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class FeatureOpen(Base):
    """An app feature an explorer actually looked at during one visit — the
    admin's Feature usage page counts these.

    The app reports a screen only after it has been on screen for a few seconds
    with the app in the foreground, so background loading and tabs kept alive
    out of sight never count. One row per visit and feature: opening the same
    feature again in that visit adds nothing.
    """
    __tablename__ = "feature_opens"
    __table_args__ = (
        UniqueConstraint("visit_id", "feature", name="uq_feature_opens_visit_feature"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # Taken from the caller's token, never from the report. Deleting an
    # account deletes its rows.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # The visit the app reports to /auth/me/session (user_sessions.id).
    visit_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    # A key from app.services.feature_usage.FEATURES.
    feature: Mapped[str] = mapped_column(String(32), nullable=False)
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True, nullable=False
    )
    app_version: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    platform: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
