"""Give attractions a lifecycle: status, reason, source and review trail

Revision ID: f7a8b9c0d1e2
Revises: e6f7a8b9c0d1
Create Date: 2026-10-13 09:00:00.000000

A place's whole life used to be one boolean, `is_active`. "Waiting for review",
"admin hid it", "duplicate copy the old seeder laid down" and "rejected" were
all the same `false`, and rejecting deleted the row, so the next Google refresh
put it straight back.

`status` now says which of those a row is. `is_active` stays as a column every
reader can keep using, but it is GENERATED from `status`, so the two can never
disagree and anything still writing the boolean fails loudly instead of
silently diverging.

Backfill:
  - active rows -> live; inactive rows -> pending / legacy_inactive. The merge
    script (app/scripts/merge_duplicate_attractions.py) resolves those.
  - source: since 54731cc (2026-08-14 08:45:34 UTC) both admin create and the
    public create endpoint have failed with a 500, so every row created after
    that came from Google seeding. Rows before it cannot be told apart
    honestly — google_place_id is also written lazily onto admin rows — so they
    stay 'unknown'.

`attraction_aliases` keeps ids of merged copies resolving to the copy that was
kept, because favourites in users.preferences hold place ids.

Run with api and worker stopped: replacing `is_active` rewrites the table.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'f7a8b9c0d1e2'
down_revision: Union[str, None] = 'e6f7a8b9c0d1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE attractions
            ADD COLUMN status varchar(16),
            ADD COLUMN status_reason varchar(40),
            ADD COLUMN status_note text,
            ADD COLUMN source varchar(16),
            ADD COLUMN submitted_by_user_id uuid
                REFERENCES users(id) ON DELETE SET NULL,
            ADD COLUMN reviewed_at timestamptz,
            ADD COLUMN reviewed_by varchar(100),
            ADD COLUMN updated_at timestamptz
    """)

    op.execute("""
        UPDATE attractions SET
            status = CASE WHEN is_active THEN 'live' ELSE 'pending' END,
            status_reason = CASE WHEN is_active THEN NULL ELSE 'legacy_inactive' END,
            source = CASE
                WHEN created_at >= '2026-08-14 08:45:34+00' THEN 'google'
                ELSE 'unknown'
            END,
            updated_at = COALESCE(created_at, now())
    """)

    op.execute("""
        ALTER TABLE attractions
            ALTER COLUMN status SET DEFAULT 'live',
            ALTER COLUMN status SET NOT NULL,
            ALTER COLUMN source SET DEFAULT 'unknown',
            ALTER COLUMN source SET NOT NULL,
            ALTER COLUMN updated_at SET DEFAULT now(),
            ALTER COLUMN updated_at SET NOT NULL,
            ADD CONSTRAINT ck_attractions_status
                CHECK (status IN ('live', 'pending', 'hidden', 'rejected')),
            ADD CONSTRAINT ck_attractions_source
                CHECK (source IN ('google', 'admin', 'user', 'seed', 'unknown'))
    """)

    # Postgres cannot turn an existing column into a generated one, so the
    # boolean is dropped and re-added in the same statement.
    op.execute("""
        ALTER TABLE attractions
            DROP COLUMN is_active,
            ADD COLUMN is_active boolean
                GENERATED ALWAYS AS (status = 'live') STORED
    """)

    op.execute(
        "CREATE INDEX ix_attractions_status_created "
        "ON attractions (status, created_at)"
    )
    op.execute(
        "CREATE INDEX ix_attractions_submitted_by "
        "ON attractions (submitted_by_user_id) "
        "WHERE submitted_by_user_id IS NOT NULL"
    )

    op.execute("""
        CREATE TABLE attraction_aliases (
            old_id uuid PRIMARY KEY,
            attraction_id uuid NOT NULL
                REFERENCES attractions(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL DEFAULT now()
        )
    """)
    op.execute(
        "CREATE INDEX ix_attraction_aliases_attraction "
        "ON attraction_aliases (attraction_id)"
    )


def downgrade() -> None:
    # hidden and rejected both collapse back into "inactive".
    op.execute("DROP TABLE attraction_aliases")
    op.execute("DROP INDEX IF EXISTS ix_attractions_submitted_by")
    op.execute("DROP INDEX IF EXISTS ix_attractions_status_created")
    op.execute("""
        ALTER TABLE attractions
            DROP COLUMN is_active,
            ADD COLUMN is_active boolean NOT NULL DEFAULT true
    """)
    op.execute("UPDATE attractions SET is_active = (status = 'live')")
    op.execute("""
        ALTER TABLE attractions
            DROP CONSTRAINT ck_attractions_status,
            DROP CONSTRAINT ck_attractions_source,
            DROP COLUMN status,
            DROP COLUMN status_reason,
            DROP COLUMN status_note,
            DROP COLUMN source,
            DROP COLUMN submitted_by_user_id,
            DROP COLUMN reviewed_at,
            DROP COLUMN reviewed_by,
            DROP COLUMN updated_at
    """)
