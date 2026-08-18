"""telemetry: token accounting, request route, and legacy backfill

Three additions, all driven by questions the dashboard could not answer:

  tokens   Gemini bills per token, not per call, so a call count told us
           nothing about AI cost. prompt/completion/total are now recorded and
           priced from per-1k rates.
  route    Which inbound endpoint caused an upstream call. request_id already
           groups them; this names the thing being grouped.
  ingest   Distinguishes rows recorded live from the 287k api_request_logs rows
           imported below. Those predate outcome and cache recording, so they
           carry volume only — marking them keeps a real number and a
           reconstructed one from being read as the same thing.

Revision ID: f9a0b1c2d3e4
Revises: e8f9a0b1c2d3
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'f9a0b1c2d3e4'
down_revision: Union[str, None] = 'e8f9a0b1c2d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("api_events", sa.Column("prompt_tokens", sa.Integer(), nullable=True))
    op.add_column("api_events", sa.Column("completion_tokens", sa.Integer(), nullable=True))
    op.add_column("api_events", sa.Column("total_tokens", sa.Integer(), nullable=True))
    op.add_column("api_events", sa.Column("route", sa.String(length=255), nullable=True))
    # 'live' = recorded by the recorder with a real outcome.
    # 'legacy' = reconstructed from api_request_logs; volume is real, cost and
    # served_from are not known.
    op.add_column("api_events", sa.Column(
        "ingest", sa.String(length=16), nullable=False, server_default="live"))
    op.execute("CREATE INDEX ix_api_events_ingest ON api_events (ingest, ts DESC)")

    # Token-priced SKUs need per-1k rates; per-call unit_cost_usd stays 0 for them.
    op.add_column("api_sku_rates", sa.Column(
        "input_per_1k_usd", sa.Numeric(10, 8), nullable=False, server_default="0"))
    op.add_column("api_sku_rates", sa.Column(
        "output_per_1k_usd", sa.Numeric(10, 8), nullable=False, server_default="0"))

    # Gemini 2.5 Flash list pricing, ~$0.30/1M in and $2.50/1M out.
    op.execute("""
        UPDATE api_sku_rates
        SET input_per_1k_usd = 0.0003, output_per_1k_usd = 0.0025,
            notes = 'Gemini Flash is token-metered. Cost is computed from '
                    'recorded prompt/completion tokens, not per call.'
        WHERE sku = 'gemini_flash_generate'
    """)

    # Rollups carry tokens too, so the AI panel does not have to scan raw rows.
    op.add_column("api_usage_hourly", sa.Column(
        "total_tokens", sa.BigInteger(), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("api_usage_hourly", "total_tokens")
    op.drop_column("api_sku_rates", "output_per_1k_usd")
    op.drop_column("api_sku_rates", "input_per_1k_usd")
    op.execute("DROP INDEX IF EXISTS ix_api_events_ingest")
    for col in ("ingest", "route", "total_tokens", "completion_tokens", "prompt_tokens"):
        op.drop_column("api_events", col)
