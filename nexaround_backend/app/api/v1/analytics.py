"""Reports from the app about which features explorers look at.

Feeds the admin's Feature usage page (app.services.feature_usage).
"""
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import request_context
from app.core.database import get_db
from app.core.exceptions import NotFoundException, UnauthorizedException
from app.core.rate_limiter import check_account_rate_limit
from app.models.analytics import FeatureOpen
from app.services import feature_usage
from app.services.auth_service import AuthService

router = APIRouter(prefix="/analytics", tags=["Analytics"])


class _FeatureOpenItem(BaseModel):
    visit_id: uuid.UUID
    feature: str = Field(max_length=32)
    # When the screen was opened. A report resent on a later app open still
    # lands on the day it happened; the server clamps it.
    opened_at: Optional[datetime] = None


class _FeatureOpensReport(BaseModel):
    opens: List[_FeatureOpenItem] = Field(default_factory=list, max_length=feature_usage.MAX_REPORT_ITEMS)


@router.post("/feature-opens")
async def record_feature_opens(
    data: _FeatureOpensReport,
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
):
    """Record the features an explorer looked at.

    The explorer comes from the token only, never from the report. No token:
    nothing is kept (the page counts explorers). A token that no longer works
    gets 401, so the app renews it and resends, as /auth/me/session does.
    Unknown features are dropped, and a visit counts each feature once.
    """
    token = (authorization or "").replace("Bearer ", "").strip()
    if not token:
        return {"accepted": 0}
    try:
        user = await AuthService(db).get_current_user(token)
    except (UnauthorizedException, NotFoundException):
        raise UnauthorizedException(detail="Session expired")

    # The app sends a batch now and then; this only stops a runaway client.
    await check_account_rate_limit(
        str(user.id), action="feature_opens", max_attempts=30, window_seconds=60,
    )

    rows = feature_usage.clean_opens(
        (item.model_dump() for item in data.opens), datetime.now(timezone.utc)
    )
    if rows:
        stmt = insert(FeatureOpen).values([
            {
                "id": uuid.uuid4(),
                "user_id": user.id,
                "app_version": request_context.app_version_var.get(),
                "platform": request_context.platform_var.get(),
                **row,
            }
            for row in rows
        ])
        # A feature already recorded for the visit stays as it was, including
        # one recorded under another account.
        await db.execute(stmt.on_conflict_do_nothing(
            index_elements=[FeatureOpen.visit_id, FeatureOpen.feature]
        ))
        await db.commit()
    return {"accepted": len(rows)}
