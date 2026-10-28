"""City Tours: guides, content creators and partner-link taps

content_creators   logins for the people who write guides (admin panel, role
                   "creator"); kept out of `users` like vendor logins.
city_tours         one guide each: the working copy (`content`) and the copy
                   the app shows (`live_content`, set when an admin approves).
city_tour_taps     one row per traveller tap on a partner link in a guide.

Revision ID: c9e1a3b5d7f0
Revises: b8d0f2a4c6e9
Create Date: 2026-10-28 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'c9e1a3b5d7f0'
down_revision: Union[str, None] = 'b8d0f2a4c6e9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "content_creators",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("password_changed_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "city_tours",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "creator_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("content_creators.id", ondelete="SET NULL"), nullable=True,
        ),
        sa.Column("author_name", sa.String(120), nullable=False),
        sa.Column("content", postgresql.JSONB(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("review_status", sa.String(20), nullable=False, server_default="draft"),
        sa.Column("review_note", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_by", sa.String(120), nullable=True),
        sa.Column("live_content", postgresql.JSONB(), nullable=True),
        sa.Column("live_version", sa.Integer(), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("live_updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_hidden", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_city_tours_creator_id", "city_tours", ["creator_id"])
    op.create_index("ix_city_tours_review_status", "city_tours", ["review_status"])

    op.create_table(
        "city_tour_taps",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "tour_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("city_tours.id", ondelete="CASCADE"), nullable=False,
        ),
        sa.Column("link_id", sa.String(36), nullable=False),
        sa.Column("partner", sa.String(40), nullable=False),
        sa.Column("package_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "user_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_city_tour_taps_tour_link", "city_tour_taps", ["tour_id", "link_id"])
    op.create_index("ix_city_tour_taps_created_at", "city_tour_taps", ["created_at"])


def downgrade() -> None:
    op.drop_table("city_tour_taps")
    op.drop_table("city_tours")
    op.drop_table("content_creators")
