"""Add video_urls to experience_packages

Revision ID: d1e2f3a4b5c6
Revises: c0d1e2f3a4b5
Create Date: 2026-10-15 15:00:00.000000

Uploaded clips for a package, next to `photo_urls`. Existing rows get an empty
array.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'd1e2f3a4b5c6'
down_revision: Union[str, None] = 'c0d1e2f3a4b5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_packages',
        sa.Column(
            'video_urls', postgresql.ARRAY(sa.String()),
            server_default='{}', nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column('experience_packages', 'video_urls')
