"""Versioned legal documents and the record of who accepted which version.

The acceptance rows are the point. A disclaimer only protects the client if it
can show that a given traveller or provider agreed to a given wording at a
given time, so a document is never edited into a new meaning in place: a
material change is a new version, and everyone accepts again.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    ARRAY, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class LegalDocument(Base):
    """One version of one document. The highest version of a kind is current."""

    __tablename__ = "legal_documents"
    __table_args__ = (UniqueConstraint("kind", "version", name="uq_legal_kind_version"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # experience_customer | experience_provider (legal_service.KINDS)
    kind: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    # A deliberately small Markdown subset, so the app, the partner portal and
    # the website can all render it without a Markdown library: "## " starts a
    # heading, "- " a bullet, and a blank line separates paragraphs.
    body: Mapped[str] = mapped_column(Text, nullable=False)
    # The few lines shown where people commit (the app's "Good to know" card,
    # the request sheet), so they change with the document.
    highlights: Mapped[list] = mapped_column(
        ARRAY(String), default=list, server_default="{}"
    )
    published_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # Bumped by a wording fix that is saved without a new version.
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_by: Mapped[str] = mapped_column(String(255), nullable=True)


class LegalAcceptance(Base):
    """One person accepting one version. Never updated or deleted.

    Foreign keys are SET NULL rather than CASCADE: deleting a vendor or a user
    must not destroy the evidence that they agreed. `party_label` keeps a
    readable name for when the row it pointed to is gone.
    """

    __tablename__ = "legal_acceptances"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    kind: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False)

    # A traveller (app) ...
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )
    enquiry_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_enquiries.id", ondelete="SET NULL"),
        nullable=True,
    )
    # ... or a provider (portal, or recorded by an admin).
    vendor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("experience_vendors.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )
    vendor_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("vendor_users.id", ondelete="SET NULL"),
        nullable=True,
    )
    party_label: Mapped[str] = mapped_column(String(255), nullable=True)

    # app | portal | offline
    method: Mapped[str] = mapped_column(String(20), nullable=False)
    # Offline only: who recorded it, and what it rests on ("signed partner form").
    recorded_by: Mapped[str] = mapped_column(String(255), nullable=True)
    note: Mapped[str] = mapped_column(Text, nullable=True)

    ip: Mapped[str] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[str] = mapped_column(String(512), nullable=True)
    accepted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )
