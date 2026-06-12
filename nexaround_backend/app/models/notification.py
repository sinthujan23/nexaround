import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Text, DateTime, Boolean, Integer, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base


class Broadcast(Base):
    """An admin-sent announcement / promotion — the campaign record shown in the
    admin panel's 'Broadcast History'. One row per send; the per-user copies live
    in [Notification]."""
    __tablename__ = "broadcasts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    # 'all' for now. Plan targeting (free/pro) is intentionally not implemented
    # yet — kept as a free-text label so the column is future-proof.
    target_audience: Mapped[str] = mapped_column(String(50), default="all")
    recipients_count: Mapped[int] = mapped_column(Integer, default=0)  # users targeted
    devices_sent: Mapped[int] = mapped_column(Integer, default=0)      # pushes delivered
    devices_failed: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="sending")  # sending|sent|failed
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class Notification(Base):
    """A per-user inbox entry — what the app's bell icon shows. Created for every
    targeted user when a broadcast goes out (and reusable for other system
    notices, e.g. Odyssey-ready alerts)."""
    __tablename__ = "notifications"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id"), index=True, nullable=False
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(String(40), default="broadcast")  # broadcast|system|odyssey
    broadcast_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    # Per-user PUSH (FCM) delivery outcome for broadcasts, so the admin can see
    # exactly who received it: pending|sent|failed|no_token. ('sent' = at least
    # one of the user's devices was delivered to.)
    push_status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
