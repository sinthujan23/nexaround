"""Audit trail and device sessions for the admin panel and the partner portal.

Three jobs live here:

1. **Sessions.** `start_session` runs at sign-in; its id rides in the token as
   `sid`. Every authenticated request calls `session_is_live`, so revoking a row
   signs that device out on its very next request - a token blacklist cannot do
   that, because an admin revoking someone else's device does not hold the token.
2. **Events.** `record` appends one row to `audit_events`. It never raises:
   an audit write that fails must not turn a successful change into a 500, so it
   logs loudly instead.
3. **The middleware.** `audit_http_middleware` records every write made under
   /admin and /partner without each endpoint having to remember to. It sees
   method, route, status and who - never the request body, which carries
   passwords and API keys.

Who is calling is handed over by the auth dependencies through
`request.state.audit_actor`. A ContextVar would not do: dependencies run in the
task Starlette's middleware spawns, and a value set there never reaches the
middleware that wrote the response.
"""
from __future__ import annotations

import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Request
from sqlalchemy import select, update

from app.core import request_context
from app.core.database import async_session
from app.models.audit import AuditEvent, AuthSession

logger = logging.getLogger(__name__)

# `last_seen_at` is written at most this often per session. Every request would
# otherwise add an UPDATE to a table that is read on every request.
_TOUCH_EVERY = timedelta(seconds=60)

_AUDITED_PREFIXES = ("/api/v1/admin/", "/api/v1/partner/")
_WRITE_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})

# Writes the middleware leaves alone. Sign-in/out and credential changes are
# recorded by hand with richer detail (and, for a failed sign-in, before any
# actor exists); the rest are not decisions anyone made.
_SKIPPED_ROUTES = frozenset({
    "/api/v1/admin/login",
    "/api/v1/admin/logout",
    "/api/v1/partner/auth/login",
    "/api/v1/partner/auth/logout",
    "/api/v1/partner/auth/refresh",
    "/api/v1/partner/auth/forgot-password",
    "/api/v1/partner/auth/set-password",
    # Moves a read watermark; one row per bell click is noise.
    "/api/v1/partner/activity/seen",
    # Revoking a device is recorded by hand, with the device named.
    "/api/v1/admin/sessions/{session_id}/revoke",
    "/api/v1/partner/sessions/{session_id}/revoke",
    "/api/v1/partner/sessions/revoke-others",
})

# Reads worth a row: they expose secrets or other people's personal data.
_SENSITIVE_READS = {
    "/api/v1/admin/settings": "Viewed platform settings and API keys",
    "/api/v1/admin/users": "Viewed the explorer list",
    "/api/v1/admin/users/activity": "Viewed explorer activity",
}

# Plain-English lines for the writes that matter most. Anything not listed gets
# a generated one ("Update · experiences › vendors").
_SUMMARIES = {
    ("PUT", "/api/v1/admin/settings"): "Changed platform settings or API keys",
    ("POST", "/api/v1/admin/users/{user_id}/toggle-active"): "Enabled or disabled an explorer account",
    ("POST", "/api/v1/admin/users/{user_id}/verify"): "Verified an explorer account",
    ("POST", "/api/v1/admin/engagement/announcements"): "Sent an announcement to explorers",
    ("DELETE", "/api/v1/admin/experiences/logins/{login_id}"): "Deleted a partner login",
    ("PATCH", "/api/v1/admin/experiences/logins/{login_id}"): "Changed a partner login",
    ("POST", "/api/v1/admin/experiences/vendors/{vendor_id}/logins"): "Created a partner login",
    ("POST", "/api/v1/admin/experiences/logins/{login_id}/resend-invite"): "Sent a partner a new invite link",
    ("POST", "/api/v1/admin/city-tours"): "Started a City Tours guide",
    ("PUT", "/api/v1/admin/city-tours/{tour_id}"): "Saved a City Tours guide",
    ("POST", "/api/v1/admin/city-tours/{tour_id}/submit"): "Sent a City Tours guide for review",
    ("POST", "/api/v1/admin/city-tours/{tour_id}/review"): "Approved a City Tours guide or sent it back",
    ("POST", "/api/v1/admin/city-tours/{tour_id}/visibility"): "Hid or showed a City Tours guide in the app",
    ("DELETE", "/api/v1/admin/city-tours/{tour_id}"): "Deleted a City Tours guide",
    ("POST", "/api/v1/admin/city-tours/upload"): "Uploaded City Tours photos",
    ("POST", "/api/v1/admin/city-tours/creators"): "Created a content creator login",
    ("PATCH", "/api/v1/admin/city-tours/creators/{creator_id}"): "Changed a content creator login",
    ("DELETE", "/api/v1/admin/city-tours/creators/{creator_id}"): "Deleted a content creator login",
    ("DELETE", "/api/v1/admin/experiences/vendors/{vendor_id}"): "Deleted a vendor",
    ("PUT", "/api/v1/partner/profile"): "Updated the business profile",
    ("POST", "/api/v1/partner/packages"): "Created a package",
    ("PUT", "/api/v1/partner/packages/{package_id}"): "Updated a package",
    ("DELETE", "/api/v1/partner/packages/{package_id}"): "Deleted a package",
    ("PATCH", "/api/v1/partner/enquiries/{enquiry_id}"): "Updated an enquiry",
    ("PUT", "/api/v1/partner/reviews/{review_id}/reply"): "Replied to a review",
    ("PATCH", "/api/v1/admin/experiences/reviews/{review_id}"): "Moderated a review",
    ("POST", "/api/v1/partner/agreement/accept"): "Accepted the Provider Agreement",
    ("PUT", "/api/v1/admin/legal/{kind}"): "Edited a legal document",
    ("POST", "/api/v1/admin/legal/vendors/{vendor_id}/offline-acceptance"):
        "Recorded a vendor's offline acceptance of the Provider Agreement",
}


