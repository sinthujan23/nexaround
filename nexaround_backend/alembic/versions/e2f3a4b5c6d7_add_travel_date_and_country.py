"""add travel date and country to travel story

Revision ID: e2f3a4b5c6d7
Revises: ddd3a740ee00
Create Date: 2026-06-24 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e2f3a4b5c6d7'
down_revision: Union[str, None] = 'ddd3a740ee00'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('travel_stories', sa.Column('travel_date', sa.DateTime(timezone=True), nullable=True))
    op.add_column('travel_stories', sa.Column('country', sa.String(length=100), nullable=True))


def downgrade() -> None:
    op.drop_column('travel_stories', 'country')
    op.drop_column('travel_stories', 'travel_date')
