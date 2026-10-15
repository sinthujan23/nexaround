"""Add pickup_location to experience_enquiries

Revision ID: c9e5a13d4f62
Revises: b8d4f02c3e51
Create Date: 2026-10-15 20:00:00.000000

Where the traveller wants picking up: a Google place they chose or text they
typed. Optional; NULL on every existing enquiry.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c9e5a13d4f62'
down_revision: Union[str, None] = 'b8d4f02c3e51'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_enquiries',
        sa.Column('pickup_location', sa.String(length=500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'pickup_location')
