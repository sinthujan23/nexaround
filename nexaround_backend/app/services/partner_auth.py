"""Token rules for the partner portal, kept as pure functions so they are testable.

The suite here runs without a database, a network or a TestClient, so anything
that decides whether a request is allowed has to be callable on its own. The
three rules below are the ones worth pinning: which claims make a partner token
valid, whether a session predates a password change, and which Redis keys the
link tokens live under.
"""
from __future__ import annotations

import secrets
import uuid
from datetime import datetime
from typing import Optional

from app.core.rate_limiter import get_redis_client

# Invite links last long enough to survive a weekend; reset links do not need to.
INVITE_TTL_SECONDS = 72 * 3600
RESET_TTL_SECONDS = 3600

# The prefixes are deliberately NOT `reset_token:`. `AuthService.reset_password`
# reads that prefix, maps it to an *email*, and updates the matching `users`
# row - so a vendor invite stored there would let whoever holds the link take
# over the traveller account with the same address. Pinned by a test.
_INVITE = "vendor_invite:"
_RESET = "vendor_reset:"


def invite_key(token: str) -> str:
    return f"{_INVITE}{token}"


def reset_key(token: str) -> str:
    return f"{_RESET}{token}"


def invite_pointer_key(login_id) -> str:
    """The live invite token for a login, so a resend can revoke the last one.

    Without this reverse pointer every resend leaves the previous link working,
    and "resend because the first email went astray" would widen the exposure
    instead of closing it.
    """
    return f"{_INVITE}current:{login_id}"


def reset_pointer_key(login_id) -> str:
    return f"{_RESET}current:{login_id}"


def new_link_token() -> str:
    return secrets.token_urlsafe(32)


def claims_ok(payload: Optional[dict], expected_vendor_id) -> bool:
    """Whether a decoded token may act as this vendor login.

    `type` is checked because `create_refresh_token` signs with the same key and
    nothing else in the codebase looks at it - omit this and a 30-day refresh
    token works as an access token indefinitely, defeating both the one-hour
    expiry and the blacklist.

    `vendor_id` is carried on the token only to be asserted here: it is never
    used as the scoping value. Re-pointing a login at another vendor therefore
    invalidates its live tokens for free.
    """
    if not payload:
        return False
    if payload.get("type") != "access":
        return False
    if payload.get("role") != "vendor":
        return False
    if not payload.get("sub"):
        return False
    return str(payload.get("vendor_id")) == str(expected_vendor_id)


def session_is_current(
    issued_at: Optional[float], password_changed_at: Optional[datetime],
) -> bool:
    """False for a token minted before the password was last changed.

    The other sessions' jti values were never recorded, so there is nothing to
    blacklist; comparing timestamps is what makes "reset my password" actually
    sign the other browsers out.
    """
    if password_changed_at is None:
        return True
    if issued_at is None:
        # A token with no `iat` cannot be shown to postdate the change.
        return False
    changed = password_changed_at
    if changed.tzinfo is None:
        from datetime import timezone
        changed = changed.replace(tzinfo=timezone.utc)
    return float(issued_at) >= changed.timestamp()


async def store_link_token(login_id, *, is_reset: bool) -> str:
    """Mint a single-use link token, revoking any previous one for this login."""
    token = new_link_token()
    key = reset_key(token) if is_reset else invite_key(token)
    pointer = reset_pointer_key(login_id) if is_reset else invite_pointer_key(login_id)
    ttl = RESET_TTL_SECONDS if is_reset else INVITE_TTL_SECONDS

    redis = await get_redis_client()
    if redis:
        previous = await redis.get(pointer)
        if previous:
            await redis.delete(reset_key(previous) if is_reset else invite_key(previous))
        await redis.setex(key, ttl, str(login_id))
        await redis.setex(pointer, ttl, token)
    return token


async def consume_link_token(token: str) -> Optional[uuid.UUID]:
    """Resolve a link token to its login id and burn it. None when unusable.

    Invite and reset tokens are interchangeable here on purpose - both mean
    "this person proved they read the mailbox", and the endpoint that calls
    this does the same thing either way.
    """
    redis = await get_redis_client()
    if not redis or not token:
        return None

    for is_reset in (False, True):
        key = reset_key(token) if is_reset else invite_key(token)
        login_id = await redis.get(key)
        if not login_id:
            continue
        pointer = (
            reset_pointer_key(login_id) if is_reset else invite_pointer_key(login_id)
        )
        await redis.delete(key)
        await redis.delete(pointer)
        try:
            return uuid.UUID(str(login_id))
        except (ValueError, AttributeError, TypeError):
            return None
    return None