# ── Device description ──────────────────────────────────────────────────────

def parse_user_agent(ua: Optional[str]) -> tuple[Optional[str], Optional[str], str]:
    """(browser, os, device_type) from a User-Agent, without a dependency.

    Order matters throughout: Edge and Opera also say "Chrome", Chrome also says
    "Safari", Android also says "Linux", iPadOS says "Mac OS X".
    """
    if not ua:
        return None, None, "other"

    if re.search(r"Edg(e|A|iOS)?/", ua):
        browser = "Edge"
    elif re.search(r"OPR/|Opera", ua):
        browser = "Opera"
    elif "Firefox/" in ua or "FxiOS/" in ua:
        browser = "Firefox"
    elif "SamsungBrowser/" in ua:
        browser = "Samsung Internet"
    elif "CriOS/" in ua or "Chrome/" in ua:
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    elif "okhttp" in ua or "Dart/" in ua:
        browser = "App"
    elif "curl/" in ua or "python" in ua.lower():
        browser = "Script"
    else:
        browser = None

    if "Windows" in ua:
        os_name = "Windows"
    elif "iPhone" in ua or "iPad" in ua or "iPod" in ua:
        os_name = "iOS"
    elif "Android" in ua:
        os_name = "Android"
    elif "Mac OS X" in ua or "Macintosh" in ua:
        os_name = "macOS"
    elif "CrOS" in ua:
        os_name = "ChromeOS"
    elif "Linux" in ua or "X11" in ua:
        os_name = "Linux"
    else:
        os_name = None

    if "iPad" in ua or ("Android" in ua and "Mobile" not in ua):
        device = "tablet"
    elif "iPhone" in ua or "iPod" in ua or "Mobile" in ua:
        device = "mobile"
    elif os_name in ("Windows", "macOS", "Linux", "ChromeOS"):
        device = "desktop"
    else:
        device = "other"
    return browser, os_name, device


def client_meta(request: Request) -> dict:
    """Where a request came from: IP and device, truncated to column widths."""
    from app.core.rate_limiter import get_client_ip

    try:
        ip = get_client_ip(request)
    except Exception:
        ip = None
    ua = (request.headers.get("user-agent") or "")[:512] or None
    browser, os_name, device = parse_user_agent(ua)
    return {
        "ip": ip, "user_agent": ua,
        "browser": browser, "os": os_name, "device_type": device,
    }


def describe_device(browser: Optional[str], os_name: Optional[str]) -> str:
    if browser and os_name:
        return f"{browser} on {os_name}"
    return browser or os_name or "Unknown device"


# ── Sessions ────────────────────────────────────────────────────────────────

