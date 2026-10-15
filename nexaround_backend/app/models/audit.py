"""Audit trail and sign-in sessions for the admin panel and the partner portal.

Two tables, deliberately separate:

* `auth_sessions` is *state*: one row per sign-in, carrying the device it came
  from. Revoking a row signs that device out on its next request. It is mutable.
* `audit_events` is *history*: append-only, one row per thing that happened. A
  database trigger (see the migration) refuses UPDATE and DELETE, so neither a
  bug nor an over-eager admin endpoint can quietly rewrite it.

Neither table has foreign keys to `vendor_users` or `experience_vendors`.
Admins are not rows anywhere (one shared env credential), and a record of what
a login did must survive that login being deleted.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Boolean, DateTime, Index, Integer, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AuthSession(Base):
    """One sign-in on one device. Its id travels in the token as `sid`."""

    __tablename__ = "auth_sessions"
    __table_args__ = (
        Index("ix_auth_sessions_actor", "actor_type", "actor_id", "created_at"),
        Index("ix_auth_sessions_vendor", "vendor_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # "admin" or "vendor".
    actor_type: Mapped[str] = mapped_column(String(10), nullable=False)
    # The admin's username, or the vendor login's id.
    actor_id: Mapped[str] = mapped_column(String(255), nullable=False)
    # What a person recognises: the admin's username, or the vendor login's email.
    actor_label: Mapped[str] = mapped_column(String(255), nullable=False)
    vendor_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )

    ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    last_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    browser: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    os: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    # "desktop", "mobile", "tablet" or "other".
    device_type: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # When the newest token issued for this session stops working. A refresh
    # moves it forward.
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    revoked_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # "user" (signed out), "admin" (revoked by an admin) or "password".
    revoked_reason: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    revoked_by: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)


class AuditEvent(Base):
    """One row of the audit trail. Append-only."""

    __tablename__ = "audit_events"
    __table_args__ = (
        Index("ix_audit_events_time", "occurred_at"),
        Index("ix_audit_events_actor", "actor_type", "actor_id", "occurred_at"),
        Index("ix_audit_events_vendor", "vendor_id", "occurred_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    # "admin", "vendor", or "anonymous" for a failed sign-in that matched nobody.
    actor_type: Mapped[str] = mapped_column(String(10), nullable=False)
    actor_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    # Snapshot, like `vendor_activities.actor_name`: still readable after the
    # login is renamed or deleted.
    actor_label: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    vendor_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )
    session_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )

    # "auth" for sign-in/out and credential changes, "access" for a read of
    # something sensitive, "change" for a write.
    category: Mapped[str] = mapped_column(String(10), nullable=False)
    # Machine key: "auth.login", "auth.login_failed", "change.update" ...
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    # Rendered sentence, stored for the same reason as `actor_label`.
    summary: Mapped[str] = mapped_column(String(300), nullable=False)

    method: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)
    # The route template ("/admin/experiences/{vendor_id}"), so events group by
    # endpoint; `target_id` carries the concrete id.
    route: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    target_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    status_code: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    success: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    browser: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    os: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    device_type: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    request_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )

    # Anything extra worth keeping, e.g. the reason a sign-in failed. Never a
    # request body: those carry passwords and API keys.
    detail: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
