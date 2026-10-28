"""Sign-in for City Tours content creators.

Creators use the admin panel's own sign-in form: /admin/login tries the admin
credential first, then a creator's email and password. Their token says
`role: "creator"`, which every admin endpoint refuses (verify_admin_token
wants "admin"); only the City Tours endpoints take it, through
city_tours_admin.require_editor. Sessions are the audit trail's, so an admin
sees and signs out creators' devices in Devices & Sessions like any other.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import Request
from sqlalchemy import select

from app.core.database import async_session
from app.core.rate_limiter import check_account_rate_limit
from app.core.security import verify_password
from app.models.city_tour import ContentCreator
from app.services import audit

ACTOR = "creator"
ROLE = "creator"


def normalize_email(value: str) -> str:
    return (value or "").strip().lower()


async def sign_in(email: str, password: str) -> tuple[Optional[ContentCreator], str]:
    """The creator these credentials open, or None with the reason for the trail.

    An address that is not a creator's costs nothing here, so the admin's own
    sign-in (a username, no "@") never reaches the database.
    """
    email = normalize_email(email)
    if "@" not in email:
        return None, "unknown username"
    # Keyed on the account, as the partner portal's: the IP limit alone is rotatable.
    await check_account_rate_limit(email, action="creator_login", max_attempts=10, window_seconds=900)
    async with async_session() as db:
        creator = (
            await db.execute(select(ContentCreator).where(ContentCreator.email == email))
        ).scalar_one_or_none()
        if creator is None:
            return None, "unknown username"
        if not verify_password(password, creator.password_hash):
            return None, "wrong password"
        if not creator.is_active:
            return None, "creator login switched off"
        creator.last_login_at = datetime.now(timezone.utc)
        await db.commit()
        await db.refresh(creator)
        return creator, ""


async def from_token(payload: Optional[dict], request: Request) -> Optional[ContentCreator]:
    """The signed-in creator a decoded token stands for, or None.

    `type` is checked because refresh tokens are signed with the same key. The
    session must still be live (an admin can sign a device out) and the login
    still switched on.
    """
    if not payload or payload.get("type") != "access" or payload.get("role") != ROLE:
        return None
    try:
        creator_id = uuid.UUID(str(payload.get("sub")))
    except (ValueError, AttributeError, TypeError):
        return None
    meta = audit.client_meta(request)
    if not await audit.session_is_live(
        payload.get("sid"), actor_type=ACTOR, actor_id=str(creator_id), ip=meta["ip"],
    ):
        return None
    async with async_session() as db:
        creator = await db.get(ContentCreator, creator_id)
    return creator if creator is not None and creator.is_active else None
