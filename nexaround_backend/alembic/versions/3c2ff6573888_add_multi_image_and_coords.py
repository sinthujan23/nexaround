"""add multi image and coords to travel story

Revision ID: 3c2ff6573888
Revises: 2b1ee5462967
Create Date: 2026-06-19 11:25:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '3c2ff6573888'
down_revision: Union[str, None] = '2b1ee5462967'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # travel_stories table
    op.add_column('travel_stories', sa.Column('image_urls', postgresql.ARRAY(sa.String()), server_default='{}', nullable=False))
    op.add_column('travel_stories', sa.Column('latitude', sa.Float(), nullable=True))
    op.add_column('travel_stories', sa.Column('longitude', sa.Float(), nullable=True))
    
    # travel_story_comments table
    op.add_column('travel_story_comments', sa.Column('image_index', sa.Integer(), server_default='0', nullable=False))


def downgrade() -> None:
    # travel_story_comments table
    op.drop_column('travel_story_comments', 'image_index')
    
    # travel_stories table
    op.drop_column('travel_stories', 'longitude')
    op.drop_column('travel_stories', 'latitude')
    op.drop_column('travel_stories', 'image_urls')
