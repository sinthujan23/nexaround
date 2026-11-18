"""Photos travellers send for places that have none

place_photos: waits for an admin (pending), then shows for the place for
everyone (approved), or is deleted (rejected, row kept). Keyed like
place_reviews.

Revision ID: b6d8f0a2c4e7
Revises: a4c6e8f0b2d5
Create Date: 2026-11-18 14:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'b6d8f0a2c4e7'
down_revision: Union[str, None] = 'a4c6e8f0b2d5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'place_photos',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('place_key', sa.String(255), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('uploader_name', sa.String(80), nullable=False),
        sa.Column('place_name', sa.String(255), nullable=False),
        sa.Column('latitude', sa.Float(), nullable=True),
        sa.Column('longitude', sa.Float(), nullable=True),
        sa.Column('url', sa.String(255), nullable=True),
        sa.Column('width', sa.Integer(), nullable=True),
        sa.Column('height', sa.Integer(), nullable=True),
        sa.Column('size_bytes', sa.Integer(), nullable=True),
        sa.Column('status', sa.String(12), nullable=False, server_default='pending'),
        sa.Column('reject_reason', sa.String(200), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('now()')),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_place_photos_place_status', 'place_photos',
                    ['place_key', 'status', 'created_at'])
    op.create_index('ix_place_photos_status_created', 'place_photos',
                    ['status', 'created_at'])


def downgrade() -> None:
    op.drop_index('ix_place_photos_status_created', table_name='place_photos')
    op.drop_index('ix_place_photos_place_status', table_name='place_photos')
    op.drop_table('place_photos')
