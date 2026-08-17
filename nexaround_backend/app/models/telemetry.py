"""Telemetry models — one row per resolved API operation.

The point of this module is to make a *paid* call and a *cached* call
distinguishable, which `api_request_logs` cannot do: it logs intent before the
HTTP request, records no outcome, and never sees cache or database hits at all.

`ApiEvent` is written AFTER the outcome is known, and always carries
`served_from`, so "how many of these did we actually buy" is a GROUP BY rather
than a guess.

Note on partitioning: `api_events` is RANGE-partitioned on `ts` in Postgres.
SQLAlchemy has no DDL for that, so the table is created by raw SQL in the
migration and this class exists for ORM reads only — writes go through the
batched INSERT in `telemetry.py`. The composite primary key (id, ts) is required
by Postgres: a partitioned table's PK must contain the partition key.
"""
import uuid
from datetime import datetime, date, timezone

from sqlalchemy import (
    BigInteger, Boolean, CHAR, Date, DateTime, Integer, Numeric,
    SmallInteger, String, Text,
)
from sqlalchemy.dialects.postgresql import INET, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


# Allowed `served_from` values. Anything not in this set is a bug in the
# recorder, not a new case — the CHECK constraint in the migration enforces it.
SERVED_FROM = ("upstream", "redis", "memory", "database", "disk", "negative")

# Providers we call. `internal` covers operations that never leave the box
# (a pure cache or PostGIS hit) so those still produce a row.
PROVIDERS = (
    "google_maps", "gemini", "mapbox", "geoapify", "serpapi",
    "unsplash", "booking", "google", "apple", "firebase", "internal",
)


class ApiEvent(Base):
    """One resolved API operation: what was asked for, where it came from,
    whether it cost anything."""

    __tablename__ = "api_events"
    # Created as a partitioned table by raw DDL; keep autogenerate off it.
    __table_args__ = {"info": {"skip_autogenerate": True}}

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    ts: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        primary_key=True,
        default=lambda: datetime.now(timezone.utc),
    )

    # Correlates one inbound request to every upstream call it caused. This is
    # what turns "15 Find Place calls" into "one category tap".
    request_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=True)

    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    operation: Mapped[str] = mapped_column(String(64), nullable=False)
    # Billing SKU, joined against api_sku_rates. NULL when nothing is charged.
    sku: Mapped[str] = mapped_column(String(64), nullable=True)

    served_from: Mapped[str] = mapped_column(String(16), nullable=False)
    billable: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    est_cost_usd: Mapped[float] = mapped_column(
        Numeric(10, 6), nullable=False, default=0
    )

    http_status: Mapped[int] = mapped_column(SmallInteger, nullable=True)
    # The provider's own status field — Google returns 200 OK with
    # REQUEST_DENIED in the body, so HTTP status alone is not enough.
    provider_status: Mapped[str] = mapped_column(String(32), nullable=True)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=True)

    # No FK: this table is partitioned and high-volume, and a user deletion
    # must not cascade into telemetry history.
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=True)
    client_ip: Mapped[str] = mapped_column(INET, nullable=True)
    app_version: Mapped[str] = mapped_column(String(32), nullable=True)
    platform: Mapped[str] = mapped_column(String(16), nullable=True)

    # Normalised cache key. Indexed for upstream rows only, which answers the
    # highest-value question here: which keys did we pay for more than once?
    cache_key: Mapped[str] = mapped_column(String(255), nullable=True)
    params_digest: Mapped[str] = mapped_column(CHAR(64), nullable=True)
    error: Mapped[str] = mapped_column(Text, nullable=True)


class ApiUsageHourly(Base):
    """Hourly rollup. Every dashboard panel spanning more than 48h reads this
    instead of api_events, so no UI query can trigger a partition scan."""

    __tablename__ = "api_usage_hourly"

    bucket: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), primary_key=True)
    operation: Mapped[str] = mapped_column(String(64), primary_key=True)
    served_from: Mapped[str] = mapped_column(String(16), primary_key=True)
    # '' rather than NULL: NULL never compares equal, which would break the PK.
    provider_status: Mapped[str] = mapped_column(
        String(32), primary_key=True, default=""
    )

    calls: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    billable_calls: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    est_cost_usd: Mapped[float] = mapped_column(
        Numeric(12, 6), nullable=False, default=0
    )
    p50_latency_ms: Mapped[int] = mapped_column(Integer, nullable=True)
    p95_latency_ms: Mapped[int] = mapped_column(Integer, nullable=True)
    error_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class ApiUsageUserDaily(Base):
    """Per-user daily rollup — powers attribution and per-user quotas."""

    __tablename__ = "api_usage_user_daily"

    day: Mapped[date] = mapped_column(Date, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), primary_key=True)

    calls: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    billable_calls: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    est_cost_usd: Mapped[float] = mapped_column(
        Numeric(12, 6), nullable=False, default=0
    )


class ApiSkuRate(Base):
    """Provider pricing, as data.

    Hard-coded rates are how cost estimates drift out of date without anyone
    noticing. These are editable from the admin Settings page and carry an
    effective date so historical events keep the rate that applied at the time.
    """

    __tablename__ = "api_sku_rates"

    sku: Mapped[str] = mapped_column(String(64), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    unit_cost_usd: Mapped[float] = mapped_column(Numeric(10, 6), nullable=False)
    # Calls per calendar month billed at zero before unit_cost_usd applies.
    free_tier_monthly: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    effective_from: Mapped[date] = mapped_column(Date, nullable=False)
    notes: Mapped[str] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class ApiAlert(Base):
    """An anomaly raised over api_events.

    (rule, subject) is the dedup key: the same rule will not re-fire for the
    same provider or operation while it is inside its cooldown. An alert stream
    that repeats itself is one people learn to ignore.
    """

    __tablename__ = "api_alerts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    rule: Mapped[str] = mapped_column(String(32), nullable=False)
    subject: Mapped[str] = mapped_column(String(128), nullable=False)
    severity: Mapped[str] = mapped_column(String(16), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    detail: Mapped[dict] = mapped_column(JSONB, nullable=True)
    acknowledged_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    notified_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
