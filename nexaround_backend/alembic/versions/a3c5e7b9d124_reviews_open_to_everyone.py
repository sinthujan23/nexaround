"""Reviews open to every signed-in traveller

Revision ID: a3c5e7b9d124
Revises: f7b1d4e9a203
Create Date: 2026-10-16 23:00:00.000000

A review is now one per (user, package) instead of one per confirmed enquiry,
so the enquiry link goes. The table was empty when this ran (the feature had
been live for hours with no review written), so nothing is converted.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'a3c5e7b9d124'
down_revision: Union[str, None] = 'f7b1d4e9a203'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('uq_experience_reviews_enquiry', 'experience_reviews', type_='unique')
    op.drop_column('experience_reviews', 'enquiry_id')
    op.create_unique_constraint(
        'uq_experience_reviews_user_package', 'experience_reviews', ['user_id', 'package_id']
    )


def downgrade() -> None:
    op.drop_constraint('uq_experience_reviews_user_package', 'experience_reviews', type_='unique')
    # Nullable: reviews written under the open rule have no enquiry to point at.
    op.add_column(
        'experience_reviews',
        sa.Column(
            'enquiry_id', postgresql.UUID(as_uuid=True),
            sa.ForeignKey('experience_enquiries.id', ondelete='CASCADE'), nullable=True,
        ),
    )
    op.create_unique_constraint('uq_experience_reviews_enquiry', 'experience_reviews', ['enquiry_id'])
