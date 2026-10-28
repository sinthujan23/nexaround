"""Neva voice: rate for transcribing on Gemini Flash

Spoken questions are now transcribed by Gemini 2.5 Flash instead of
Flash-Lite: Flash-Lite wrote "Trincomalee" as "Drink On" (2026-10-28). Flash
bills audio input at $1.00 per 1M tokens (32 a second) and output at $2.50,
so it gets its own SKU rather than Flash-Lite's audio rate.

Revision ID: c3e5a7b9d1f4
Revises: e1a3c5e7f9b2
Create Date: 2026-10-28 09:00:00.000000
"""
from datetime import date
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c3e5a7b9d1f4'
down_revision: Union[str, None] = 'e1a3c5e7f9b2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    exists = op.get_bind().execute(
        sa.text("SELECT 1 FROM api_sku_rates WHERE sku = 'gemini_flash_audio'")
    ).first()
    if exists:
        return
    rates = sa.table(
        "api_sku_rates",
        sa.column("sku", sa.String),
        sa.column("provider", sa.String),
        sa.column("unit_cost_usd", sa.Numeric),
        sa.column("input_per_1k_usd", sa.Numeric),
        sa.column("output_per_1k_usd", sa.Numeric),
        sa.column("free_tier_monthly", sa.Integer),
        sa.column("effective_from", sa.Date),
        sa.column("notes", sa.Text),
    )
    op.bulk_insert(rates, [{
        "sku": "gemini_flash_audio",
        "provider": "gemini",
        "unit_cost_usd": "0",
        "input_per_1k_usd": "0.00100000",
        "output_per_1k_usd": "0.00250000",
        "free_tier_monthly": 0,
        "effective_from": date(2026, 10, 28),
        "notes": "Gemini 2.5 Flash with audio input (32 tokens a second), "
                 "transcribing Neva voice questions.",
    }])


def downgrade() -> None:
    op.execute("DELETE FROM api_sku_rates WHERE sku = 'gemini_flash_audio'")
