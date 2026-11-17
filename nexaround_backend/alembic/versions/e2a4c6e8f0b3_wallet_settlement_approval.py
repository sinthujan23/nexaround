"""Trip Wallet: the owner approves each payment

wallet_settlements.status (pending|confirmed) and approved_at. Payments
recorded before this were all counted at once, so they stay confirmed.

Revision ID: e2a4c6e8f0b3
Revises: d1f3a5c7e9b2
Create Date: 2026-11-17 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e2a4c6e8f0b3'
down_revision: Union[str, None] = 'd1f3a5c7e9b2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('wallet_settlements', sa.Column(
        'status', sa.String(10), nullable=False, server_default='confirmed',
    ))
    op.add_column('wallet_settlements', sa.Column(
        'approved_at', sa.DateTime(timezone=True), nullable=True,
    ))


def downgrade() -> None:
    op.drop_column('wallet_settlements', 'approved_at')
    op.drop_column('wallet_settlements', 'status')
