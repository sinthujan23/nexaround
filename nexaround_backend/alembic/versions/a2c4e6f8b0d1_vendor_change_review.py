"""Admin review of vendors' own edits

Revision ID: a2c4e6f8b0d1
Revises: f0b2d4e6a891
Create Date: 2026-10-22 16:00:00.000000

A vendor's package and profile edits now wait for an admin: the live columns
keep showing while `pending_changes` holds the proposal. A package a vendor
adds has no `approved_at` and stays unpublished until approved. Everything
that exists today was made or accepted already, so it counts as approved.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'a2c4e6f8b0d1'
down_revision: Union[str, None] = 'f0b2d4e6a891'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _review_columns(table: str) -> None:
    op.add_column(table, sa.Column(
        'review_status', sa.String(20), nullable=False, server_default='approved',
    ))
    op.add_column(table, sa.Column('pending_changes', postgresql.JSONB(), nullable=True))
    op.add_column(table, sa.Column('review_note', sa.Text(), nullable=True))
    op.add_column(table, sa.Column('submitted_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column(table, sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index(f'ix_{table}_review_status', table, ['review_status'])


def upgrade() -> None:
    _review_columns('experience_packages')
    _review_columns('experience_vendors')
    op.add_column('experience_packages', sa.Column(
        'approved_at', sa.DateTime(timezone=True), nullable=True,
    ))
    op.execute(
        "UPDATE experience_packages SET approved_at = COALESCE(created_at, now())"
    )


def downgrade() -> None:
    op.drop_column('experience_packages', 'approved_at')
    for table in ('experience_vendors', 'experience_packages'):
        op.drop_index(f'ix_{table}_review_status', table_name=table)
        for column in ('reviewed_at', 'submitted_at', 'review_note', 'pending_changes', 'review_status'):
            op.drop_column(table, column)
