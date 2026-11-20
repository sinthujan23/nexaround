"""Museums entered in the admin panel: museums.is_hidden

A museum being entered stays out of the app until someone switches it on.
Every museum that exists already is live, so it stays shown.

Revision ID: d2f4a6c8e0b1
Revises: c8e0a2b4d6f8
Create Date: 2026-11-20 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd2f4a6c8e0b1'
down_revision: Union[str, None] = 'c8e0a2b4d6f8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('museums', sa.Column(
        'is_hidden', sa.Boolean(), nullable=False, server_default='false',
    ))


def downgrade() -> None:
    op.drop_column('museums', 'is_hidden')
