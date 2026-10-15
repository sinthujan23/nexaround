"""Let experience vendors and packages have no exact location

Revision ID: c0d1e2f3a4b5
Revises: b9c0d1e2f3a4
Create Date: 2026-10-15 12:00:00.000000

A vendor can now be listed by country alone. Its packages then have no point
either, so both `location` columns drop NOT NULL. Existing rows all have a
point and are untouched.

The downgrade refuses to run while any row has no location, instead of
deleting or inventing data to satisfy the constraint.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'c0d1e2f3a4b5'
down_revision: Union[str, None] = 'b9c0d1e2f3a4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TABLE experience_vendors ALTER COLUMN location DROP NOT NULL")
    op.execute("ALTER TABLE experience_packages ALTER COLUMN location DROP NOT NULL")


def downgrade() -> None:
    op.execute(
        "DO $$ BEGIN "
        "IF EXISTS (SELECT 1 FROM experience_vendors WHERE location IS NULL) "
        "OR EXISTS (SELECT 1 FROM experience_packages WHERE location IS NULL) THEN "
        "RAISE EXCEPTION 'Vendors or packages without a location exist; give them one first'; "
        "END IF; END $$"
    )
    op.execute("ALTER TABLE experience_packages ALTER COLUMN location SET NOT NULL")
    op.execute("ALTER TABLE experience_vendors ALTER COLUMN location SET NOT NULL")
