"""Price the Places call that checks a venue's rating and opening hours.

The Odyssey used to print the model's own star ratings. Audited against the
live API on 2026-09-16, only 24% of them matched Google and 10% were out by
half a star or more, so `venue_facts_service` now looks them up instead. That
lookup asks for `rating`, `userRatingCount` and `regularOpeningHours`, which
Places API (New) bills at its dearest Text Search tier — Enterprise +
Atmosphere, $0.040 per request against the Pro mask's $0.032.

Given a SKU of its own rather than folded into `text_search_pro` so the
dashboard can show what this verification costs, separately from the cheaper
identity lookups that share the endpoint. Cached 30 days per venue, so a city
whose restaurants recur across plans pays once a month.

Revision ID: e7f8a9b0c1d2
Revises: b2c3d4e5f6a7
"""
from datetime import date

import sqlalchemy as sa
from alembic import op

revision = "e7f8a9b0c1d2"
down_revision = "b2c3d4e5f6a7"
branch_labels = None
depends_on = None

SKU = "text_search_atmosphere"


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
    exists = op.get_bind().execute(
        sa.text("SELECT 1 FROM api_sku_rates WHERE sku = :sku"), {"sku": SKU},
    ).first()
    if exists:
        return
    op.bulk_insert(rates, [{
        "sku": SKU,
        "provider": "google_maps",
        "unit_cost_usd": "0.040000",
        "input_per_1k_usd": "0",
        "output_per_1k_usd": "0",
        "free_tier_monthly": 5000,
        "effective_from": date(2026, 1, 1),
        "notes": (
            "Places API (New) searchText with the Enterprise + Atmosphere field "
            "mask (rating, userRatingCount, regularOpeningHours). Spent by "
            "venue_facts_service to check the ratings and hours an Odyssey "
            "shows. Cached 30 days per venue."
        ),
    }])


def downgrade() -> None:
    op.execute(sa.text("DELETE FROM api_sku_rates WHERE sku = :sku").bindparams(sku=SKU))
