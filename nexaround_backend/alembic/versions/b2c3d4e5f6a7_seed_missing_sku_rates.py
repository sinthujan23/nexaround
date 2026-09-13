"""telemetry: rate the SKUs that were being billed at zero

Five SKUs were reaching `_to_row` with no rate row, so every call of theirs
was recorded at $0 and the dashboard under-reported real spend:

  gemini_flash_grounded       The single largest Gemini line — the day-by-day
                              itinerary generation. Never seeded, because the
                              SKU was introduced in code after the seed
                              migration.
  gemini_flash_lite_generate  New: the helper calls (airport lookup, flight
  gemini_pro_generate         copy, estimates) now pick their own model chain,
                              and the rotation can still land on pro. Billing
                              them at Flash's rate would flatter the cheap
                              chain and hide the expensive fallback.
  text_search_pro             Places text search behind destination and
                              airport resolution. Inside the free tier today,
                              but priced so the free tier is visibly consumed.
  serpapi_search              Seeded at 0 with a note to set it from the active
                              plan; nobody did, so the largest cash cost in
                              the Odyssey pipeline read as free.

Insert-only: a rate that has already been calibrated against a real bill
(`source='billing'`) is left exactly as it is.

Revision ID: b2c3d4e5f6a7
Revises: a7b8c9d0e1f2
"""
from datetime import date
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, None] = 'a7b8c9d0e1f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# (sku, provider, unit_cost_usd, input_per_1k, output_per_1k, free_tier, notes)
#
# Gemini 2.5 list prices, per 1M tokens, expressed per 1k:
#   Flash       $0.30 in / $2.50 out
#   Flash-Lite  $0.10 in / $0.40 out
#   Pro         $1.25 in / $10.00 out
NEW_RATES = [
    (
        "gemini_flash_grounded", "gemini", "0", "0.00030000", "0.00250000", 0,
        "Gemini 2.5 Flash with google_search grounding. Token cost only: "
        "grounding is free to 1,500 requests/day and the per-request fee "
        "beyond that is not modelled here.",
    ),
    (
        "gemini_flash_lite_generate", "gemini", "0", "0.00010000", "0.00040000", 0,
        "Gemini 2.5 Flash-Lite — the cheap chain used for airport lookups, "
        "flight/hotel copy and estimates.",
    ),
    (
        "gemini_pro_generate", "gemini", "0", "0.00125000", "0.01000000", 0,
        "Gemini 2.5 Pro. Only reached as the last rung of the model rotation "
        "when Flash and Flash-Lite are both failing, so a rising count here "
        "means an outage, not a choice.",
    ),
    (
        "text_search_pro", "google_maps", "0.032000", "0", "0", 5000,
        "Places API (New) searchText with the Pro field mask (location, "
        "address components, types).",
    ),
]

# Priced, not inserted: the row exists at 0 from the original seed.
SERPAPI_UNIT_COST = "0.015000"   # Developer plan: $75 / 5,000 searches.


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
                "unit_cost_usd": unit,
                "input_per_1k_usd": inp,
                "output_per_1k_usd": out,
                "free_tier_monthly": free_tier,
                "effective_from": date(2026, 1, 1),
                "notes": notes,
            }
            for sku, provider, unit, inp, out, free_tier, notes in missing
        ])

    # Only if nobody has priced it from a real invoice since.
    op.execute(
        sa.text(
            "UPDATE api_sku_rates SET unit_cost_usd = CAST(:cost AS NUMERIC), "
            "notes = :notes "
            "WHERE sku = 'serpapi_search' AND unit_cost_usd = 0"
        ).bindparams(
            cost=SERPAPI_UNIT_COST,
            notes=(
                "SerpAPI Developer plan: $75 / 5,000 searches. Change with "
                "PUT /api/v1/telemetry/rates/serpapi_search when the plan changes."
            ),
        )
    )


def downgrade() -> None:
    op.execute(
        "DELETE FROM api_sku_rates WHERE sku IN "
        "('gemini_flash_grounded', 'gemini_flash_lite_generate', "
        "'gemini_pro_generate', 'text_search_pro')"
    )
    op.execute(
        "UPDATE api_sku_rates SET unit_cost_usd = 0 WHERE sku = 'serpapi_search'"
    )
