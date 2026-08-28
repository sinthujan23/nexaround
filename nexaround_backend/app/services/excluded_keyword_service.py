"""Admin-managed keyword list that hides places from the Around You cards.

Deliberately small and DB-backed rather than a static Python set like
`place_bands._EXCLUDED_TAGS` — this list is edited by admins at runtime, not
by a developer shipping a code change. See `place_bands.matches_excluded_keyword`
for how a keyword is matched against a place name, and
`banded_places_service.get_nearby_banded` for where the list is applied.
"""
import uuid
from typing import List

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session
from app.models.excluded_keyword import ExcludedKeyword
from app.repositories.excluded_keyword_repository import ExcludedKeywordRepository
from app.schemas.excluded_keyword import ExcludedKeywordCreate


def _normalize(keyword: str) -> str:
    return " ".join(keyword.strip().split())


async def list_all(db: AsyncSession) -> List[ExcludedKeyword]:
    return await ExcludedKeywordRepository(db).get_all()


async def create(db: AsyncSession, data: ExcludedKeywordCreate) -> ExcludedKeyword:
    keyword = _normalize(data.keyword)
    if not keyword:
        raise ValueError("Keyword must not be empty")

    repo = ExcludedKeywordRepository(db)
    existing = await repo.get_by_keyword(keyword)
    if existing:
        raise ValueError(f'"{keyword}" is already excluded')
    return await repo.create(keyword)


async def delete(db: AsyncSession, keyword_id: uuid.UUID) -> bool:
    return await ExcludedKeywordRepository(db).delete(keyword_id)


async def get_active_keywords() -> List[str]:
    """The current keyword list, for the banded-places pipeline to apply.

    Opens its own session: called from `get_nearby_banded`'s cache-hit path,
    which does not otherwise touch the database.
    """
    async with async_session() as session:
        rows = await ExcludedKeywordRepository(session).get_all()
        return [r.keyword for r in rows]
