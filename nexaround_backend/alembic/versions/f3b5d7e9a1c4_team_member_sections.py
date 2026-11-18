"""Team logins: content creators become team members with sections

content_creators.sections (which admin-panel areas the login opens:
city_tours, experiences, travel_bytes) and can_publish_guides (City Guides
go live without an admin's review). Existing creators keep exactly what they
had: City Tours only, every guide reviewed by an admin.

Revision ID: f3b5d7e9a1c4
Revises: e2a4c6e8f0b3
Create Date: 2026-11-18 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'f3b5d7e9a1c4'
down_revision: Union[str, None] = 'e2a4c6e8f0b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('content_creators', sa.Column(
        'sections', sa.ARRAY(sa.String(20)), nullable=False, server_default='{city_tours}',
    ))
    op.add_column('content_creators', sa.Column(
        'can_publish_guides', sa.Boolean(), nullable=False, server_default='false',
    ))


def downgrade() -> None:
    op.drop_column('content_creators', 'can_publish_guides')
    op.drop_column('content_creators', 'sections')
