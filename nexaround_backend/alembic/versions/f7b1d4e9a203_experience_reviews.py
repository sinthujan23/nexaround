"""Ratings and reviews on experience packages

Revision ID: f7b1d4e9a203
Revises: e5a9c3d71b28
Create Date: 2026-10-16 21:00:00.000000

One review per booked enquiry, with the provider's reply on the same row.
Nothing to backfill: every existing package simply has no reviews yet.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f7b1d4e9a203'
down_revision: Union[str, None] = 'e5a9c3d71b28'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'experience_reviews',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'package_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_packages.id', ondelete='CASCADE'), nullable=False,
        ),
        sa.Column(
            'vendor_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_vendors.id', ondelete='CASCADE'), nullable=False,
        ),
        sa.Column(
            'enquiry_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_enquiries.id', ondelete='CASCADE'), nullable=False,
        ),
        sa.Column(
            'user_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True,
        ),
        sa.Column('reviewer_name', sa.String(80), nullable=False),
        sa.Column('rating', sa.SmallInteger(), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('status', sa.String(12), nullable=False, server_default='published'),
        sa.Column('vendor_reply', sa.Text(), nullable=True),
        sa.Column('vendor_replied_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('edited_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('hidden_at', sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint('enquiry_id', name='uq_experience_reviews_enquiry'),
        sa.CheckConstraint('rating BETWEEN 1 AND 5', name='ck_experience_reviews_rating'),
    )
    op.create_index(
        'ix_experience_reviews_package_status', 'experience_reviews',
        ['package_id', 'status', 'created_at'],
    )
    op.create_index(
        'ix_experience_reviews_vendor_status', 'experience_reviews',
        ['vendor_id', 'status', 'created_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_experience_reviews_vendor_status', table_name='experience_reviews')
    op.drop_index('ix_experience_reviews_package_status', table_name='experience_reviews')
    op.drop_table('experience_reviews')
