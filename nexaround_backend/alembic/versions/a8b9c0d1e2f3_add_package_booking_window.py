"""Add experience_packages.booking_window_days

Revision ID: a8b9c0d1e2f3
Revises: f7a8b9c0d1e2
Create Date: 2026-10-14 09:00:00.000000

How far ahead a traveller may ask for a date on each package, set by the vendor
or the admin. Nullable with no default: every existing package keeps the
platform's one-year window until someone chooses a shorter one.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a8b9c0d1e2f3'
down_revision: Union[str, None] = 'f7a8b9c0d1e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_packages',
        sa.Column('booking_window_days', sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_packages', 'booking_window_days')
