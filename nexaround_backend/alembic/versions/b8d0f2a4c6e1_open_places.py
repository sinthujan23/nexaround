"""Free map data: open_places + open_areas

Places from Overture Maps for free users (Food & Drink, Shopping, Hotels,
Medical, Hospital), downloaded one 0.5-degree area at a time.

Revision ID: b8d0f2a4c6e1
Revises: a7c9e1f3b5d2
Create Date: 2026-11-12 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry


revision: str = 'b8d0f2a4c6e1'
down_revision: Union[str, None] = 'a7c9e1f3b5d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'open_places',
        sa.Column('id', sa.String(64), primary_key=True),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('section', sa.String(24), nullable=False),
        sa.Column('category', sa.String(64), nullable=True),
        sa.Column('latitude', sa.Float(), nullable=False),
        sa.Column('longitude', sa.Float(), nullable=False),
        sa.Column('location', Geometry(geometry_type='POINT', srid=4326, spatial_index=False), nullable=False),
        sa.Column('address', sa.String(500), nullable=True),
        sa.Column('country', sa.String(2), nullable=True),
        sa.Column('phone', sa.String(64), nullable=True),
        sa.Column('website', sa.String(500), nullable=True),
        sa.Column('social', sa.String(500), nullable=True),
        sa.Column('brand', sa.String(120), nullable=True),
        sa.Column('confidence', sa.Float(), nullable=False, server_default='0'),
        sa.Column('wiki_views', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('our_points', sa.SmallInteger(), nullable=False, server_default='0'),
        sa.Column('popularity_score', sa.SmallInteger(), nullable=False, server_default='0'),
        sa.Column('tile', sa.String(16), nullable=False),
        sa.Column('release', sa.String(32), nullable=False),
        sa.Column('imported_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index('ix_open_places_section', 'open_places', ['section'])
    op.create_index('ix_open_places_tile', 'open_places', ['tile'])
    # The nearby query filters on (location::geography) like the attractions
    # table does, so the index is on that expression.
    op.execute(
        "CREATE INDEX ix_open_places_location_geog ON open_places "
        "USING gist ((location::geography))"
    )

    op.create_table(
        'open_areas',
        sa.Column('tile', sa.String(16), primary_key=True),
        sa.Column('status', sa.String(12), nullable=False, server_default='queued'),
        sa.Column('places_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('release', sa.String(32), nullable=True),
        sa.Column('attempts', sa.SmallInteger(), nullable=False, server_default='0'),
        sa.Column('error', sa.Text(), nullable=True),
        sa.Column('seconds', sa.Float(), nullable=True),
        sa.Column('requested_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('imported_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_open_areas_status', 'open_areas', ['status'])


def downgrade() -> None:
    op.drop_index('ix_open_areas_status', table_name='open_areas')
    op.drop_table('open_areas')
    op.execute("DROP INDEX IF EXISTS ix_open_places_location_geog")
    op.drop_index('ix_open_places_tile', table_name='open_places')
    op.drop_index('ix_open_places_section', table_name='open_places')
    op.drop_table('open_places')
