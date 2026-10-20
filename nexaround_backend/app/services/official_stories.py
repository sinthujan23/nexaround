"""The TravelByte account that admin-posted travel stories belong to.

Every story needs a `users` row as its owner, but admins are not users (one
shared credential from the environment). Official stories are owned by this
one system account instead, so the feed, likes and comments work on them
unchanged.

It can never sign in: it is inactive (every sign-in path refuses that), has
no password, and its address is on the reserved `.invalid` domain, so no code
or Google account can ever reach it. Nobody being able to sign in as it is
also what stops app users editing or deleting official stories - those
endpoints are owner-only.
"""
import uuid

from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.user import User

OFFICIAL_USER_ID = uuid.UUID("6e3a0b7c-5f1d-4c2a-9e8b-a0b1c2d3e4f5")
OFFICIAL_EMAIL = "stories@nexaround.invalid"
OFFICIAL_NAME = "TravelByte"
# The square pin mark. Absolute, because app builds before official stories
# only draw an avatar whose URL starts with http.
OFFICIAL_AVATAR_PATH = "/static/brand/nexaround_mark.png"


def place_label(country: str, region: str | None) -> str:
    """What an official story shows where a traveller's story shows its
    category: country then town or region, "CHINA · FURONG TOWN".

    It is stored and sent as the story's `category`, so every app build
    already installed shows it without an update.
    """
    parts = [p.strip() for p in (country, region or "") if p and p.strip()]
    return " · ".join(parts).upper()[:100]


async def ensure_official_user(db: AsyncSession) -> uuid.UUID:
    """Create the account the first time an official story is posted."""
    await db.execute(
        pg_insert(User)
        .values(
            id=OFFICIAL_USER_ID,
            email=OFFICIAL_EMAIL,
            display_name=OFFICIAL_NAME,
            avatar_url=f"{settings.PUBLIC_BASE_URL}{OFFICIAL_AVATAR_PATH}",
            preferences={},
            is_active=False,
            is_verified=True,
        )
        .on_conflict_do_nothing()
    )
    return OFFICIAL_USER_ID
