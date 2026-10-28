"""City Tours trips follow one day of a guide

Guides now have days (app/services/city_tours.py). A trip follows one of them;
NULL is a trip started before days existed, read as the guide's first day.

Revision ID: e1a3c5e7f9b2
Revises: d0f2b4c6e8a1
Create Date: 2026-10-28 13:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e1a3c5e7f9b2'
down_revision: Union[str, None] = 'd0f2b4c6e8a1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("city_tour_trips", sa.Column("day_id", sa.String(36), nullable=True))


def downgrade() -> None:
    op.drop_column("city_tour_trips", "day_id")
