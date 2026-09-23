import uuid
from typing import NamedTuple

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.core.security import decode_token_with_blacklist_check
from app.models.user import User
from app.repositories.user_repository import UserRepository

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")
# auto_error=False so a missing header yields None instead of a 401. Used by
# endpoints that are reachable without a Bearer token — notably image URLs,
# which browsers and Flutter's Image widget fetch without custom headers.
oauth2_scheme_optional = OAuth2PasswordBearer(
    tokenUrl="api/v1/auth/login", auto_error=False
)

async def get_current_user(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    payload = await decode_token_with_blacklist_check(token)
    if payload is None:
        raise credentials_exception
        
    user_id: str = payload.get("sub")
    if user_id is None:
        raise credentials_exception
        
    repo = UserRepository(db)
    user = await repo.get_by_id(uuid.UUID(user_id))
    
    if user is None:
        raise credentials_exception
        
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")

    # Attach the caller to the request context so telemetry rows emitted deeper
    # in the stack carry a user_id without every service signature growing one.
    from app.core.request_context import set_user_id
    set_user_id(user.id)

    return user


async def get_current_user_optional(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme_optional),
):
    """Resolve the caller if a valid token is present, else None.

    Never raises. Endpoints using this must decide for themselves what an
    anonymous caller is allowed to do.
    """
    if not token:
        return None
    try:
        payload = await decode_token_with_blacklist_check(token)
        if payload is None:
            return None
        user_id = payload.get("sub")
        if user_id is None:
            return None
        user = await UserRepository(db).get_by_id(uuid.UUID(user_id))
        if user is None or not user.is_active:
            return None
        from app.core.request_context import set_user_id
        set_user_id(user.id)
        return user
    except Exception:
        return None


# ── Partner portal ──────────────────────────────────────────────────────────

class VendorPrincipal(NamedTuple):
    """Who is calling the partner API, and the vendor they act for.

    Both halves are returned because every write path needs the full
    `ExperienceVendor` anyway — `apply_vendor_cascade` and
    `apply_package_derived_fields` both take it — and re-fetching it per
    endpoint would double the query count on the hot paths.
    """

    login: "VendorUser"
    vendor: "ExperienceVendor"


async def get_current_vendor(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme),
) -> VendorPrincipal:
    """Resolve a partner-portal caller, or refuse.

    Deliberately stricter than `get_current_user`, which checks neither the
    token's `type` nor its `role`. Each step below closes something specific;
    none is defensive padding.
    """
    from app.models.experience import ExperienceVendor, VendorUser  # noqa: F401
    from app.repositories.experience_repository import ExperienceRepository
    from app.services.partner_auth import claims_ok, session_is_current

    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    # The blacklist-checking variant, unlike `verify_admin_token`, so that
    # logging out of the portal actually revokes the token.
    payload = await decode_token_with_blacklist_check(token)
    if payload is None:
        raise credentials_exception

    sub = payload.get("sub")
    if not sub:
        raise credentials_exception
    try:
        login_id = uuid.UUID(str(sub))
    except (ValueError, AttributeError, TypeError):
        # A malformed `sub` is a bad token, not a server fault.
        raise credentials_exception

    login = await db.get(VendorUser, login_id)
    if login is None:
        raise credentials_exception

    # Checks `type == "access"` (a refresh token would otherwise work as an
    # access token for 30 days), `role == "vendor"`, and that the token's
    # `vendor_id` still matches the row — so re-pointing a login at another
    # vendor invalidates its live tokens.
    if not claims_ok(payload, login.vendor_id):
        raise credentials_exception

    # Tokens minted before the password was last changed are dead. Their jti
    # values were never recorded, so this comparison is the only mechanism.
    if not session_is_current(payload.get("iat"), login.password_changed_at):
        raise credentials_exception

    if not login.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This login has been disabled. Contact NexAround.",
        )

    vendor = await ExperienceRepository(db).get_vendor(login.vendor_id)
    if vendor is None:
        raise credentials_exception

    # Load-bearing: `is_active=False` is how an admin suspends a vendor, and it
    # unpublishes every package they own. Without this they would keep editing
    # an invisible listing and, worse, keep reading their enquiry inbox after
    # the platform cut them off.
    if not vendor.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your listing is currently suspended. Contact NexAround.",
        )

    # Deliberately NOT calling `set_user_id()`. It feeds `api_events.user_id`,
    # a plain UUID column with no foreign key, so a vendor_users id there would
    # not error — it would silently corrupt the admin cost dashboard's
    # per-user report with ids that resolve to nothing.

    return VendorPrincipal(login=login, vendor=vendor)
