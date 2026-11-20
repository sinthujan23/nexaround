"""Explorer Points the server cannot work out from other rows (2026-11-20).

Almost all points are counted from the rows they come from (reviews, photos,
completed trips; see services/explorer_points.py). This table holds the rest:
for now only the one-time carry-over of the old phone-only XP.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ExplorerPointEvent(Base):
    __tablename__ = "explorer_point_events"
    __table_args__ = (
        # One carry-over per traveller (ref "once"); later kinds pick their own ref.
        UniqueConstraint("user_id", "kind", "ref", name="uq_explorer_point_events_user_kind_ref"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # Deleting an account deletes its events (auth_service.delete_account).
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    ref: Mapped[str] = mapped_column(String(64), nullable=False)
    points: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
