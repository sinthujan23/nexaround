"""Applications from businesses who want to list experiences

Revision ID: d6f8a0b2c4e7
Revises: c4e6a8b0d2f5
Create Date: 2026-10-23 09:00:00.000000

From the app's "List your experience" form; the team reviews them in Admin >
Provider applications and adds the vendor by hand.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'd6f8a0b2c4e7'
down_revision: Union[str, None] = 'c4e6a8b0d2f5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'provider_applications',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('business_name', sa.String(255), nullable=False),
        sa.Column('contact_name', sa.String(120), nullable=False),
        sa.Column('contact_phone', sa.String(32), nullable=False),
        sa.Column('contact_email', sa.String(255), nullable=False),
        sa.Column('country_code', sa.String(2), nullable=False),
        sa.Column('city', sa.String(120), nullable=True),
        sa.Column('offering', sa.Text(), nullable=False),
        sa.Column('links', sa.String(1000), nullable=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='new'),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_provider_applications_created', 'provider_applications', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_provider_applications_created', table_name='provider_applications')
    op.drop_table('provider_applications')
