"""add mood to discovery_histories

The generate request already carried `mood` and used it to shape the Gemini
prompt, but nothing persisted it — so every time the result sheet was
reopened (app resume, push notification, history tap) it fell back to the
widget's hardcoded default instead of the mood the user actually picked. See
`discovery_ai_service.py`'s prompt and `discovery.py`'s `_run_discovery_generation`.

Revision ID: a7b8c9d0e1f2
Revises: d4e5f6a7b8c9
Create Date: 2026-09-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a7b8c9d0e1f2'
down_revision: Union[str, None] = 'd4e5f6a7b8c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'discovery_histories',
        sa.Column('mood', sa.String(length=50), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('discovery_histories', 'mood')
