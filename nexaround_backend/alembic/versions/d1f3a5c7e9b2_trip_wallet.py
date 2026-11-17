"""Trip Wallet: group trip expense ledger

wallet_trips, wallet_members, wallet_expenses, wallet_expense_shares,
wallet_settlements (app/models/trip_wallet.py).

Revision ID: d1f3a5c7e9b2
Revises: c9e1a3b5d7f2
Create Date: 2026-11-17 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = 'd1f3a5c7e9b2'
down_revision: Union[str, None] = 'c9e1a3b5d7f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'wallet_trips',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('owner_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(80), nullable=False),
        sa.Column('currency', sa.String(3), nullable=False),
        sa.Column('invite_code', sa.String(8), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_wallet_trips_owner_id', 'wallet_trips', ['owner_id'])
    op.create_index('ix_wallet_trips_invite_code', 'wallet_trips', ['invite_code'], unique=True)

    op.create_table(
        'wallet_members',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('trip_id', UUID(as_uuid=True), sa.ForeignKey('wallet_trips.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('display_name', sa.String(100), nullable=False),
        sa.Column('role', sa.String(10), nullable=False),
        sa.Column('joined_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('left_at', sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint('trip_id', 'user_id', name='uq_wallet_members_trip_user'),
    )
    op.create_index('ix_wallet_members_trip_id', 'wallet_members', ['trip_id'])
    op.create_index('ix_wallet_members_user_id', 'wallet_members', ['user_id'])

    op.create_table(
        'wallet_expenses',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('trip_id', UUID(as_uuid=True), sa.ForeignKey('wallet_trips.id', ondelete='CASCADE'), nullable=False),
        sa.Column('paid_by_member_id', UUID(as_uuid=True), sa.ForeignKey('wallet_members.id', ondelete='CASCADE'), nullable=False),
        sa.Column('title', sa.String(120), nullable=False),
        sa.Column('category', sa.String(20), nullable=False),
        sa.Column('amount_minor', sa.BigInteger(), nullable=False),
        sa.Column('spent_on', sa.Date(), nullable=False),
        sa.Column('receipt_url', sa.String(500), nullable=True),
        sa.Column('split_mode', sa.String(10), nullable=False),
        sa.Column('created_by_user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_wallet_expenses_trip', 'wallet_expenses', ['trip_id', 'spent_on'])

    op.create_table(
        'wallet_expense_shares',
        sa.Column('expense_id', UUID(as_uuid=True), sa.ForeignKey('wallet_expenses.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('member_id', UUID(as_uuid=True), sa.ForeignKey('wallet_members.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('amount_minor', sa.BigInteger(), nullable=False),
    )

    op.create_table(
        'wallet_settlements',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('trip_id', UUID(as_uuid=True), sa.ForeignKey('wallet_trips.id', ondelete='CASCADE'), nullable=False),
        sa.Column('from_member_id', UUID(as_uuid=True), sa.ForeignKey('wallet_members.id', ondelete='CASCADE'), nullable=False),
        sa.Column('to_member_id', UUID(as_uuid=True), sa.ForeignKey('wallet_members.id', ondelete='CASCADE'), nullable=False),
        sa.Column('amount_minor', sa.BigInteger(), nullable=False),
        sa.Column('created_by_user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('ix_wallet_settlements_trip_id', 'wallet_settlements', ['trip_id'])


def downgrade() -> None:
    op.drop_index('ix_wallet_settlements_trip_id', table_name='wallet_settlements')
    op.drop_table('wallet_settlements')
    op.drop_table('wallet_expense_shares')
    op.drop_index('ix_wallet_expenses_trip', table_name='wallet_expenses')
    op.drop_table('wallet_expenses')
    op.drop_index('ix_wallet_members_user_id', table_name='wallet_members')
    op.drop_index('ix_wallet_members_trip_id', table_name='wallet_members')
    op.drop_table('wallet_members')
    op.drop_index('ix_wallet_trips_invite_code', table_name='wallet_trips')
    op.drop_index('ix_wallet_trips_owner_id', table_name='wallet_trips')
    op.drop_table('wallet_trips')
