"""Merge multiple migration heads

Revision ID: ddd3a740ee00
Revises: 3c2ff6573888, f1a2b3c4d5e6
Create Date: 2026-06-22 10:06:06.351380

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ddd3a740ee00'
down_revision: Union[str, None] = ('3c2ff6573888', 'f1a2b3c4d5e6')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
