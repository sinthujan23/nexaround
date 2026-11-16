"""Feature usage: feature_opens

One row per app feature an explorer looked at during one visit, for the
admin's Feature usage page.

Revision ID: c9e1a3b5d7f2
Revises: b8d0f2a4c6e1
Create Date: 2026-11-16 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = 'c9e1a3b5d7f2'
down_revision: Union[str, None] = 'b8d0f2a4c6e1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'feature_opens',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('visit_id', UUID(as_uuid=True), nullable=False),
        sa.Column('feature', sa.String(32), nullable=False),
        sa.Column('opened_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('app_version', sa.String(32), nullable=True),
        sa.Column('platform', sa.String(16), nullable=True),
        sa.UniqueConstraint('visit_id', 'feature', name='uq_feature_opens_visit_feature'),
    )
    op.create_index('ix_feature_opens_user_id', 'feature_opens', ['user_id'])
    op.create_index('ix_feature_opens_opened_at', 'feature_opens', ['opened_at'])


def downgrade() -> None:
    op.drop_index('ix_feature_opens_opened_at', table_name='feature_opens')
    op.drop_index('ix_feature_opens_user_id', table_name='feature_opens')
    op.drop_table('feature_opens')
