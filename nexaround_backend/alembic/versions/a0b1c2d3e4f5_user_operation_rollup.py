"""user × operation × source rollup, and indexes for user-filtered panels

Per-user panels were aggregating raw events. For the heaviest account that
meant a sequential scan of 66,000 rows and ~7,600 buffer hits to answer one
question, because at 63% selectivity the planner correctly declines the index —
no index fixes a query that genuinely touches most of the table.

The fix is to not touch it. api_usage_user_daily is re-cut at the granularity
the user panels actually ask for — which endpoint did they use, was it billed,
did it come from cache, the database, or a provider — so a 90-day answer reads
a few hundred pre-aggregated rows instead of scanning a partition.

Revision ID: a0b1c2d3e4f5
Revises: f9a0b1c2d3e4
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'a0b1c2d3e4f5'
down_revision: Union[str, None] = 'f9a0b1c2d3e4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Rebuilt rather than altered: the primary key changes, and the table is a
    # derived aggregate that the rollup job repopulates in one pass.
    op.drop_index("ix_api_usage_user_daily_day", table_name="api_usage_user_daily")
    op.drop_table("api_usage_user_daily")

    op.create_table(
        "api_usage_user_daily",
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("operation", sa.String(length=64), nullable=False),
        sa.Column("served_from", sa.String(length=16), nullable=False),
        sa.Column("calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("billable_calls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("est_cost_usd", sa.Numeric(12, 6), nullable=False, server_default="0"),
        sa.Column("total_tokens", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("actions", sa.Integer(), nullable=False, server_default="0"),
        sa.PrimaryKeyConstraint("day", "user_id", "provider", "operation", "served_from"),
    )
    # Leading user_id: every per-user panel filters on it first, then narrows
    # by date. The PK's leading `day` serves the opposite access pattern (the
    # top-consumers table), so both exist deliberately.
    op.create_index("ix_user_daily_user_day", "api_usage_user_daily",
                    ["user_id", sa.text("day DESC")])
    op.create_index("ix_user_daily_day", "api_usage_user_daily", ["day"])

    # Route panels group by route over a date range; without this they scan.
    op.execute("""
        CREATE INDEX ix_api_events_route_ts ON api_events (route, ts DESC)
        WHERE route IS NOT NULL
    """)
    # Token panels touch only the small subset of rows that have token counts.
    op.execute("""
        CREATE INDEX ix_api_events_tokens ON api_events (ts DESC)
        WHERE total_tokens IS NOT NULL
    """)
    # Billable-only cost queries skip the ~30% of rows that are cache hits.
    op.execute("""
        CREATE INDEX ix_api_events_billable ON api_events (sku, ts DESC)
        WHERE billable
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_api_events_billable")
    op.execute("DROP INDEX IF EXISTS ix_api_events_tokens")
    op.execute("DROP INDEX IF EXISTS ix_api_events_route_ts")
    op.drop_index("ix_user_daily_day", table_name="api_usage_user_daily")
    op.drop_index("ix_user_daily_user_day", table_name="api_usage_user_daily")
    op.drop_table("api_usage_user_daily")
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
