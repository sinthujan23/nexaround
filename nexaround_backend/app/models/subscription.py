"""Paid plans (Voyager / Globetrotter) and the store events behind them.

A user with no active row here is on the free Explorer plan. A user can hold
one row per `source`: the store subscription (RevenueCat, which speaks for the
App Store and Google Play) and an optional admin grant (testers, support,
goodwill). The best active row wins, so an admin grant never overwrites a paid
subscription and a webhook never wipes an admin grant.
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    JSON, Boolean, DateTime, ForeignKey, Numeric, String, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class Subscription(Base):
    __tablename__ = "subscriptions"
    __table_args__ = (UniqueConstraint("user_id", "source", name="uq_subscriptions_user_source"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False,
    )
    # 'revenuecat' (App Store / Google Play) or 'admin' (granted by hand).
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    # 'voyager' | 'globetrotter'
    plan: Mapped[str] = mapped_column(String(20), nullable=False)
    # 'monthly' | 'yearly' | None for an open-ended admin grant
    period: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    # 'app_store' | 'play_store' | 'admin' | other RevenueCat store names
    store: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # For display only — whether the plan is usable is decided by period_end.
    # 'active' | 'cancelled' (auto-renew off, still paid up) | 'billing_issue'
    # | 'expired'
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    product_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    # Start of the current billing period: Odyssey plans are counted from here.
    period_start: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    # When access ends, store grace period included. NULL = no end (admin).
    period_end: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    auto_renew: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # 'SANDBOX' | 'PRODUCTION' — sandbox purchases unlock too (that is how the
    # stores' reviewers and our testers buy), but stay out of revenue numbers.
    environment: Mapped[Optional[str]] = mapped_column(String(12), nullable=True)
    note: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    granted_by: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(),
    )


class SubscriptionEvent(Base):
    """Every RevenueCat webhook, kept once (idempotent on `event_id`).

    The Payments page reads revenue from here: purchase and renewal events
    carry the price the store charged.
    """
    __tablename__ = "subscription_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), index=True, nullable=True)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    product_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    store: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    environment: Mapped[Optional[str]] = mapped_column(String(12), nullable=True)
    price_usd: Mapped[Optional[float]] = mapped_column(Numeric(10, 2), nullable=True)
    currency: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)
    price_local: Mapped[Optional[float]] = mapped_column(Numeric(12, 2), nullable=True)
    event_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
