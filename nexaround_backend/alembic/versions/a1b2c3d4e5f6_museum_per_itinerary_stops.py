"""museum masterpieces: a stop number per itinerary

One `rank` column cannot hold three walking orders. The Acropolis sheet gives a
different stop number for the same exhibit in each itinerary — 41 of its 50
five-hour exhibits sit at a different position in the one-day tour — so storing
a single rank meant two of the three orders were lost, and the seeder papered
over it by re-sorting on the inclusion flags, which put 101 of 113 exhibits in
the wrong place.

Each itinerary now carries its own stop number. Nullable on purpose: museums
seeded before this change have none, and the itinerary query falls back to
`rank` for them.

Revision ID: a1b2c3d4e5f6
Revises: b1c2d3e4f5a6
Create Date: 2026-08-21 07:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'b1c2d3e4f5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for column in ('stop_3h', 'stop_5h', 'stop_1d', 'stop_2d'):
        op.add_column(
            'museum_masterpieces',
            sa.Column(column, sa.Integer(), nullable=True),
        )


def downgrade() -> None:
    for column in ('stop_2d', 'stop_1d', 'stop_5h', 'stop_3h'):
        op.drop_column('museum_masterpieces', column)