async def start_session(
    *,
    actor_type: str,
    actor_id: str,
    actor_label: str,
    vendor_id=None,
    request: Request,
    ttl: timedelta,
) -> uuid.UUID:
    """Create the row for a new sign-in and return its id (the token's `sid`)."""
    meta = client_meta(request)
    now = datetime.now(timezone.utc)
    row = AuthSession(
        id=uuid.uuid4(),
        actor_type=actor_type,
        actor_id=str(actor_id),
        actor_label=actor_label,
        vendor_id=vendor_id,
        ip=meta["ip"],
        last_ip=meta["ip"],
        user_agent=meta["user_agent"],
        browser=meta["browser"],
        os=meta["os"],
        device_type=meta["device_type"],
        created_at=now,
        last_seen_at=now,
        expires_at=now + ttl,
    )
    async with async_session() as db:
        db.add(row)
        await db.commit()
    return row.id


def parse_sid(value) -> Optional[uuid.UUID]:
    try:
        return uuid.UUID(str(value)) if value else None
    except (ValueError, AttributeError, TypeError):
        return None


async def session_is_live(
    sid, *, actor_type: str, actor_id: str, ip: Optional[str] = None,
    extend_to: Optional[datetime] = None,
) -> bool:
    """Whether this sign-in may still be used. Touches `last_seen_at`.

    A token with no `sid` is refused: it predates the audit trail, or it was
    forged with a leaked signing key and a guess at the claims. Deploying this
    therefore signs everybody out once, which is the price of there being no
    unaudited way in.

    The actor must match as well as the id, so a session minted for one login
    can never authorise another.
    """
    sid = parse_sid(sid)
    if sid is None:
        return False
    now = datetime.now(timezone.utc)
    async with async_session() as db:
        row = await db.get(AuthSession, sid)
        if (
            row is None
            or row.revoked_at is not None
            or row.actor_type != actor_type
            or row.actor_id != str(actor_id)
        ):
            return False
        due = (
            now - row.last_seen_at >= _TOUCH_EVERY
            or (ip and ip != row.last_ip)
            or extend_to is not None
        )
        if due:
            values = {"last_seen_at": now}
            if ip:
                values["last_ip"] = ip
            if extend_to is not None:
                values["expires_at"] = extend_to
            await db.execute(
                update(AuthSession).where(AuthSession.id == sid).values(**values)
            )
            await db.commit()
    return True


async def revoke_session(
    sid, *, reason: str, by: str, actor_type: Optional[str] = None,
    actor_id: Optional[str] = None, vendor_id=None,
) -> Optional[AuthSession]:
    """Sign one device out. Returns the row, or None when there was nothing to do.

    `actor_*` / `vendor_id` narrow the lookup so a caller can only reach rows it
    owns: the partner portal passes its own login, and a miss is a plain None
    (404 upstream), never a hint that the id exists under someone else.
    """
    sid = parse_sid(sid)
    if sid is None:
        return None
    async with async_session() as db:
        row = await db.get(AuthSession, sid)
        if row is None or row.revoked_at is not None:
            return None
        if actor_type is not None and row.actor_type != actor_type:
            return None
        if actor_id is not None and row.actor_id != str(actor_id):
            return None
        if vendor_id is not None and row.vendor_id != vendor_id:
            return None
        row.revoked_at = datetime.now(timezone.utc)
        row.revoked_reason = reason
        row.revoked_by = by
        await db.commit()
        await db.refresh(row)
        return row


async def revoke_sessions_for(
    *, actor_type: str, actor_id: str, reason: str, by: str, except_sid=None,
) -> int:
    """Sign out every live device of one login. Returns how many."""
    stmt = (
        update(AuthSession)
        .where(
            AuthSession.actor_type == actor_type,
            AuthSession.actor_id == str(actor_id),
            AuthSession.revoked_at.is_(None),
        )
        .values(
            revoked_at=datetime.now(timezone.utc),
            revoked_reason=reason,
            revoked_by=by,
        )
    )
    keep = parse_sid(except_sid)
    if keep is not None:
        stmt = stmt.where(AuthSession.id != keep)
    async with async_session() as db:
        result = await db.execute(stmt)
        await db.commit()
        return result.rowcount or 0


def session_status(row: AuthSession, now: Optional[datetime] = None) -> str:
    if row.revoked_at is not None:
        return "revoked"
    if row.expires_at <= (now or datetime.now(timezone.utc)):
        return "ended"
    return "active"


# ── Events ──────────────────────────────────────────────────────────────────

