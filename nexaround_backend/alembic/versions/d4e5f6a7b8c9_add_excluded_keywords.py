"""admin-managed keyword list for the Around You cards

Places matching one of these keywords still show in Discover — the list only
feeds the Around You section's own client-side selection step, not the shared
banded-places fetch or cache both surfaces read from. See
`banded_places_service.get_nearby_banded` and
`living_map_page.dart`'s `_buildHiddenGemCards`.

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-08-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, None] = 'c3d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'excluded_keywords',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('keyword', sa.String(length=100), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        'ix_excluded_keywords_keyword', 'excluded_keywords', ['keyword'], unique=True,
    )


def downgrade() -> None:
    op.drop_index('ix_excluded_keywords_keyword', table_name='excluded_keywords')
    op.drop_table('excluded_keywords')
