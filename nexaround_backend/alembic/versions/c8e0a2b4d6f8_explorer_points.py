"""Explorer Points (TL, 2026-11-20)

explorer_point_events: the one-time carry-over of the old phone-only XP (the
rest is counted from reviews, photos and trips). place_photos.trailblazer:
the first photo of a place that had none. Indexes for counting a traveller's
photos and completed trips.

Revision ID: c8e0a2b4d6f8
Revises: b6d8f0a2c4e7
Create Date: 2026-11-20 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'c8e0a2b4d6f8'
down_revision: Union[str, None] = 'b6d8f0a2c4e7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'explorer_point_events',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('kind', sa.String(20), nullable=False),
        sa.Column('ref', sa.String(64), nullable=False),
        sa.Column('points', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('now()')),
        sa.UniqueConstraint('user_id', 'kind', 'ref',
                            name='uq_explorer_point_events_user_kind_ref'),
    )
    op.add_column('place_photos', sa.Column(
        'trailblazer', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_index('ix_place_photos_user', 'place_photos', ['user_id', 'status'])
    op.create_index('ix_itineraries_user_status', 'itineraries', ['user_id', 'status'])


def downgrade() -> None:
    op.drop_index('ix_itineraries_user_status', table_name='itineraries')
    op.drop_index('ix_place_photos_user', table_name='place_photos')
    op.drop_column('place_photos', 'trailblazer')
    op.drop_table('explorer_point_events')
