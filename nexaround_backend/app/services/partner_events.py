"""Live updates for the partner portal, pushed to open tabs as Server-Sent Events.

Whatever changes something a vendor can see calls `publish()` after its commit;
every open portal tab of that vendor receives it through `GET /partner/events`
and refreshes the affected view without a page reload.

Redis pub/sub rather than an in-process queue because the API runs
WEB_CONCURRENCY uvicorn processes: the tab's stream and the request that caused
the event (a traveller's enquiry, an admin edit) are usually on different ones.

Pub/sub is fire-and-forget, so an event published while a tab is reconnecting
is lost. That is acceptable because no event is the record — the rows are — and
the portal re-reads its counts and lists every time its stream (re)connects.
"""
from __future__ import annotations

import json
import logging
import time
from typing import AsyncIterator, Awaitable, Callable, Optional

import anyio

from app.core.rate_limiter import get_redis_client

logger = logging.getLogger(__name__)

# Well inside nginx's 300 s proxy_read_timeout, and short enough that the
# portal's 50 s watchdog notices a silently dead connection.
HEARTBEAT_SECONDS = 20
# How often an idle stream re-checks the session. Events re-check on their own.
RECHECK_SECONDS = 300

ENQUIRY_CREATED = "enquiry.created"
ENQUIRY_UPDATED = "enquiry.updated"
PACKAGES_CHANGED = "packages.changed"
# The vendor record or one of its logins changed. Carries no data; its job is
# to make every open stream re-check its session at once, so a suspension or a
# disabled login takes effect in seconds rather than at the next recheck.
ACCOUNT_CHANGED = "account.changed"
# Sent by the stream itself, never published: the portal signs out on it.
SESSION_ENDED = "session.ended"

SESSION_EXPIRED_MESSAGE = "Session expired. Please sign in again."


def channel(vendor_id) -> str:
    return f"partner_events:{vendor_id}"


def sse(event: str, data: dict) -> str:
    """One Server-Sent Events frame. `json.dumps` never emits a raw newline,
    so the payload always fits on the single `data:` line."""
    return f"event: {event}\ndata: {json.dumps(data, default=str)}\n\n"


async def publish(vendor_id, event_type: str, data: Optional[dict] = None) -> None:
    """Tell that vendor's open portal tabs something changed.

    Never raises. The write that caused the event is already committed, and a
    Redis outage must not turn it into a 500 — the portal catches up on its
    next load anyway.
    """
    if not vendor_id:
        return
    try:
        redis = await get_redis_client()
        if redis is None:
            return
        await redis.publish(
            channel(vendor_id),
            json.dumps({"type": event_type, "data": data or {}}, default=str),
        )
    except Exception:
        logger.warning(
            "partner event %s for vendor %s not published",
            event_type, vendor_id, exc_info=True,
        )


async def stream(
    redis,
    vendor_id,
    *,
    expires_at: float,
    session_problem: Callable[[], Awaitable[Optional[str]]],
) -> AsyncIterator[str]:
    """The event stream for one portal tab.

    Ends when the access token expires, and whenever `session_problem` returns a
    reason — it is awaited before every event is forwarded and every
    RECHECK_SECONDS while idle, so a suspended vendor, a disabled login, a
    password change or a logout stops the flow of traveller contact details
    rather than leaving it running until the token's hour is up.

    If the check itself fails (the database is down), the stream just closes:
    the portal reconnects with backoff instead of signing the vendor out over
    an outage.
    """
    pubsub = redis.pubsub()
    await pubsub.subscribe(channel(vendor_id))
    try:
        yield sse("ready", {"heartbeat_seconds": HEARTBEAT_SECONDS})
        next_check = time.monotonic() + RECHECK_SECONDS
        while True:
            remaining = expires_at - time.time()
            if remaining <= 0:
                yield sse(SESSION_ENDED, {"message": SESSION_EXPIRED_MESSAGE})
                return

            message = await pubsub.get_message(
                ignore_subscribe_messages=True,
                timeout=min(HEARTBEAT_SECONDS, remaining),
            )

            if message is not None or time.monotonic() >= next_check:
                try:
                    problem = await session_problem()
                except Exception:
                    logger.warning("partner stream session check failed", exc_info=True)
                    return
                if problem:
                    yield sse(SESSION_ENDED, {"message": problem})
                    return
                next_check = time.monotonic() + RECHECK_SECONDS

            if message is None:
                # An SSE comment: ignored by the client, but it keeps nginx
                # and the portal's watchdog from treating the line as dead.
                yield ": ping\n\n"
                continue

            try:
                event = json.loads(message["data"])
                event_type = str(event["type"])
            except (ValueError, KeyError, TypeError):
                logger.warning("malformed partner event dropped: %r", message)
                continue
            yield sse(event_type, event.get("data") or {})
    finally:
        # Shielded: the usual way out of here is a cancellation (the tab
        # closed, or uvicorn's graceful-shutdown timeout), and an unshielded
        # await would be cancelled too, leaking the subscription's Redis
        # connection.
        with anyio.move_on_after(2, shield=True):
            try:
                await pubsub.aclose()
            except Exception:
                logger.debug("pubsub close failed", exc_info=True)
