"""IP address ranges and their country, for the admin Explorers page

DB-IP's free "IP to Country Lite" list (CC BY 4.0), about 730,000 ranges.
The worker fills and refreshes it each month (app/services/ip_country.py);
this only creates the empty table.

Revision ID: e8a0c2d4f6b1
Revises: d5f7a9b1c3e6
Create Date: 2026-11-04 06:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'e8a0c2d4f6b1'
down_revision: Union[str, None] = 'd5f7a9b1c3e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'ip_country_ranges',
        sa.Column('ip_from', postgresql.INET(), primary_key=True),
        sa.Column('ip_to', postgresql.INET(), nullable=False),
        sa.Column('country_code', sa.String(2), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('ip_country_ranges')
