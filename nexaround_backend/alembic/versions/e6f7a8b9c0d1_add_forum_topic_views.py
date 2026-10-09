"""Add forum_topic_views table for unique per-user view tracking

Revision ID: e6f7a8b9c0d1
Revises: d5e6f7a8b9c0
Create Date: 2026-10-09 03:30:00.000000

Records each user/visitor view on a forum topic so that repeated taps/visits by
the same user do not inflate topic views count.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'e6f7a8b9c0d1'
down_revision: Union[str, None] = 'd5e6f7a8b9c0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'forum_topic_views',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'topic_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('forum_topics.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column(
            'user_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='CASCADE'),
            nullable=True,
        ),
        sa.Column('ip_address', sa.String(length=45), nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
    )
    op.create_index(
        'ix_forum_topic_views_topic_user',
        'forum_topic_views',
        ['topic_id', 'user_id'],
    )
    op.create_index(
        'ix_forum_topic_views_topic_ip',
        'forum_topic_views',
        ['topic_id', 'ip_address'],
    )


def downgrade() -> None:
    op.drop_index('ix_forum_topic_views_topic_ip', table_name='forum_topic_views')
    op.drop_index('ix_forum_topic_views_topic_user', table_name='forum_topic_views')
    op.drop_table('forum_topic_views')
