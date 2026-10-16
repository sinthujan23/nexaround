"""Currency exchange rates, fetched once a day and served to the app.

One row per base currency (only USD today). The app converts every price it
shows into the traveller's currency from this row, and Odyssey restates
provider prices with it. Fetched by the worker from ExchangeRate-API with the
key kept in Admin > Settings, so no phone ever calls the provider and the
monthly quota is spent once a day, not once per traveller.
"""

from datetime import datetime, timezone

from sqlalchemy import DateTime, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class FxRate(Base):
    __tablename__ = "fx_rates"

    base: Mapped[str] = mapped_column(String(3), primary_key=True)
    # {"QAR": 3.64, "INR": 95.1, ...}: units of each currency per one `base`.
    rates: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    # "exchangerate-api" (keyed) or "open-er-api" (the keyless fallback).
    source: Mapped[str] = mapped_column(String(40), nullable=False)
    # The provider's own publish time, and when it says the next one is due.
    provider_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    provider_next_update_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    # When we last stored a good answer, and when we last tried at all.
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    last_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=True)
    # The last failure (e.g. "invalid-key", "quota-reached"); cleared on success.
    last_error: Mapped[str] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )
