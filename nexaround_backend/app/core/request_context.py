"""Per-request context, carried implicitly so call sites don't have to thread it.

Telemetry needs to know which inbound request caused an outbound call, who the
caller was, and which app build they were running. Passing that down through
every service signature would touch most of the codebase, so it lives in
ContextVars instead: the middleware sets them once per request and anything
deeper in the stack reads them for free.

ContextVars are task-local under asyncio, so concurrent requests never see each
other's values — including inside `asyncio.gather`, which matters here because
the place-resolution paths fan out with `Future.wait`-style concurrency.
"""
import uuid
from contextvars import ContextVar
from typing import Optional

# Correlates one inbound request to every upstream call it caused.
request_id_var: ContextVar[Optional[uuid.UUID]] = ContextVar(
    "request_id", default=None
)
user_id_var: ContextVar[Optional[uuid.UUID]] = ContextVar("user_id", default=None)
client_ip_var: ContextVar[Optional[str]] = ContextVar("client_ip", default=None)
# Sent by the mobile client. Without these an old build's traffic is
# indistinguishable from a new one's, which is what made the Find Place
# investigation slow — the fix was already shipped but still generating load.
app_version_var: ContextVar[Optional[str]] = ContextVar("app_version", default=None)
platform_var: ContextVar[Optional[str]] = ContextVar("platform", default=None)
# The inbound endpoint that caused this work. request_id groups the upstream
# calls one client action produced; this names the action.
route_var: ContextVar[Optional[str]] = ContextVar("route", default=None)


def current_request_id() -> Optional[uuid.UUID]:
    return request_id_var.get()


def current_user_id() -> Optional[uuid.UUID]:
    return user_id_var.get()


def set_user_id(user_id) -> None:
    """Called once the request is authenticated.

    Auth resolves after the middleware has run, so the user is attached here
    rather than at request start. Telemetry rows emitted before this point
    simply carry a NULL user_id.
    """
    if user_id is None:
        return
    try:
        user_id_var.set(user_id if isinstance(user_id, uuid.UUID) else uuid.UUID(str(user_id)))
    except (ValueError, AttributeError, TypeError):
        pass


def snapshot() -> dict:
    """All context values as a plain dict, for attaching to a telemetry row."""
    return {
        "request_id": request_id_var.get(),
        "user_id": user_id_var.get(),
        "client_ip": client_ip_var.get(),
        "app_version": app_version_var.get(),
        "platform": platform_var.get(),
        "route": route_var.get(),
    }
