"""attractions: remember which Google place a row came from

Rows seeded from Google kept the name, the coordinates and the rating, but not
the one field that lets us ask Google anything else about the place — its Place
ID. Without it the detail page had no route back upstream: `/places/nearby`
hands the client a local UUID, the client asks `/places/search` to translate it
and gets the same UUID back, and `get_place_details` recognises a UUID and
answers from our own table. Legacy Place Details was called zero times in the
30 days before this migration while 351 detail pages were opened.

`google_place_id` closes that loop. It is nullable because the 67k rows already
in the table have no ID to backfill from; those resolve lazily, one ID-only
Find Place per place, the first time someone opens them.

`details_fetched_at` stamps the last upstream refresh so the durable fields we
write back (hours, address, photos) can be re-fetched on a 30-day cycle rather
than aging indefinitely.

Revision ID: c3d4e5f6a7b8
Revises: a1b2c3d4e5f6
Create Date: 2026-08-21 11:35:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c3d4e5f6a7b8'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "attractions",
        sa.Column("google_place_id", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "attractions",
        sa.Column("details_fetched_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Deliberately not UNIQUE. The seeders insert a whole tile of places in one
    # transaction, so a single collision — two rows for one Google place, which
    # the coordinate dedupe already makes rare — would abort the batch and throw
    # away every other place in it, then re-buy them on the next pass. Nothing
    # reads this column in the reverse direction, so the constraint would cost
    # more than it protects.
    op.create_index(
        "ix_attractions_google_place_id",
        "attractions",
        ["google_place_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_attractions_google_place_id", table_name="attractions")
    op.drop_column("attractions", "details_fetched_at")
    op.drop_column("attractions", "google_place_id")
