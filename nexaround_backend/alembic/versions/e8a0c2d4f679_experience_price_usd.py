"""US dollar price on experience packages

Revision ID: e8a0c2d4f679
Revises: d7f9b1c3e568
Create Date: 2026-10-21 09:00:00.000000

Typed by the admin next to the vendor's own price and shown in brackets
("QAR 499 ($137)"), in place of a daily exchange-rate conversion.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e8a0c2d4f679'
down_revision: Union[str, None] = 'd7f9b1c3e568'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('experience_packages', sa.Column('price_usd', sa.Numeric(12, 2), nullable=True))


def downgrade() -> None:
    op.drop_column('experience_packages', 'price_usd')
