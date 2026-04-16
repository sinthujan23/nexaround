import uuid
from sqlalchemy import String, Integer, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Media(Base):
    __tablename__ = "media"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    attraction_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("attractions.id"), nullable=False
    )
    type: Mapped[str] = mapped_column(String(20), nullable=False)  # image, video, audio
    url: Mapped[str] = mapped_column(String(500), nullable=False)
    caption: Mapped[str] = mapped_column(String(255), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    # Relationships
    attraction = relationship("Attraction", back_populates="media")

    def __repr__(self) -> str:
        return f"<Media {self.type} for {self.attraction_id}>"
