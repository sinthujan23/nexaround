"""Add auth_sessions and audit_events

Revision ID: b9c0d1e2f3a4
Revises: a8b9c0d1e2f3
Create Date: 2026-10-15 09:00:00.000000

The audit trail for the admin panel and the partner portal, and the table of
signed-in devices that goes with it.

`audit_events` is append-only: a trigger refuses UPDATE and DELETE. That is a
guard against the application (a bug, a future "clean up" endpoint), not
against someone with a database superuser - they can drop the trigger, which is
why the trigger's own existence is the thing to check in an audit of the audit.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'b9c0d1e2f3a4'
down_revision: Union[str, None] = 'a8b9c0d1e2f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'auth_sessions',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('actor_type', sa.String(length=10), nullable=False),
        sa.Column('actor_id', sa.String(length=255), nullable=False),
        sa.Column('actor_label', sa.String(length=255), nullable=False),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('ip', sa.String(length=64), nullable=True),
        sa.Column('last_ip', sa.String(length=64), nullable=True),
        sa.Column('user_agent', sa.String(length=512), nullable=True),
        sa.Column('browser', sa.String(length=60), nullable=True),
        sa.Column('os', sa.String(length=60), nullable=True),
        sa.Column('device_type', sa.String(length=10), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('revoked_reason', sa.String(length=20), nullable=True),
        sa.Column('revoked_by', sa.String(length=255), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_auth_sessions_actor', 'auth_sessions',
        ['actor_type', 'actor_id', 'created_at'],
    )
    op.create_index(
        'ix_auth_sessions_vendor', 'auth_sessions', ['vendor_id', 'created_at'],
    )

    op.create_table(
        'audit_events',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('occurred_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('actor_type', sa.String(length=10), nullable=False),
        sa.Column('actor_id', sa.String(length=255), nullable=True),
        sa.Column('actor_label', sa.String(length=255), nullable=True),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('session_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('category', sa.String(length=10), nullable=False),
        sa.Column('action', sa.String(length=60), nullable=False),
        sa.Column('summary', sa.String(length=300), nullable=False),
        sa.Column('method', sa.String(length=8), nullable=True),
        sa.Column('route', sa.String(length=255), nullable=True),
        sa.Column('path', sa.String(length=500), nullable=True),
        sa.Column('target_id', sa.String(length=100), nullable=True),
        sa.Column('status_code', sa.Integer(), nullable=True),
        sa.Column('success', sa.Boolean(), nullable=False),
        sa.Column('ip', sa.String(length=64), nullable=True),
        sa.Column('user_agent', sa.String(length=512), nullable=True),
        sa.Column('browser', sa.String(length=60), nullable=True),
        sa.Column('os', sa.String(length=60), nullable=True),
        sa.Column('device_type', sa.String(length=10), nullable=True),
        sa.Column('request_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('detail', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_audit_events_time', 'audit_events', ['occurred_at'])
    op.create_index(
        'ix_audit_events_actor', 'audit_events',
        ['actor_type', 'actor_id', 'occurred_at'],
    )
    op.create_index(
        'ix_audit_events_vendor', 'audit_events', ['vendor_id', 'occurred_at'],
    )

    op.execute("""
        CREATE FUNCTION audit_events_append_only() RETURNS trigger AS $$
        BEGIN
            RAISE EXCEPTION 'audit_events is append-only';
        END;
        $$ LANGUAGE plpgsql
    """)
    op.execute("""
        CREATE TRIGGER audit_events_no_change
        BEFORE UPDATE OR DELETE ON audit_events
        FOR EACH ROW EXECUTE FUNCTION audit_events_append_only()
    """)


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS audit_events_no_change ON audit_events")
    op.execute("DROP FUNCTION IF EXISTS audit_events_append_only()")
    op.drop_index('ix_audit_events_vendor', table_name='audit_events')
    op.drop_index('ix_audit_events_actor', table_name='audit_events')
    op.drop_index('ix_audit_events_time', table_name='audit_events')
    op.drop_table('audit_events')
    op.drop_index('ix_auth_sessions_vendor', table_name='auth_sessions')
    op.drop_index('ix_auth_sessions_actor', table_name='auth_sessions')
    op.drop_table('auth_sessions')
