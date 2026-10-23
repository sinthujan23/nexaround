"""Travellers accept or decline a date the provider offered

Revision ID: c4e6a8b0d2f5
Revises: b3d5f7a9c1e4
Create Date: 2026-10-23 09:00:00.000000

When the provider cannot do the date asked and offers another, the traveller
now answers in the app: accepting confirms the booking for that date,
declining cancels the request. Their answer and its time are kept so the
admin and the provider can see it.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4e6a8b0d2f5'
down_revision: Union[str, None] = 'b3d5f7a9c1e4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('experience_enquiries', sa.Column('offer_response', sa.String(10), nullable=True))
    op.add_column('experience_enquiries', sa.Column(
        'offer_responded_at', sa.DateTime(timezone=True), nullable=True,
    ))


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'offer_responded_at')
    op.drop_column('experience_enquiries', 'offer_response')
