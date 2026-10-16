"""Daily currency exchange rates

Revision ID: b4d6f8a0c235
Revises: a3c5e7b9d124
Create Date: 2026-10-16 19:30:00.000000

One row per base currency, refreshed by the worker once a day.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'b4d6f8a0c235'
down_revision: Union[str, None] = 'a3c5e7b9d124'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'fx_rates',
        sa.Column('base', sa.String(3), primary_key=True),
        sa.Column('rates', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('source', sa.String(40), nullable=False),
        sa.Column('provider_updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('provider_next_update_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_attempt_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_error', sa.Text(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table('fx_rates')
