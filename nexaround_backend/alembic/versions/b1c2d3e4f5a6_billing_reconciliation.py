"""actual billed cost, for reconciliation against estimates

The dashboard's cost column was modelled from hand-seeded per-call rates. Against
the real console it ran ~15x high and ranked the wrong provider first: it named
Find Place as the problem while the actual bill was almost entirely Gemini, with
Places fully absorbed by free-tier credits.

That is not fixable by editing rates more carefully. An estimate that nothing
checks will drift again. This adds the thing that checks it — actual billed cost
per SKU per day, from Google — plus the currency handling the console made
obvious was missing.

Revision ID: b1c2d3e4f5a6
Revises: a0b1c2d3e4f5
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'b1c2d3e4f5a6'
down_revision: Union[str, None] = 'a0b1c2d3e4f5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "api_billing_actual",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("usage_date", sa.Date(), nullable=False),
        sa.Column("project_id", sa.String(length=128), nullable=True),
        sa.Column("service", sa.String(length=128), nullable=False),
        sa.Column("sku", sa.String(length=256), nullable=False),
        # Google's own SKU id, stable across renames; absent in CSV exports.
        sa.Column("sku_id", sa.String(length=64), nullable=True),
        # Usage quantity and unit are what make rate derivation possible:
        # cost / usage is the real per-call price, rather than a guess.
        sa.Column("usage_amount", sa.Numeric(20, 6), nullable=True),
        sa.Column("usage_unit", sa.String(length=32), nullable=True),
        sa.Column("cost", sa.Numeric(16, 6), nullable=False, server_default="0"),
        # Free tier and promotions arrive as negative credits, which is why the
        # console shows Places at zero while usage cost is non-zero.
        sa.Column("credits", sa.Numeric(16, 6), nullable=False, server_default="0"),
        sa.Column("currency", sa.String(length=8), nullable=False, server_default="USD"),
        # Which of our operations this SKU maps to, once resolved.
        sa.Column("mapped_operation", sa.String(length=64), nullable=True),
        sa.Column("source", sa.String(length=16), nullable=False, server_default="csv"),
        sa.Column("imported_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        # Re-importing the same day must correct it, not duplicate it.
        sa.UniqueConstraint("usage_date", "project_id", "sku", "currency",
                            name="uq_billing_actual_day_sku"),
    )
    op.create_index("ix_billing_actual_date", "api_billing_actual",
                    [sa.text("usage_date DESC")])
    op.create_index("ix_billing_actual_sku", "api_billing_actual",
                    ["sku", sa.text("usage_date DESC")])

    # Rates gain a currency and a provenance flag, so a rate derived from real
    # billing is visibly different from one someone typed in.
    op.add_column("api_sku_rates", sa.Column(
        "currency", sa.String(length=8), nullable=False, server_default="USD"))
    op.add_column("api_sku_rates", sa.Column(
        "source", sa.String(length=16), nullable=False, server_default="seed"))
    op.add_column("api_sku_rates", sa.Column(
        "calibrated_at", sa.DateTime(timezone=True), nullable=True))

    for key, value, desc in [
        ("billing_currency", "INR",
         "Currency the Google Cloud billing account is denominated in."),
        ("billing_fx_to_usd", "88.0",
         "Units of billing currency per USD, for display only. Reconciliation "
         "compares like for like and does not convert."),
        ("gcp_billing_dataset", "",
         "BigQuery dataset holding the detailed usage cost export, as "
         "project.dataset. Empty until the export is enabled."),
    ]:
        op.execute(
            sa.text("""
                INSERT INTO system_settings (key, value, description, updated_at)
                VALUES (:k, :v, :d, now()) ON CONFLICT (key) DO NOTHING
            """).bindparams(k=key, v=value, d=desc)
        )


def downgrade() -> None:
    for key in ("billing_currency", "billing_fx_to_usd", "gcp_billing_dataset"):
        op.execute(sa.text("DELETE FROM system_settings WHERE key = :k").bindparams(k=key))
    op.drop_column("api_sku_rates", "calibrated_at")
    op.drop_column("api_sku_rates", "source")
    op.drop_column("api_sku_rates", "currency")
    op.drop_index("ix_billing_actual_sku", table_name="api_billing_actual")
    op.drop_index("ix_billing_actual_date", table_name="api_billing_actual")
    op.drop_table("api_billing_actual")
