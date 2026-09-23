"""Add contact_instagram, contact_facebook and contact_x to experience_vendors

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-09-23 09:30:00.000000

Adds social media profile columns to experience_vendors so that vendors can provide
Instagram, Facebook, and X (Twitter) channels alongside WhatsApp and Phone.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3c4d5e6f7a8'
down_revision: Union[str, None] = 'a2b3c4d5e6f7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_vendors',
        sa.Column('contact_instagram', sa.String(length=255), nullable=True),
    )
    op.add_column(
        'experience_vendors',
        sa.Column('contact_facebook', sa.String(length=500), nullable=True),
    )
    op.add_column(
        'experience_vendors',
        sa.Column('contact_x', sa.String(length=255), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_vendors', 'contact_x')
    op.drop_column('experience_vendors', 'contact_facebook')
    op.drop_column('experience_vendors', 'contact_instagram')
