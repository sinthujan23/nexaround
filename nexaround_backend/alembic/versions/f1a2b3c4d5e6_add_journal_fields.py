"""add journal fields

Revision ID: f1a2b3c4d5e6
Revises: c7ccdbe04d95
Create Date: 2026-06-22 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f1a2b3c4d5e6'
down_revision: Union[str, None] = 'c7ccdbe04d95'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('travel_stories', sa.Column('is_journal', sa.Boolean(), server_default='false', nullable=False))
    op.add_column('travel_stories', sa.Column('journal_date', sa.DateTime(timezone=True), nullable=True))
    op.add_column('travel_stories', sa.Column('total_spend', sa.Float(), server_default='0.0', nullable=False))
    op.add_column('travel_stories', sa.Column('spend_currency', sa.String(length=10), server_default='USD', nullable=False))
    op.add_column('travel_stories', sa.Column('cloud_provider', sa.String(length=50), nullable=True))
    op.add_column('travel_stories', sa.Column('cloud_folder_url', sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column('travel_stories', 'cloud_folder_url')
    op.drop_column('travel_stories', 'cloud_provider')
    op.drop_column('travel_stories', 'spend_currency')
    op.drop_column('travel_stories', 'total_spend')
    op.drop_column('travel_stories', 'journal_date')
    op.drop_column('travel_stories', 'is_journal')
