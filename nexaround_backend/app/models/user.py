import uuid
from typing import Optional
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, JSON, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    password_hash: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    avatar_url: Mapped[str] = mapped_column(String(500), nullable=True)
    preferences: Mapped[dict] = mapped_column(JSON, default=dict)
    language: Mapped[str] = mapped_column(String(10), default="en")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    # Relationships.
    #
    # `lazy="raise"`, NOT "selectin". Every authenticated request loads a User
    # (get_current_user -> UserRepository.get_by_id), and selectin made that one
    # load emit six queries — users, budgets, discovery_histories, reviews,
    # itineraries, and expenses via Budget.expenses — deserialising the caller's
    # entire history into Python before the endpoint did any work. Measured at
    # 44.7 KiB and 21 ms for an average account; the heaviest real account
    # carries 126 itineraries / 837 kB, and paid that on *every* request it made.
    #
    # Nothing reads these collections. They are kept (rather than deleted)
    # because Itinerary.user, Budget.user, Review.user and
    # DiscoveryHistory.user declare back_populates against them, and "raise"
    # rather than "select" so that a future accidental `user.itineraries`
    # fails loudly here instead of silently reintroducing the fan-out.
    # Load them explicitly with selectinload() at the query that needs them.
    #
    # passive_deletes=True is required alongside "raise": deleting a User makes
    # the unit of work resolve each relationship, which would trip the raise.
    # AuthService.delete_account already removes every child row itself (all ten
    # FK paths), and the remaining NO ACTION constraints in Postgres will reject
    # the delete loudly if it ever misses one.
    reviews = relationship(
        "Review", back_populates="user", lazy="raise", passive_deletes=True)
    itineraries = relationship(
        "Itinerary", back_populates="user", lazy="raise", passive_deletes=True)
    budgets = relationship(
        "Budget", back_populates="user", lazy="raise", passive_deletes=True)
    discovery_histories = relationship(
        "DiscoveryHistory", back_populates="user", lazy="raise", passive_deletes=True)

    def __repr__(self) -> str:
        return f"<User {self.email}>"
