"""Add experience vendor, package and enquiry tables

Revision ID: a2b3c4d5e6f7
Revises: f0a1b2c3d4e5
Create Date: 2026-09-21 11:15:00.000000

The first-party vendor marketplace behind the Discovery "Experiences" tab.

Note on indexes: the geometry columns are declared with spatial_index=False so
geoalchemy2 does not auto-emit `idx_<table>_<column>`; every index here is
created explicitly, which keeps the names predictable and stops startup
`create_all` from racing this migration. The index the Discovery query actually
rides is the *geography-cast, partial* one on experience_packages — a plain
geometry index will not serve a KNN ordered by `geography(location) <-> ...`.

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import geoalchemy2
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'a2b3c4d5e6f7'
down_revision: Union[str, None] = 'f0a1b2c3d4e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _point():
    return geoalchemy2.types.Geometry(
        geometry_type='POINT', srid=4326, spatial_index=False,
    )


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'experience_vendors',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('location', _point(), nullable=False),
        sa.Column('address', sa.String(length=500), nullable=True),
        sa.Column('google_place_id', sa.String(length=255), nullable=True),
        sa.Column('city', sa.String(length=120), nullable=True),
        sa.Column('country_code', sa.String(length=2), nullable=True),
        sa.Column('contact_phone', sa.String(length=32), nullable=True),
        sa.Column('contact_whatsapp', sa.String(length=32), nullable=True),
        sa.Column('contact_email', sa.String(length=255), nullable=True),
        sa.Column('website', sa.String(length=500), nullable=True),
        sa.Column('logo_url', sa.String(length=500), nullable=True),
        sa.Column('photo_urls', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('rating', sa.Numeric(precision=3, scale=2), nullable=True),
        sa.Column('review_count', sa.Integer(), nullable=True),
        sa.Column('internal_notes', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=True),
        sa.Column('sort_order', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_experience_vendors_name'), 'experience_vendors', ['name'])
    op.create_index(
        op.f('ix_experience_vendors_google_place_id'),
        'experience_vendors', ['google_place_id'],
    )
    op.create_index(
        op.f('ix_experience_vendors_is_active'), 'experience_vendors', ['is_active'],
    )

    op.create_table(
        'experience_packages',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('summary', sa.String(length=500), nullable=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('category', sa.String(length=60), nullable=True),
        sa.Column('tags', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('photo_urls', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('price_amount', sa.Numeric(precision=12, scale=2), nullable=True),
        sa.Column('price_currency', sa.String(length=10), nullable=True),
        sa.Column('price_basis', sa.String(length=20), nullable=True),
        sa.Column('duration_minutes', sa.Integer(), nullable=True),
        sa.Column('max_participants', sa.Integer(), nullable=True),
        sa.Column('inclusions', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('languages', postgresql.ARRAY(sa.String()), nullable=True),
        sa.Column('location', _point(), nullable=False),
        sa.Column('uses_vendor_location', sa.Boolean(), nullable=True),
        sa.Column('meeting_point_address', sa.String(length=500), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=True),
        sa.Column('is_published', sa.Boolean(), nullable=True),
        sa.Column('sort_order', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ['vendor_id'], ['experience_vendors.id'], ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_experience_packages_vendor_id'), 'experience_packages', ['vendor_id'],
    )
    op.create_index(
        op.f('ix_experience_packages_title'), 'experience_packages', ['title'],
    )
    op.create_index(
        op.f('ix_experience_packages_category'), 'experience_packages', ['category'],
    )
    op.create_index(
        op.f('ix_experience_packages_is_published'),
        'experience_packages', ['is_published'],
    )

    op.create_table(
        'experience_enquiries',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('package_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('package_title_snapshot', sa.String(length=255), nullable=True),
        sa.Column('vendor_name_snapshot', sa.String(length=255), nullable=True),
        sa.Column('contact_name', sa.String(length=120), nullable=False),
        sa.Column('contact_phone', sa.String(length=32), nullable=False),
        sa.Column('contact_email', sa.String(length=255), nullable=True),
        sa.Column('preferred_date', sa.Date(), nullable=True),
        sa.Column('party_size', sa.Integer(), nullable=True),
        sa.Column('message', sa.Text(), nullable=True),
        sa.Column('status', sa.String(length=20), nullable=True),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ['package_id'], ['experience_packages.id'], ondelete='SET NULL',
        ),
        sa.ForeignKeyConstraint(
            ['vendor_id'], ['experience_vendors.id'], ondelete='SET NULL',
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_experience_enquiries_package_id'),
        'experience_enquiries', ['package_id'],
    )
    op.create_index(
        op.f('ix_experience_enquiries_vendor_id'),
        'experience_enquiries', ['vendor_id'],
    )
    op.create_index(
        op.f('ix_experience_enquiries_user_id'), 'experience_enquiries', ['user_id'],
    )
    op.create_index(
        op.f('ix_experience_enquiries_status'), 'experience_enquiries', ['status'],
    )
    op.create_index(
        op.f('ix_experience_enquiries_created_at'),
        'experience_enquiries', ['created_at'],
    )

    # Plain geometry GiST — for any future bounding-box / map query.
    op.execute(
        "CREATE INDEX idx_experience_vendors_location "
        "ON experience_vendors USING gist (location)"
    )
    op.execute(
        "CREATE INDEX idx_experience_packages_location "
        "ON experience_packages USING gist (location)"
    )

    # The index the Discovery nearest-first query rides. Geography-cast because
    # the KNN operator and ST_Distance both work in metres on geography, and
    # partial because every app-facing read filters is_published.
    op.execute(
        "CREATE INDEX idx_experience_packages_location_geog "
        "ON experience_packages USING gist (((location)::geography)) "
        "WHERE is_published"
    )

    # Backfill a hand-made index that exists in production but in no migration:
    # without it a database rebuilt from migrations alone silently drops every
    # attractions spatial query to a sequential scan.
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_attractions_location_geog "
        "ON attractions USING gist (((location)::geography))"
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DROP INDEX IF EXISTS idx_experience_packages_location_geog")
    op.execute("DROP INDEX IF EXISTS idx_experience_packages_location")
    op.execute("DROP INDEX IF EXISTS idx_experience_vendors_location")
    # idx_attractions_location_geog is deliberately left in place: it predates
    # this migration in production and dropping it would slow unrelated queries.
    op.drop_table('experience_enquiries')
    op.drop_table('experience_packages')
    op.drop_table('experience_vendors')
