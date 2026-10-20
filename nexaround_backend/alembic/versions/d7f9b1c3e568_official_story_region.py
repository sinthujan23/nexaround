"""Town or region on official travel stories

Revision ID: d7f9b1c3e568
Revises: c6e8f0a2b457
Create Date: 2026-10-20 09:00:00.000000

With the country it makes the label an official story shows in place of a
traveller's category ("CHINA · FURONG TOWN").
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd7f9b1c3e568'
down_revision: Union[str, None] = 'c6e8f0a2b457'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('travel_stories', sa.Column('region_label', sa.String(120), nullable=True))


def downgrade() -> None:
    op.drop_column('travel_stories', 'region_label')
