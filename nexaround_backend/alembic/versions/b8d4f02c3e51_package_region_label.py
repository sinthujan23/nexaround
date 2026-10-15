"""Add region_label to experience_packages

Revision ID: b8d4f02c3e51
Revises: a7c3e91b2d40
Create Date: 2026-10-15 19:00:00.000000

Free text the admin types to say roughly where a package is, e.g. "Kerala
State · Munnar region". Shown in the app with a pin icon instead of a map
location. NULL (every existing row) shows nothing.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b8d4f02c3e51'
down_revision: Union[str, None] = 'a7c3e91b2d40'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_packages',
        sa.Column('region_label', sa.String(length=120), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_packages', 'region_label')
