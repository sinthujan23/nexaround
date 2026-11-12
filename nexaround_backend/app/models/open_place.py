"""Free map data for free users (Explorer).

Places downloaded from Overture Maps (CDLA-Permissive-2.0 / Apache-2.0 / CC0),
one 0.5-degree area at a time, the first time a free user needs that area.
Kept apart from `attractions` (Google-sourced) so the two never mix: free users
get these places with our own popularity score instead of Google ratings.

Only the sections whose Overture coverage is good live here today: Food &
Drink, Shopping, Hotels, Medical and Hospital. Sights / Nature / POI stay on
Google (within the free user's map limit) until a better free source is added.
"""
from datetime import datetime
from typing import Optional

from geoalchemy2 import Geometry
from sqlalchemy import DateTime, Float, Integer, SmallInteger, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class OpenPlace(Base):
    __tablename__ = "open_places"

    # Overture's own id (GERS). Served to the app as "op_<id>".
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    # One of our section names: "Food & Drink", "Shopping", "Hotels",
    # "Medical", "Hospital".
    section: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    # Overture basic_category, e.g. "restaurant", "pharmacy_and_drug_store".
    category: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    # Indexed as (location::geography) by the migration, like attractions.
    location = mapped_column(
        Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False,
    )
    address: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    country: Mapped[Optional[str]] = mapped_column(String(2), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    website: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    social: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    brand: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    # Overture's "this place exists" confidence, 0..1.
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    # Wikipedia readers last month (0 = no article matched).
    wiki_views: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Our users' place-page opens, 0..10 points, refreshed nightly.
    our_points: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    # 0..100, see app/services/open_data/score.py. Sorted on, never shown.
    popularity_score: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    tile: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    release: Mapped[str] = mapped_column(String(32), nullable=False)
    imported_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(),
    )


class OpenArea(Base):
    """One 0.5 x 0.5 degree download area and where its import stands."""
    __tablename__ = "open_areas"

    # "<lat floor>_<lng floor>", e.g. "15.5_108.0".
    tile: Mapped[str] = mapped_column(String(16), primary_key=True)
    # queued | importing | done | failed
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="queued", index=True)
    places_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    release: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    attempts: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    seconds: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    requested_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(),
    )
    imported_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
