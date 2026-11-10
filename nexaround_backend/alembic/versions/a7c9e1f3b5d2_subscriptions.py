"""Paid plans: subscriptions + subscription_events

One row per user per source (RevenueCat store subscription, admin grant), and a
log of every RevenueCat webhook (idempotent on event_id) for the Payments page.

Revision ID: a7c9e1f3b5d2
Revises: e8a0c2d4f6b1
Create Date: 2026-11-10 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'a7c9e1f3b5d2'
down_revision: Union[str, None] = 'e8a0c2d4f6b1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'subscriptions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('source', sa.String(20), nullable=False),
        sa.Column('plan', sa.String(20), nullable=False),
        sa.Column('period', sa.String(10), nullable=True),
        sa.Column('store', sa.String(20), nullable=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='active'),
        sa.Column('product_id', sa.String(100), nullable=True),
        sa.Column('period_start', sa.DateTime(timezone=True), nullable=True),
        sa.Column('period_end', sa.DateTime(timezone=True), nullable=True),
        sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('environment', sa.String(12), nullable=True),
        sa.Column('note', sa.String(255), nullable=True),
        sa.Column('granted_by', sa.String(100), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint('user_id', 'source', name='uq_subscriptions_user_source'),
    )
    op.create_index('ix_subscriptions_user_id', 'subscriptions', ['user_id'])

    op.create_table(
        'subscription_events',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('event_id', sa.String(100), nullable=False, unique=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('type', sa.String(40), nullable=False),
        sa.Column('product_id', sa.String(100), nullable=True),
        sa.Column('store', sa.String(20), nullable=True),
        sa.Column('environment', sa.String(12), nullable=True),
        sa.Column('price_usd', sa.Numeric(10, 2), nullable=True),
        sa.Column('currency', sa.String(8), nullable=True),
        sa.Column('price_local', sa.Numeric(12, 2), nullable=True),
        sa.Column('event_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_subscription_events_user_id', 'subscription_events', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_subscription_events_user_id', table_name='subscription_events')
    op.drop_table('subscription_events')
    op.drop_index('ix_subscriptions_user_id', table_name='subscriptions')
    op.drop_table('subscriptions')
