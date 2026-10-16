"""Confirmation and cancellation on experience enquiries

Revision ID: e5a9c3d71b28
Revises: d3f8b2a61c47
Create Date: 2026-10-16 18:00:00.000000

A request becomes a booking when the provider confirms it for a date, and
either side can cancel it; the traveller's cancellation records whether it fell
inside the 72-hour window. All NULL on existing enquiries, whose statuses
(new | contacted | closed) stay valid.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e5a9c3d71b28'
down_revision: Union[str, None] = 'd3f8b2a61c47'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('experience_enquiries', sa.Column('confirmed_date', sa.Date(), nullable=True))
    op.add_column(
        'experience_enquiries',
        sa.Column('confirmed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'experience_enquiries',
        sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'experience_enquiries', sa.Column('cancellation_reason', sa.Text(), nullable=True)
    )
    op.add_column(
        'experience_enquiries', sa.Column('late_cancellation', sa.Boolean(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'late_cancellation')
    op.drop_column('experience_enquiries', 'cancellation_reason')
    op.drop_column('experience_enquiries', 'cancelled_at')
    op.drop_column('experience_enquiries', 'confirmed_at')
    op.drop_column('experience_enquiries', 'confirmed_date')
