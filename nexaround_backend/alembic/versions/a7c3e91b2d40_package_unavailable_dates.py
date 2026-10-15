"""Add unavailable_ranges to experience_packages

Revision ID: a7c3e91b2d40
Revises: d1e2f3a4b5c6
Create Date: 2026-10-15 17:00:00.000000

Date ranges a package cannot be booked, set by the admin or the vendor. Empty
(the default for every existing row) means available every day.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'a7c3e91b2d40'
down_revision: Union[str, None] = 'd1e2f3a4b5c6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_packages',
        sa.Column(
            'unavailable_ranges', postgresql.JSONB(),
            server_default='[]', nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column('experience_packages', 'unavailable_ranges')
