"""Merge the country_cities and venue_facts_sku heads

Revision ID: f0a1b2c3d4e5
Revises: c1d2e3f4a5b6, e7f8a9b0c1d2
Create Date: 2026-09-21 11:10:00.000000

Two revisions were written against the same parent (b2c3d4e5f6a7) and both were
applied, leaving the graph with two heads and `alembic upgrade head` failing
with "Multiple head revisions are present". This merges them so the experience
tables have a single parent to hang off.

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f0a1b2c3d4e5'
down_revision: Union[str, None] = ('c1d2e3f4a5b6', 'e7f8a9b0c1d2')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
