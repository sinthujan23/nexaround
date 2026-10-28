"""City Tours: step-by-step city guides written in the admin panel.

A guide is one route through a city: a start point, then "take this vehicle",
the next stop, and so on, with partner links on the steps. Content creators
write them; an admin approves each version before travellers see it.

The guide itself is one JSON document (`content`), so the version travellers
see (`live_content`) is a plain copy of it, taken when an admin approves. A
creator can keep editing a live guide: the app goes on showing the approved
copy until the admin approves the new one. See app/services/city_tours.py for
the document's shape and the review rules.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Index, Integer, String, Text, false
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class ContentCreator(Base):
    """Someone who writes City Tours. Signs in to the admin panel with their
    email and sees only City Tours there.

    Kept out of `users` for the reason vendors are (see partner.py): traveller
    endpoints accept any `users` row's token. Admin-created only; the admin
    sets the password and can reset it or switch the login off.
    """
    __tablename__ = "content_creators"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    # Stored lower-case; the sign-in form's "username" box takes it.
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    password_changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)

    def __repr__(self) -> str:
        return f"<ContentCreator {self.email}>"


class CityTour(Base):
    __tablename__ = "city_tours"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # The creator who wrote it; NULL when an admin did. A creator's own list
    # is filtered on this, and a deleted creator's guides stay (author_name).
    creator_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("content_creators.id", ondelete="SET NULL"),
        nullable=True, index=True,
    )
    author_name: Mapped[str] = mapped_column(String(120), nullable=False, default="Admin")

    # The working copy the editor saves, and a counter that goes up with every
    # change to it. Approving names the version the admin looked at, so an
    # edit that lands while they read is never published unseen.
    content: Mapped[dict] = mapped_column(JSONB, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")

    # draft | pending | changes_requested | approved (= the working copy is live)
    review_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="draft", server_default="draft", index=True,
    )
    review_note: Mapped[str] = mapped_column(Text, nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    reviewed_by: Mapped[str] = mapped_column(String(120), nullable=True)

    # What the app shows. NULL until the first approval.
    live_content: Mapped[dict] = mapped_column(JSONB, nullable=True)
    live_version: Mapped[int] = mapped_column(Integer, nullable=True)
    published_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    live_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    # An admin took a live guide off the app without deleting it.
    is_hidden: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default=false())

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now, nullable=False,
    )

    creator = relationship("ContentCreator", lazy="selectin")

    def __repr__(self) -> str:
        return f"<CityTour {(self.content or {}).get('title')!r}>"


class CityTourTap(Base):
    """One traveller tap on a partner link in a guide: the counts the admin
    reports to partners. Written by /go/city-tour (links that open the
    partner's site) and POST /city-tours/{id}/links/{link_id}/tap
    (Experiences, which open inside the app)."""
    __tablename__ = "city_tour_taps"
    __table_args__ = (
        Index("ix_city_tour_taps_tour_link", "tour_id", "link_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    tour_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("city_tours.id", ondelete="CASCADE"), nullable=False,
    )
    link_id: Mapped[str] = mapped_column(String(36), nullable=False)
    # An affiliate's key ("klook") or "experience".
    partner: Mapped[str] = mapped_column(String(40), nullable=False)
    package_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, nullable=False, index=True,
    )
