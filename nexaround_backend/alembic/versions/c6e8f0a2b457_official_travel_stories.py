"""Official (admin-posted) travel stories

Revision ID: c6e8f0a2b457
Revises: b4d6f8a0c235
Create Date: 2026-10-19 10:00:00.000000

Stories posted from the admin panel as the nexARound account: a flag that
pins them first in the feed, a title, and the long read in light Markdown.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c6e8f0a2b457'
down_revision: Union[str, None] = 'b4d6f8a0c235'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'travel_stories',
        sa.Column('is_official', sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column('travel_stories', sa.Column('title', sa.String(200), nullable=True))
    op.add_column('travel_stories', sa.Column('article_md', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('travel_stories', 'article_md')
    op.drop_column('travel_stories', 'title')
    op.drop_column('travel_stories', 'is_official')
