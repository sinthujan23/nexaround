import uuid
from sqlalchemy import String, Integer, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    icon: Mapped[str] = mapped_column(String(50), nullable=True)
    color: Mapped[str] = mapped_column(String(20), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    # Relationships
    # `lazy="raise"`, NOT "selectin". CategoryResponse returns only id/name/icon/
    # colour, but selectin made `GET /api/v1/categories/` hydrate every
    # attraction row joined to a category — 92,937 objects, ~106 MiB — and throw
    # all of it away. That endpoint is unauthenticated and took 6-8 s; two
    # concurrent calls pushed the whole API's p90 from 3 ms to 756 ms.
    #
    # Kept rather than deleted because Attraction.category back_populates
    # against it. Nothing reads it; load explicitly if that ever changes.
    attractions = relationship(
        "Attraction", back_populates="category", lazy="raise",
        passive_deletes=True)

    def __repr__(self) -> str:
        return f"<Category {self.name}>"
