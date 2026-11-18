"""Travellers' own ratings and reviews of map places

place_reviews: one review per traveller per place, keyed by the id the app
uses for the place (Google place id, op_/ga_ free-data id, or our attraction
uuid when it has no Google id). Published at once; an admin can hide it.

Revision ID: a4c6e8f0b2d5
Revises: f3b5d7e9a1c4
Create Date: 2026-11-18 12:30:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'a4c6e8f0b2d5'
down_revision: Union[str, None] = 'f3b5d7e9a1c4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'place_reviews',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('place_key', sa.String(255), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('reviewer_name', sa.String(80), nullable=False),
        sa.Column('place_name', sa.String(255), nullable=False),
        sa.Column('latitude', sa.Float(), nullable=True),
        sa.Column('longitude', sa.Float(), nullable=True),
        sa.Column('rating', sa.SmallInteger(), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('status', sa.String(12), nullable=False, server_default='published'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('now()')),
        sa.Column('edited_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('hidden_at', sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint('user_id', 'place_key', name='uq_place_reviews_user_place'),
        sa.CheckConstraint('rating BETWEEN 1 AND 5', name='ck_place_reviews_rating'),
    )
    op.create_index('ix_place_reviews_place_status', 'place_reviews',
                    ['place_key', 'status', 'created_at'])
    op.create_index('ix_place_reviews_status_created', 'place_reviews',
                    ['status', 'created_at'])


def downgrade() -> None:
    op.drop_index('ix_place_reviews_status_created', table_name='place_reviews')
    op.drop_index('ix_place_reviews_place_status', table_name='place_reviews')
    op.drop_table('place_reviews')
