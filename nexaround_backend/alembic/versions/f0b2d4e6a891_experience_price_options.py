"""Several price options per experience package

Revision ID: f0b2d4e6a891
Revises: f1a3c5e7b902
Create Date: 2026-10-22 09:00:00.000000

"LKR 30,000 per trip (max 7)" or "LKR 8,000 per person (min 3)". Every
priced package gets its current price as its one option, so nothing changes
until an admin or vendor adds another. Requests keep the option chosen.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB


# revision identifiers, used by Alembic.
revision: str = 'f0b2d4e6a891'
down_revision: Union[str, None] = 'f1a3c5e7b902'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'experience_packages',
        sa.Column('price_options', JSONB, nullable=False, server_default='[]'),
    )
    op.add_column('experience_enquiries', sa.Column('price_option', JSONB, nullable=True))
    op.execute("""
        UPDATE experience_packages
           SET price_options = jsonb_build_array(jsonb_build_object(
                 'id', substr(md5(id::text), 1, 8),
                 'amount', price_amount::float8,
                 'usd', price_usd::float8,
                 'basis', coalesce(price_basis, 'per_person'),
                 'min_people', NULL,
                 'max_people', NULL))
         WHERE price_amount IS NOT NULL AND price_basis IS DISTINCT FROM 'on_request'
    """)


def downgrade() -> None:
    op.drop_column('experience_enquiries', 'price_option')
    op.drop_column('experience_packages', 'price_options')
