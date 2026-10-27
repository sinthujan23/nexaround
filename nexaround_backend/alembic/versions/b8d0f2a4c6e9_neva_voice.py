"""Neva voice: rates for the speech SKUs, and its two settings

Spoken Neva (app.services.neva_voice) adds four metered SKUs. Each gets a rate
row before its first call, so the dashboard never reports it at $0:

  cloud_tts_chirp3_hd      Neva's voice. Billed per character, so the "per 1k"
                           input rate is per 1,000 characters and the recorder
                           puts the character count in prompt_tokens. The first
                           1M characters a month are free; est_cost_usd does
                           not model free tiers.
  gemini_tts_lite          Gemini 3.8 Flash-Lite TTS, for languages Chirp has no
  gemini_tts_flash         voice in, and its Flash fallback. List price doubles
                           on 2027-01-01: update both with
                           PUT /api/v1/telemetry/rates/<sku> that day.
  gemini_flash_lite_audio  Transcribing the user's question (audio input bills
                           at $0.30 per 1M tokens, not text's $0.10).

Settings: voice on, 600 spoken seconds per user per day.

Revision ID: b8d0f2a4c6e9
Revises: d6f8a0b2c4e7
Create Date: 2026-10-27 09:00:00.000000
"""
from datetime import date
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b8d0f2a4c6e9'
down_revision: Union[str, None] = 'd6f8a0b2c4e7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# (sku, provider, input_per_1k, output_per_1k, notes)
NEW_RATES = [
    (
        "cloud_tts_chirp3_hd", "google_cloud", "0.03000000", "0",
        "Cloud Text-to-Speech, Chirp 3 HD voices: $30 per 1M characters, "
        "first 1M characters a month free. Input is per 1k characters.",
    ),
    (
        "gemini_tts_lite", "gemini", "0.00050000", "0.00600000",
        "Gemini 3.8 Flash-Lite TTS: $0.50 in / $6 audio out per 1M tokens "
        "(25 audio tokens a second). Doubles on 2027-01-01.",
    ),
    (
        "gemini_tts_flash", "gemini", "0.00050000", "0.00900000",
        "Gemini 3.8 Flash TTS, the Flash-Lite TTS fallback: $0.50 / $9 per 1M "
        "tokens. Doubles on 2027-01-01.",
    ),
    (
        "gemini_flash_lite_audio", "gemini", "0.00030000", "0.00040000",
        "Gemini 2.5 Flash-Lite with audio input (32 tokens a second), "
        "transcribing Neva voice questions.",
    ),
]

SETTINGS_SEED = [
    ("neva_voice_enabled", "true",
     "Neva reads her replies aloud (true) or answers in text only (false)"),
    ("neva_voice_daily_seconds", "600",
     "Seconds of Neva speech per user per day (0 = no limit)"),
]


def upgrade() -> None:
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
    existing = set(
        r[0] for r in op.get_bind().execute(sa.text("SELECT sku FROM api_sku_rates")).fetchall()
    )
    missing = [r for r in NEW_RATES if r[0] not in existing]
    if missing:
        op.bulk_insert(rates, [
            {
                "sku": sku,
                "provider": provider,
                "unit_cost_usd": "0",
                "input_per_1k_usd": inp,
                "output_per_1k_usd": out,
                "free_tier_monthly": 0,
                "effective_from": date(2026, 10, 27),
                "notes": notes,
            }
            for sku, provider, inp, out, notes in missing
        ])

    for key, value, description in SETTINGS_SEED:
        op.execute(
            sa.text("""
                INSERT INTO system_settings (key, value, description, updated_at)
                VALUES (:key, :value, :description, now())
                ON CONFLICT (key) DO NOTHING
            """).bindparams(key=key, value=value, description=description)
        )


def downgrade() -> None:
    op.execute(
        "DELETE FROM api_sku_rates WHERE sku IN "
        "('cloud_tts_chirp3_hd', 'gemini_tts_lite', 'gemini_tts_flash', "
        "'gemini_flash_lite_audio')"
    )
    for key, _v, _d in SETTINGS_SEED:
        op.execute(sa.text("DELETE FROM system_settings WHERE key = :key")
                   .bindparams(key=key))
