"""App logins for vendors

Revision ID: f1a3c5e7b902
Revises: e8a0c2d4f679
Create Date: 2026-10-21 14:00:00.000000

An admin can give a vendor to a traveller account, which then manages it
from the app. Such a login is a `vendor_users` row with `app_user_id` and no
email or password, so it can never sign in at the web portal.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'f1a3c5e7b902'
down_revision: Union[str, None] = 'e8a0c2d4f679'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'vendor_users',
        sa.Column('app_user_id', postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        'fk_vendor_users_app_user_id_users', 'vendor_users', 'users',
        ['app_user_id'], ['id'], ondelete='CASCADE',
    )
    op.create_index('ix_vendor_users_app_user_id', 'vendor_users', ['app_user_id'])
    op.create_unique_constraint(
        'uq_vendor_users_vendor_app_user', 'vendor_users', ['vendor_id', 'app_user_id'],
    )
    op.alter_column('vendor_users', 'email', existing_type=sa.String(255), nullable=True)
    op.create_check_constraint(
        'ck_vendor_users_email_or_app_user', 'vendor_users',
        'email IS NOT NULL OR app_user_id IS NOT NULL',
    )


def downgrade() -> None:
    op.execute('DELETE FROM vendor_users WHERE email IS NULL')
    op.drop_constraint('ck_vendor_users_email_or_app_user', 'vendor_users', type_='check')
    op.alter_column('vendor_users', 'email', existing_type=sa.String(255), nullable=False)
    op.drop_constraint('uq_vendor_users_vendor_app_user', 'vendor_users', type_='unique')
    op.drop_index('ix_vendor_users_app_user_id', table_name='vendor_users')
    op.drop_constraint('fk_vendor_users_app_user_id_users', 'vendor_users', type_='foreignkey')
    op.drop_column('vendor_users', 'app_user_id')
