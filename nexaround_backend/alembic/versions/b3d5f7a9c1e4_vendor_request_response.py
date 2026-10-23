"""Vendors answer experience requests

Revision ID: b3d5f7a9c1e4
Revises: a2c4e6f8b0d1
Create Date: 2026-10-22 18:00:00.000000

A vendor now sees each request (package, date, guests, price - never who
asked) and answers it: confirm, offer another date (NexAround takes that to
the traveller), or cancel when no other date works. The answer is kept on the
request; confirming and cancelling also move its status as before.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3d5f7a9c1e4'
down_revision: Union[str, None] = 'a2c4e6f8b0d1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('experience_enquiries', sa.Column('vendor_response', sa.String(20), nullable=True))
    op.add_column('experience_enquiries', sa.Column('vendor_offered_date', sa.Date(), nullable=True))
    op.add_column('experience_enquiries', sa.Column('vendor_response_reason', sa.String(30), nullable=True))
    op.add_column('experience_enquiries', sa.Column('vendor_response_note', sa.Text(), nullable=True))
    op.add_column('experience_enquiries', sa.Column(
        'vendor_responded_at', sa.DateTime(timezone=True), nullable=True,
    ))
    op.create_index(
        'ix_experience_enquiries_vendor_status', 'experience_enquiries', ['vendor_id', 'status'],
    )


def downgrade() -> None:
    op.drop_index('ix_experience_enquiries_vendor_status', table_name='experience_enquiries')
    for column in ('vendor_responded_at', 'vendor_response_note', 'vendor_response_reason',
                   'vendor_offered_date', 'vendor_response'):
        op.drop_column('experience_enquiries', column)
