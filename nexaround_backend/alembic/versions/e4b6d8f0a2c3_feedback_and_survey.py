"""Explorer feedback, quick ratings and the quarterly survey

Revision ID: e4b6d8f0a2c3
Revises: d2f4a6c8e0b1
Create Date: 2026-11-26 09:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = 'e4b6d8f0a2c3'
down_revision: Union[str, None] = 'd2f4a6c8e0b1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'feedback',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('kind', sa.String(10), nullable=False, server_default='message'),
        sa.Column('type', sa.String(12), nullable=False),
        sa.Column('text', sa.Text(), nullable=True),
        sa.Column('reasons', postgresql.ARRAY(sa.String(32)), nullable=False, server_default='{}'),
        sa.Column('screenshots', postgresql.ARRAY(sa.String(64)), nullable=False, server_default='{}'),
        sa.Column('can_reply', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('feature', sa.String(32), nullable=True),
        sa.Column('ref_id', sa.String(64), nullable=True),
        sa.Column('ref_label', sa.String(200), nullable=True),
        sa.Column('source_screen', sa.String(40), nullable=True),
        sa.Column('app_version', sa.String(32), nullable=True),
        sa.Column('platform', sa.String(16), nullable=True),
        sa.Column('os_version', sa.String(80), nullable=True),
        sa.Column('country', sa.String(2), nullable=True),
        sa.Column('status', sa.String(12), nullable=False, server_default='new'),
        sa.Column('replies', postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("kind IN ('message', 'quick')", name='ck_feedback_kind'),
    )
    op.create_index('ix_feedback_user_id', 'feedback', ['user_id'])
    op.create_index('ix_feedback_status_created', 'feedback', ['status', 'created_at'])
    op.create_index('ix_feedback_kind_created', 'feedback', ['kind', 'created_at'])
    op.create_index('uq_feedback_quick_ref', 'feedback', ['user_id', 'feature', 'ref_id'],
                    unique=True, postgresql_where=sa.text("kind = 'quick'"))

    op.create_table(
        'survey_rounds',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(60), nullable=False),
        sa.Column('starts_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('ends_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_open', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('build_next_options', postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    op.create_table(
        'survey_responses',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('round_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('survey_rounds.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('nps', sa.SmallInteger(), nullable=False),
        sa.Column('features', postgresql.ARRAY(sa.String(32)), nullable=False, server_default='{}'),
        sa.Column('build_next', postgresql.ARRAY(sa.String(40)), nullable=False, server_default='{}'),
        sa.Column('build_next_other', sa.String(300), nullable=True),
        sa.Column('would_pay', sa.String(6), nullable=False),
        sa.Column('price_range', sa.String(8), nullable=True),
        sa.Column('why_not', postgresql.ARRAY(sa.String(16)), nullable=False, server_default='{}'),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('app_version', sa.String(32), nullable=True),
        sa.Column('platform', sa.String(16), nullable=True),
        sa.Column('country', sa.String(2), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('round_id', 'user_id', name='uq_survey_responses_round_user'),
        sa.CheckConstraint('nps BETWEEN 0 AND 10', name='ck_survey_responses_nps'),
    )
    op.create_index('ix_survey_responses_round_id', 'survey_responses', ['round_id'])
    op.create_index('ix_survey_responses_user_id', 'survey_responses', ['user_id'])

    op.create_table(
        'survey_prompts',
        sa.Column('round_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('survey_rounds.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('shown_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('snoozed_until', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table('survey_prompts')
    op.drop_index('ix_survey_responses_user_id', table_name='survey_responses')
    op.drop_index('ix_survey_responses_round_id', table_name='survey_responses')
    op.drop_table('survey_responses')
    op.drop_table('survey_rounds')
    op.drop_index('uq_feedback_quick_ref', table_name='feedback')
    op.drop_index('ix_feedback_kind_created', table_name='feedback')
    op.drop_index('ix_feedback_status_created', table_name='feedback')
    op.drop_index('ix_feedback_user_id', table_name='feedback')
    op.drop_table('feedback')
