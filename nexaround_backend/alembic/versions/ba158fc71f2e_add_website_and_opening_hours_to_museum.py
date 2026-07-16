"""add website and opening hours to museum

Revision ID: ba158fc71f2e
Revises: e2f3a4b5c6d7
Create Date: 2026-07-16 08:55:30.548119

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ba158fc71f2e'
down_revision: Union[str, None] = 'e2f3a4b5c6d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('museums', sa.Column('website', sa.String(length=512), nullable=True))
    op.add_column('museums', sa.Column('opening_hours', sa.Text(), nullable=True))
    op.add_column('museums', sa.Column('closing_hours', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('museums', 'closing_hours')
    op.drop_column('museums', 'opening_hours')
    op.drop_column('museums', 'website')
