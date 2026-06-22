import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class TravelStory(Base):
    __tablename__ = "travel_stories"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    location_name: Mapped[str] = mapped_column(String(255), nullable=False)
    category: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str] = mapped_column(String(1000), nullable=False)
    image_url: Mapped[str] = mapped_column(String(500), nullable=False)
    image_urls: Mapped[list[str]] = mapped_column(ARRAY(String), server_default='{}', nullable=False)
    latitude: Mapped[float] = mapped_column(nullable=True)
    longitude: Mapped[float] = mapped_column(nullable=True)
    is_public: Mapped[bool] = mapped_column(default=True)
    
    # Journal Features
    is_journal: Mapped[bool] = mapped_column(default=False)
    journal_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    total_spend: Mapped[float] = mapped_column(default=0.0)
    spend_currency: Mapped[str] = mapped_column(String(10), default="USD")
    cloud_provider: Mapped[str] = mapped_column(String(50), nullable=True)
    cloud_folder_url: Mapped[str] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    user = relationship("User", lazy="selectin")
    likes = relationship("TravelStoryLike", back_populates="story", cascade="all, delete-orphan", lazy="selectin")
    comments = relationship("TravelStoryComment", back_populates="story", cascade="all, delete-orphan", lazy="selectin")


class TravelStoryLike(Base):
    __tablename__ = "travel_story_likes"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    story_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("travel_stories.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    story = relationship("TravelStory", back_populates="likes")


class TravelStoryComment(Base):
    __tablename__ = "travel_story_comments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    story_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("travel_stories.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    image_index: Mapped[int] = mapped_column(default=0)
    comment_text: Mapped[str] = mapped_column(String(1000), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    story = relationship("TravelStory", back_populates="comments")
    user = relationship("User", lazy="selectin")
