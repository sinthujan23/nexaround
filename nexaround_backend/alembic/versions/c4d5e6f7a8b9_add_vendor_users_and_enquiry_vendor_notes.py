"""Add vendor_users and experience_enquiries.vendor_notes

Revision ID: c4d5e6f7a8b9
Revises: b3c4d5e6f7a8
Create Date: 2026-09-23 06:10:00.000000

Logins for the partner portal at partner.nexaround.com.

`vendor_users` is a separate table rather than a role on `users`: `get_current_user`
checks neither the token's `role` nor its `type`, so a vendor sitting in `users`
would be accepted by every traveller endpoint. Keeping the row out of that table
makes the isolation structural instead of a check someone can forget.

`vendor_notes` gives the vendor somewhere to write that is not `admin_notes` —
that column already holds the admin's private commentary, and one textarea shared
by two parties means each silently overwrites the other.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'c4d5e6f7a8b9'
down_revision: Union[str, None] = 'b3c4d5e6f7a8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'vendor_users',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('vendor_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        # Null until the invite link is used; `verify_password` treats a null
        # hash as a failed login, so an unaccepted invite cannot sign in.
        sa.Column('password_hash', sa.String(length=255), nullable=True),
        sa.Column('display_name', sa.String(length=120), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=True),
        sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('password_changed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ['vendor_id'], ['experience_vendors.id'], ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_vendor_users_vendor_id'), 'vendor_users', ['vendor_id'],
    )
    op.create_index(
        op.f('ix_vendor_users_email'), 'vendor_users', ['email'], unique=True,
    )
    op.create_index(
        op.f('ix_vendor_users_is_active'), 'vendor_users', ['is_active'],
    )

    op.add_column(
        'experience_enquiries',
        sa.Column('vendor_notes', sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'vendor_notes')
    op.drop_index(op.f('ix_vendor_users_is_active'), table_name='vendor_users')
    op.drop_index(op.f('ix_vendor_users_email'), table_name='vendor_users')
    op.drop_index(op.f('ix_vendor_users_vendor_id'), table_name='vendor_users')
    op.drop_table('vendor_users')
