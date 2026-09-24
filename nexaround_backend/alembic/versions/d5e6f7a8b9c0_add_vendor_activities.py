"""Add vendor_activities and vendor_users.activity_seen_at

Revision ID: d5e6f7a8b9c0
Revises: c4d5e6f7a8b9
Create Date: 2026-09-24 09:00:00.000000

The activity feed behind the partner portal's bell: one row per thing that
happened to a vendor's listing, and a per-login "seen up to" watermark for the
unread count.

Existing enquiries are backfilled as "New enquiry" rows so the feed is not
empty on day one, and every existing login's watermark is set to now so that
history does not arrive as a wall of unread notifications. The text built
here matches `partner_activity.enquiry_created` in the app.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'd5e6f7a8b9c0'
down_revision: Union[str, None] = 'c4d5e6f7a8b9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'vendor_activities',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('kind', sa.String(length=40), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('body', sa.String(length=500), nullable=True),
        sa.Column('actor', sa.String(length=20), nullable=False),
        sa.Column('actor_login_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('actor_name', sa.String(length=255), nullable=True),
        sa.Column('enquiry_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('package_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ['vendor_id'], ['experience_vendors.id'], ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(
            ['actor_login_id'], ['vendor_users.id'], ondelete='SET NULL',
        ),
        sa.ForeignKeyConstraint(
            ['enquiry_id'], ['experience_enquiries.id'], ondelete='SET NULL',
        ),
        sa.ForeignKeyConstraint(
            ['package_id'], ['experience_packages.id'], ondelete='SET NULL',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_vendor_activities_vendor_created', 'vendor_activities',
        ['vendor_id', 'created_at'],
    )

    op.add_column(
        'vendor_users',
        sa.Column('activity_seen_at', sa.DateTime(timezone=True), nullable=True),
    )

    op.execute("""
        INSERT INTO vendor_activities
            (id, vendor_id, kind, title, body, actor, enquiry_id, package_id, created_at)
        SELECT
            gen_random_uuid(),
            e.vendor_id,
            'enquiry.created',
            left('New enquiry from ' || e.contact_name, 255),
            left(nullif(concat_ws(' · ',
                coalesce(e.package_title_snapshot, 'General enquiry'),
                CASE
                    WHEN e.party_size = 1 THEN '1 guest'
                    WHEN e.party_size > 1 THEN e.party_size || ' guests'
                END,
                to_char(e.preferred_date, 'FMDD Mon YYYY')
            ), ''), 500),
            'traveller',
            e.id,
            e.package_id,
            coalesce(e.created_at, now())
        FROM experience_enquiries e
        WHERE e.vendor_id IS NOT NULL
    """)
    op.execute("UPDATE vendor_users SET activity_seen_at = now()")


def downgrade() -> None:
    op.drop_column('vendor_users', 'activity_seen_at')
    op.drop_index('ix_vendor_activities_vendor_created', table_name='vendor_activities')
    op.drop_table('vendor_activities')
