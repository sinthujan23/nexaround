"""add api_alerts and spend guard settings

Stores anomaly alerts raised over api_events, and seeds the budget/quota
settings the spend guard reads.

Enforcement is seeded OFF. Turning on a spend cap that degrades user-facing
results should be a deliberate act taken with the dashboard in front of you,
not something that starts happening because a deploy went out.

Revision ID: e8f9a0b1c2d3
Revises: d7e8f9a0b1c2
Create Date: 2026-08-17 19:05:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'e8f9a0b1c2d3'
down_revision: Union[str, None] = 'd7e8f9a0b1c2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


SETTINGS_SEED = [
    ("api_monthly_budget_usd", "0",
     "Monthly ceiling for third-party API spend in USD. 0 disables the check."),
    ("api_user_daily_cap_usd", "0",
     "Per-user daily ceiling for API spend in USD. 0 disables the check."),
    ("api_budget_enforce", "false",
     "When true, paid calls are refused past the budget and cached results are "
     "served instead. When false the limits only raise alerts."),
    ("api_budget_alert_pct", "80",
     "Raise a budget alert once spend reaches this percentage of the ceiling."),
]


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "api_alerts",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=False),
        sa.Column("rule", sa.String(length=32), nullable=False),
        # What the rule fired about — a provider, an operation, or 'monthly_budget'.
        # Paired with `rule` it is the dedup key.
        sa.Column("subject", sa.String(length=128), nullable=False),
        sa.Column("severity", sa.String(length=16), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("detail", postgresql.JSONB(), nullable=True),
        sa.Column("acknowledged_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.CheckConstraint("severity IN ('info','warning','critical')",
                           name="api_alerts_severity_check"),
    )
    op.create_index("ix_api_alerts_created_at", "api_alerts",
                    [sa.text("created_at DESC")])
    # Supports the cooldown lookup, which runs on every rule evaluation.
    op.create_index("ix_api_alerts_rule_subject", "api_alerts",
                    ["rule", "subject", sa.text("created_at DESC")])
    op.create_index("ix_api_alerts_open", "api_alerts", ["created_at"],
                    postgresql_where=sa.text("acknowledged_at IS NULL"))

    # Seed the guard settings without clobbering anything already configured.
    for key, value, description in SETTINGS_SEED:
        op.execute(
            sa.text("""
                INSERT INTO system_settings (key, value, description, updated_at)
                VALUES (:key, :value, :description, now())
                ON CONFLICT (key) DO NOTHING
            """).bindparams(key=key, value=value, description=description)
        )


def downgrade() -> None:
    """Downgrade schema."""
    for key, _v, _d in SETTINGS_SEED:
        op.execute(sa.text("DELETE FROM system_settings WHERE key = :key")
                   .bindparams(key=key))
    op.drop_index("ix_api_alerts_open", table_name="api_alerts")
    op.drop_index("ix_api_alerts_rule_subject", table_name="api_alerts")
    op.drop_index("ix_api_alerts_created_at", table_name="api_alerts")
    op.drop_table("api_alerts")
