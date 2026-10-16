"""Legal documents, acceptances, and the terms version on each enquiry

Revision ID: d3f8b2a61c47
Revises: c9e5a13d4f62
Create Date: 2026-10-16 12:00:00.000000

The Experience Booking Terms (travellers) and the Provider Agreement (vendors),
versioned, plus an append-only record of every acceptance. No rows are seeded
here: `legal_service.get_current` writes version 1 from `legal_texts` the first
time a document is read, so the grace periods start when the code ships.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'd3f8b2a61c47'
down_revision: Union[str, None] = 'c9e5a13d4f62'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'legal_documents',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('kind', sa.String(length=40), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column(
            'highlights', postgresql.ARRAY(sa.String()), server_default='{}',
            nullable=False,
        ),
        sa.Column('published_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_by', sa.String(length=255), nullable=True),
        sa.UniqueConstraint('kind', 'version', name='uq_legal_kind_version'),
    )
    op.create_index('ix_legal_documents_kind', 'legal_documents', ['kind'])

    op.create_table(
        'legal_acceptances',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('kind', sa.String(length=40), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column(
            'user_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True,
        ),
        sa.Column(
            'enquiry_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_enquiries.id', ondelete='SET NULL'),
            nullable=True,
        ),
        sa.Column(
            'vendor_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_vendors.id', ondelete='SET NULL'),
            nullable=True,
        ),
        sa.Column(
            'vendor_user_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('vendor_users.id', ondelete='SET NULL'), nullable=True,
        ),
        sa.Column('party_label', sa.String(length=255), nullable=True),
        sa.Column('method', sa.String(length=20), nullable=False),
        sa.Column('recorded_by', sa.String(length=255), nullable=True),
        sa.Column('note', sa.Text(), nullable=True),
        sa.Column('ip', sa.String(length=64), nullable=True),
        sa.Column('user_agent', sa.String(length=512), nullable=True),
        sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('ix_legal_acceptances_kind', 'legal_acceptances', ['kind'])
    op.create_index('ix_legal_acceptances_user_id', 'legal_acceptances', ['user_id'])
    op.create_index('ix_legal_acceptances_vendor_id', 'legal_acceptances', ['vendor_id'])
    op.create_index(
        'ix_legal_acceptances_accepted_at', 'legal_acceptances', ['accepted_at']
    )

    op.add_column(
        'experience_enquiries',
        sa.Column('terms_version', sa.Integer(), nullable=True),
    )
    op.add_column(
        'experience_enquiries',
        sa.Column('terms_accepted_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'terms_accepted_at')
    op.drop_column('experience_enquiries', 'terms_version')
    op.drop_index('ix_legal_acceptances_accepted_at', table_name='legal_acceptances')
    op.drop_index('ix_legal_acceptances_vendor_id', table_name='legal_acceptances')
    op.drop_index('ix_legal_acceptances_user_id', table_name='legal_acceptances')
    op.drop_index('ix_legal_acceptances_kind', table_name='legal_acceptances')
    op.drop_table('legal_acceptances')
    op.drop_index('ix_legal_documents_kind', table_name='legal_documents')
    op.drop_table('legal_documents')
