"""add api telemetry tables

Creates the Phase 1 schema for API observability:

  api_events           partitioned raw event log (one row per resolved call)
  api_usage_hourly     hourly rollup read by the dashboard
  api_usage_user_daily per-user daily rollup for attribution and quotas
  api_sku_rates        provider pricing as editable data

api_events is RANGE-partitioned on ts so retention is DROP PARTITION rather
than a DELETE that would leave the table needing a vacuum. Two helper functions
are installed for the scheduler to call: one to create partitions ahead of time,
one to drop expired ones.

The existing api_request_logs table is deliberately left untouched. It stays
read-only for history; nothing is backfilled, because those rows predate
served_from and outcome recording and mixing them in would reproduce exactly
the ambiguity this schema exists to remove.

Revision ID: d7e8f9a0b1c2
Revises: ba158fc71f2e
Create Date: 2026-08-17 12:40:00.000000

"""
from typing import Sequence, Union
from datetime import date

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'd7e8f9a0b1c2'
down_revision: Union[str, None] = 'ba158fc71f2e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


SERVED_FROM = ("upstream", "redis", "memory", "database", "disk", "negative")

# Google Maps Platform list prices. free_tier_monthly reflects the per-SKU
# monthly free allowance. These are seeds, not gospel — they are editable from
# the admin Settings page precisely so they can be corrected against a real
# invoice rather than living in code.
SKU_SEED = [
    # sku, provider, unit_cost_usd, free_tier, notes
    ("find_place_basic", "google_maps", "0.017000", 10000,
     "Find Place, Basic Data fields only."),
    ("find_place_atmosphere", "google_maps", "0.022000", 10000,
     "Find Place with rating/user_ratings_total. Basic + Atmosphere Data. "
     "Dropping the two atmosphere fields moves calls to find_place_basic."),
    ("directions", "google_maps", "0.005000", 10000,
     "Directions API."),
    ("nearby_search_new", "google_maps", "0.032000", 10000,
     "Places API (New) searchNearby. Highest unit rate in use."),
    ("nearby_search_legacy", "google_maps", "0.032000", 10000,
     "Legacy Places nearbysearch, used when use_legacy=true."),
    ("text_search_new", "google_maps", "0.032000", 10000,
     "Places API (New) searchText, reached on /places/search DB miss."),
    ("place_details", "google_maps", "0.017000", 10000,
     "Place Details."),
    ("place_photo", "google_maps", "0.007000", 10000,
     "Place Photo. Disk-cached, so upstream calls are rare."),
    ("geocoding", "google_maps", "0.005000", 10000,
     "Geocoding and reverse geocoding."),
    ("autocomplete_per_request", "google_maps", "0.002830", 10000,
     "Autocomplete billed per request rather than per session."),
    # Non per-call or currently-free providers. Recorded so volume is visible
    # even where cost is zero; rate can be set later without a migration.
    ("gemini_flash_generate", "gemini", "0.000000", 0,
     "Gemini Flash is token-metered, not per-call. Cost stays 0 until token "
     "counts are recorded in Phase 3; call volume is still tracked."),
    ("geoapify_reverse", "geoapify", "0.000000", 90000,
     "Geoapify free tier is a daily request allowance; set a rate here if the "
     "plan changes."),
    ("mapbox_directions", "mapbox", "0.000000", 100000, "Mapbox free tier."),
    ("mapbox_geocoding", "mapbox", "0.000000", 100000, "Mapbox free tier."),
    ("serpapi_search", "serpapi", "0.000000", 0,
     "SerpAPI is plan-metered; set unit cost from the active plan."),
    ("unsplash_photo", "unsplash", "0.000000", 0, "Unsplash free tier."),
]


