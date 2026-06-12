"""Broadcast pipeline: persist a campaign, fan out per-user inbox notifications,
push to every device via FCM, prune dead tokens, and record real delivery stats.

Runs in a FastAPI BackgroundTask, so it opens its OWN DB session (the request's
session is already closed by the time it runs).
"""
import logging
import uuid as _uuid

from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

from app.core.database import async_session
from app.models.user import User
from app.models.notification import Broadcast, Notification
from app.services import fcm_service

logger = logging.getLogger(__name__)


async def send_broadcast(*, title: str, body: str, target_audience: str = "all") -> _uuid.UUID:
    """Deliver an admin broadcast end-to-end. Returns the Broadcast id."""
    async with async_session() as db:
        # Target audience. Plan targeting (free/pro) is intentionally NOT done yet
        # — every active user is reached. The label is still recorded for history.
        result = await db.execute(select(User).where(User.is_active.is_(True)))
        users = list(result.scalars().all())

        bc = Broadcast(
            title=title, body=body, target_audience=target_audience or "all",
            recipients_count=len(users), status="sending",
        )
        db.add(bc)
        await db.flush()  # assigns bc.id

        # One inbox row per user (the app's bell icon) + collect device tokens.
        all_tokens: list = []
        token_owner: dict = {}
        for u in users:
            db.add(Notification(
                user_id=u.id, title=title, body=body,
                type="broadcast", broadcast_id=bc.id,
            ))
            for t in (u.preferences or {}).get("fcm_tokens") or []:
                if t:
                    all_tokens.append(t)
                    token_owner[t] = u
        await db.commit()

        # Push to all devices (efficient multicast). data lets the app deep-link.
        success, failure, unregistered = await fcm_service.send_multicast(
            db, all_tokens, title, body,
            data={"type": "broadcast", "broadcast_id": str(bc.id)},
        )

        # Prune tokens FCM reported as dead so we stop paying to send to them.
        if unregistered:
            dead = set(unregistered)
            owners = {token_owner[t].id: token_owner[t] for t in dead if t in token_owner}
            for u in owners.values():
                prefs = dict(u.preferences or {})
                prefs["fcm_tokens"] = [t for t in (prefs.get("fcm_tokens") or []) if t not in dead]
                u.preferences = prefs
                flag_modified(u, "preferences")

        bc.devices_sent = success
        bc.devices_failed = failure
        bc.status = "sent"
        await db.commit()

        logger.info(
            f"Broadcast {bc.id}: {len(users)} users, {success} devices sent, "
            f"{failure} failed, {len(unregistered)} pruned"
        )
        return bc.id
