"""City Tours: trips (a traveller following a guide step by step)

city_tour_trips    one row per "Start trip": when it started, when each step
                   was marked done, and which step's reminder went out.

Revision ID: d0f2b4c6e8a1
Revises: c9e1a3b5d7f0
Create Date: 2026-10-28 12:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'd0f2b4c6e8a1'
down_revision: Union[str, None] = 'c9e1a3b5d7f0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "city_tour_trips",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "tour_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("city_tours.id", ondelete="CASCADE"), nullable=False,
        ),
        sa.Column(
            "user_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("done", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reminded_step_id", sa.String(36), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_city_tour_trips_user_tour", "city_tour_trips", ["user_id", "tour_id"])
    op.create_index("ix_city_tour_trips_started_at", "city_tour_trips", ["started_at"])


def downgrade() -> None:
    op.drop_index("ix_city_tour_trips_started_at", table_name="city_tour_trips")
    op.drop_index("ix_city_tour_trips_user_tour", table_name="city_tour_trips")
    op.drop_table("city_tour_trips")