def upgrade() -> None:
    """Upgrade schema."""

    # ── api_events: partitioned raw log ────────────────────────────────────
    # Raw DDL because SQLAlchemy cannot express PARTITION BY. The primary key
    # must include ts — Postgres requires the partition key in any unique
    # constraint on a partitioned table.
    op.execute(
        """
        CREATE TABLE api_events (
            id              bigserial     NOT NULL,
            ts              timestamptz   NOT NULL DEFAULT now(),
            request_id      uuid,
            provider        varchar(32)   NOT NULL,
            operation       varchar(64)   NOT NULL,
            sku             varchar(64),
            served_from     varchar(16)   NOT NULL,
            billable        boolean       NOT NULL DEFAULT false,
            est_cost_usd    numeric(10,6) NOT NULL DEFAULT 0,
            http_status     smallint,
            provider_status varchar(32),
            latency_ms      integer,
            user_id         uuid,
            client_ip       inet,
            app_version     varchar(32),
            platform        varchar(16),
            cache_key       varchar(255),
            params_digest   char(64),
            error           text,
            CONSTRAINT api_events_pkey PRIMARY KEY (id, ts),
            CONSTRAINT api_events_served_from_check
                CHECK (served_from IN ('upstream','redis','memory','database','disk','negative')),
            CONSTRAINT api_events_cost_nonneg CHECK (est_cost_usd >= 0)
        ) PARTITION BY RANGE (ts);
        """
    )

    # Partition manager. Idempotent so the scheduler can call it every run.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION ensure_api_events_partition(p_month date)
        RETURNS text AS $$
        DECLARE
            start_date date := date_trunc('month', p_month)::date;
            end_date   date := (date_trunc('month', p_month) + interval '1 month')::date;
            part_name  text := 'api_events_' || to_char(start_date, 'YYYY_MM');
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE c.relname = part_name AND n.nspname = current_schema()
            ) THEN
                EXECUTE format(
                    'CREATE TABLE %I PARTITION OF api_events FOR VALUES FROM (%L) TO (%L)',
                    part_name, start_date, end_date
                );
            END IF;
            RETURN part_name;
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    # Retention. Drops whole partitions older than the cutoff month; returns
    # how many went, so the scheduler can log it.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION drop_api_events_partitions_before(p_cutoff date)
        RETURNS integer AS $$
        DECLARE
            cutoff_name text := 'api_events_' || to_char(date_trunc('month', p_cutoff), 'YYYY_MM');
            rec         record;
            dropped     integer := 0;
        BEGIN
            FOR rec IN
                SELECT c.relname
                FROM pg_class c
                JOIN pg_inherits i ON i.inhrelid = c.oid
                JOIN pg_class p ON p.oid = i.inhparent
                WHERE p.relname = 'api_events'
                  AND c.relname < cutoff_name
            LOOP
                EXECUTE format('DROP TABLE IF EXISTS %I', rec.relname);
                dropped := dropped + 1;
            END LOOP;
            RETURN dropped;
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    # Seed the current month plus two ahead, so a scheduler outage cannot cause
    # an insert to fail for want of a partition. One statement per execute:
    # asyncpg prepares every statement and rejects multi-command strings.
    for offset in (0, 1, 2):
        op.execute(
            "SELECT ensure_api_events_partition("
            f"(date_trunc('month', now()) + interval '{offset} month')::date)"
        )

    # Indexes. On PG 11+ these propagate to every existing and future partition.
    # BRIN on ts: the table is append-ordered by time, so BRIN gives range-scan
    # performance at a fraction of a btree's size.
    # Two indexes on ts, because the access patterns genuinely differ. BRIN is
    # near-free and wins on the wide aggregate scans the rollup does. It cannot
    # serve ORDER BY though, so the live tail's `ORDER BY ts DESC LIMIT n` needs
    # a btree — without it the planner falls back to a full partition scan plus
    # a sort. Write cost is low: ts is monotonic, so inserts always land on the
    # right edge of the btree.
    op.execute("CREATE INDEX ix_api_events_ts_brin ON api_events USING BRIN (ts)")
    op.execute("CREATE INDEX ix_api_events_ts_btree ON api_events (ts DESC)")
    op.execute("CREATE INDEX ix_api_events_provider_ts ON api_events (provider, ts DESC)")
    op.execute("CREATE INDEX ix_api_events_served_from_ts ON api_events (served_from, ts DESC)")
    op.execute(
        "CREATE INDEX ix_api_events_user_ts ON api_events (user_id, ts DESC) "
        "WHERE user_id IS NOT NULL"
    )
    op.execute(
        "CREATE INDEX ix_api_events_request_id ON api_events (request_id) "
        "WHERE request_id IS NOT NULL"
    )
    # The duplicate-spend query: which cache keys did we pay for more than once.
    op.execute(
        "CREATE INDEX ix_api_events_dup_keys ON api_events (cache_key, ts DESC) "
        "WHERE served_from = 'upstream' AND cache_key IS NOT NULL"
    )

    # ── api_usage_hourly ───────────────────────────────────────────────────
    op.create_table(
        "api_usage_hourly",
        sa.Column("bucket", sa.DateTime(timezone=True), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("operation", sa.String(length=64), nullable=False),
        sa.Column("served_from", sa.String(length=16), nullable=False),
        # '' not NULL: NULL never compares equal, which would defeat the PK.
        sa.Column("provider_status", sa.String(length=32), nullable=False,
                  server_default=""),
        sa.Column("calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("billable_calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("est_cost_usd", sa.Numeric(12, 6), nullable=False, server_default="0"),
        sa.Column("p50_latency_ms", sa.Integer(), nullable=True),
        sa.Column("p95_latency_ms", sa.Integer(), nullable=True),
        sa.Column("error_count", sa.Integer(), nullable=False, server_default="0"),
        sa.PrimaryKeyConstraint(
            "bucket", "provider", "operation", "served_from", "provider_status"
        ),
    )
    op.create_index("ix_api_usage_hourly_bucket", "api_usage_hourly", ["bucket"])

    # ── api_usage_user_daily ───────────────────────────────────────────────
    op.create_table(
        "api_usage_user_daily",
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("billable_calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("est_cost_usd", sa.Numeric(12, 6), nullable=False, server_default="0"),
        sa.PrimaryKeyConstraint("day", "user_id", "provider"),
    )
    op.create_index("ix_api_usage_user_daily_day", "api_usage_user_daily", ["day"])

    # ── api_sku_rates ──────────────────────────────────────────────────────
    op.create_table(
        "api_sku_rates",
        sa.Column("sku", sa.String(length=64), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("unit_cost_usd", sa.Numeric(10, 6), nullable=False),
        sa.Column("free_tier_monthly", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("sku"),
    )
    op.create_index("ix_api_sku_rates_provider", "api_sku_rates", ["provider"])

    rates = sa.table(
        "api_sku_rates",
        sa.column("sku", sa.String),
        sa.column("provider", sa.String),
        sa.column("unit_cost_usd", sa.Numeric),
        sa.column("free_tier_monthly", sa.Integer),
        sa.column("effective_from", sa.Date),
        sa.column("notes", sa.Text),
    )
    op.bulk_insert(rates, [
        {
            "sku": sku,
            "provider": provider,
            "unit_cost_usd": cost,
            "free_tier_monthly": free_tier,
            "effective_from": date(2026, 1, 1),
            "notes": notes,
        }
        for sku, provider, cost, free_tier, notes in SKU_SEED
    ])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_api_sku_rates_provider", table_name="api_sku_rates")
    op.drop_table("api_sku_rates")

    op.drop_index("ix_api_usage_user_daily_day", table_name="api_usage_user_daily")
    op.drop_table("api_usage_user_daily")

    op.drop_index("ix_api_usage_hourly_bucket", table_name="api_usage_hourly")
    op.drop_table("api_usage_hourly")

    # DROP TABLE on the parent removes every partition with it.
    op.execute("DROP TABLE IF EXISTS api_events CASCADE")
    op.execute("DROP FUNCTION IF EXISTS ensure_api_events_partition(date)")
    op.execute("DROP FUNCTION IF EXISTS drop_api_events_partitions_before(date)")
