"""City Tours trips can skip a step

"Skip" ends the step in hand without visiting it. It is saved in `done` like
"Mark done", at the time it was tapped, and its id goes in `skipped`.

Revision ID: a2c4e6f8b0d3
Revises: c3e5a7b9d1f4
Create Date: 2026-10-29 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'a2c4e6f8b0d3'
down_revision: Union[str, None] = 'c3e5a7b9d1f4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "city_tour_trips",
        sa.Column("skipped", postgresql.JSONB(), nullable=False, server_default="[]"),
    )


def downgrade() -> None:
    op.drop_column("city_tour_trips", "skipped")