async def record(
    *,
    actor_type: str,
    actor_id: Optional[str],
    actor_label: Optional[str],
    category: str,
    action: str,
    summary: str,
    vendor_id=None,
    session_id=None,
    method: Optional[str] = None,
    route: Optional[str] = None,
    path: Optional[str] = None,
    target_id: Optional[str] = None,
    status_code: Optional[int] = None,
    success: bool = True,
    meta: Optional[dict] = None,
    detail: Optional[dict] = None,
) -> None:
    """Append one audit row. Swallows its own failures - see the module note."""
    meta = meta or {}
    try:
        async with async_session() as db:
            db.add(AuditEvent(
                id=uuid.uuid4(),
                occurred_at=datetime.now(timezone.utc),
                actor_type=actor_type,
                actor_id=str(actor_id) if actor_id is not None else None,
                actor_label=(actor_label or None) and actor_label[:255],
                vendor_id=vendor_id,
                session_id=parse_sid(session_id),
                category=category,
                action=action[:60],
                summary=summary[:300],
                method=method,
                route=(route or None) and route[:255],
                path=(path or None) and path[:500],
                target_id=(target_id or None) and str(target_id)[:100],
                status_code=status_code,
                success=success,
                ip=meta.get("ip"),
                user_agent=meta.get("user_agent"),
                browser=meta.get("browser"),
                os=meta.get("os"),
                device_type=meta.get("device_type"),
                request_id=request_context.current_request_id(),
                detail=detail,
            ))
            await db.commit()
    except Exception:
        logger.exception("audit write failed: %s (%s)", action, summary)


def set_actor(request: Request, *, actor_type: str, actor_id: str,
              actor_label: str, session_id, vendor_id=None) -> None:
    """Called by the auth dependencies once a caller is verified."""
    request.state.audit_actor = {
        "actor_type": actor_type, "actor_id": str(actor_id),
        "actor_label": actor_label, "session_id": session_id,
        "vendor_id": vendor_id,
    }


# ── The middleware ──────────────────────────────────────────────────────────

def _segments(route: str) -> tuple[str, bool]:
    """("experiences › vendors", has_params) from a route template."""
    parts = route.split("/")[3:]  # drop "", "api", "v1"
    parts = parts[1:] if parts and parts[0] in ("admin", "partner") else parts
    names = [p.replace("-", " ").replace("_", " ") for p in parts if p and not p.startswith("{")]
    return " › ".join(names) or "root", any(p.startswith("{") for p in parts)


def describe_write(method: str, route: str) -> str:
    fixed = _SUMMARIES.get((method, route))
    if fixed:
        return fixed
    noun, has_params = _segments(route)
    if method == "POST":
        verb = "Run" if has_params else "Create"
    else:
        verb = {"PUT": "Update", "PATCH": "Update", "DELETE": "Delete"}.get(method, method)
    return f"{verb} · {noun}"


def _target_id(params: dict) -> Optional[str]:
    # The last path parameter is the most specific thing acted on.
    return str(list(params.values())[-1]) if params else None


async def audit_http_middleware(request: Request, call_next):
    path = request.url.path
    method = request.method
    if not path.startswith(_AUDITED_PREFIXES):
        return await call_next(request)
    is_write = method in _WRITE_METHODS
    if not is_write and not (method == "GET" and path in _SENSITIVE_READS):
        return await call_next(request)

    response = await call_next(request)

    try:
        route_obj = request.scope.get("route")
        route = getattr(route_obj, "path", None) or path
        if route in _SKIPPED_ROUTES:
            return response
        actor = getattr(request.state, "audit_actor", None)
        if actor is None:
            # Never got past authentication: nobody to attribute it to, and an
            # unauthenticated caller must not be able to fill the table.
            return response

        status_code = response.status_code
        summary = (
            describe_write(method, route) if is_write
            else _SENSITIVE_READS[route]
        )
        ok = status_code < 400
        if not ok:
            summary = f"{summary} (refused, {status_code})"
        await record(
            actor_type=actor["actor_type"],
            actor_id=actor["actor_id"],
            actor_label=actor["actor_label"],
            vendor_id=actor["vendor_id"],
            session_id=actor["session_id"],
            category="change" if is_write else "access",
            action=f"{'change' if is_write else 'access'}.{method.lower()}",
            summary=summary,
            method=method,
            route=route,
            path=path,
            target_id=_target_id(request.path_params),
            status_code=status_code,
            success=ok,
            meta=client_meta(request),
            detail=getattr(request.state, "audit_detail", None),
        )
    except Exception:
        logger.exception("audit middleware failed for %s %s", method, path)
    return response
