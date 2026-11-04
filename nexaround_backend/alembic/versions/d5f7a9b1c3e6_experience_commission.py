"""Experience packages carry NexAround's commission

An admin types what the vendor gets for each price (`vendor_amount` in each
price option) and the package's `commission_percent`; the traveller's price
(`amount`) is worked out from the two. Every package starts at 0% with its
vendor's amount equal to today's price, so no price a traveller sees moves.

Revision ID: d5f7a9b1c3e6
Revises: a2c4e6f8b0d3
Create Date: 2026-11-03 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd5f7a9b1c3e6'
down_revision: Union[str, None] = 'a2c4e6f8b0d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# Each option of a price list, in order, with `vendor_amount` set to its
# `amount` where it has none.
_WITH_VENDOR_AMOUNT = """
    (SELECT jsonb_agg(
        CASE WHEN o ? 'vendor_amount' THEN o
             ELSE o || jsonb_build_object('vendor_amount', o->'amount') END
        ORDER BY n)
     FROM jsonb_array_elements({list}) WITH ORDINALITY AS t(o, n))
"""

_WITHOUT_VENDOR_AMOUNT = """
    (SELECT jsonb_agg(o - 'vendor_amount' ORDER BY n)
     FROM jsonb_array_elements({list}) WITH ORDINALITY AS t(o, n))
"""


def upgrade() -> None:
    op.add_column(
        "experience_packages",
        sa.Column("commission_percent", sa.Numeric(5, 2), nullable=False, server_default="0"),
    )
    op.execute(
        "UPDATE experience_packages SET price_options = "
        + _WITH_VENDOR_AMOUNT.format(list="price_options")
        + " WHERE jsonb_array_length(price_options) > 0"
    )
    # A vendor's edit waiting for review carries prices of its own.
    op.execute(
        "UPDATE experience_packages SET pending_changes = jsonb_set(pending_changes, '{price_options}', "
        + _WITH_VENDOR_AMOUNT.format(list="pending_changes->'price_options'")
        + ") WHERE jsonb_typeof(pending_changes->'price_options') = 'array'"
        " AND jsonb_array_length(pending_changes->'price_options') > 0"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE experience_packages SET pending_changes = jsonb_set(pending_changes, '{price_options}', "
        + _WITHOUT_VENDOR_AMOUNT.format(list="pending_changes->'price_options'")
        + ") WHERE jsonb_typeof(pending_changes->'price_options') = 'array'"
        " AND jsonb_array_length(pending_changes->'price_options') > 0"
    )
    op.execute(
        "UPDATE experience_packages SET price_options = "
        + _WITHOUT_VENDOR_AMOUNT.format(list="price_options")
        + " WHERE jsonb_array_length(price_options) > 0"
    )
    op.drop_column("experience_packages", "commission_percent")
