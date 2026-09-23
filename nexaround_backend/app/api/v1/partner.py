"""The partner portal API — a vendor acting on their own rows, and only those.

Two rules run through this file and both exist because the admin equivalents
would be wrong here:

1. **Scope lives in the query, not the endpoint body.** The repository helpers
   used below cannot return another vendor's row, so there is no "and check the
   owner afterwards" step for a future endpoint to forget.
2. **The scalar tuples are separate from the admin ones.** The admin update is
   a full-replacement loop over fields that all have defaults, so reusing its
   tuple would let a vendor write `is_active`, `rating` and `internal_notes`
   simply by pressing Save — even if their schema never declared them.
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import VendorPrincipal, get_current_vendor
from app.core.database import get_db
from app.core.rate_limiter import auth_rate_limiter, check_account_rate_limit
from app.core.security import (
    blacklist_token, create_access_token, create_refresh_token,
    get_password_hash, verify_password,
)
from app.models.experience import VendorUser
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.partner import (
    PartnerForgotPasswordRequest, PartnerLoginRequest, PartnerMe,
    PartnerMessageResponse, PartnerSetPasswordRequest, PartnerTokenResponse,
)
from app.services.email_service import send_vendor_invite_email
from app.services.partner_auth import consume_link_token, store_link_token

router = APIRouter(prefix="/partner", tags=["Partner Portal"])

# Returned for every outcome of /auth/login. Distinguishing "no such email"
# from "wrong password" from "invite not accepted" would enumerate the vendor
# roster for anyone with a browser.
_BAD_CREDENTIALS = "Invalid email or password."


def _claims(login: VendorUser) -> dict:
    """The claims every partner token carries.

    `iat` is set explicitly because `create_access_token` does not add one — it
    injects only `exp`, `type` and `jti`. Without it every token looks older
    than the password it was issued against, and `session_is_current` refuses
    the lot: a vendor who sets a password can never sign in again. Found by
    signing in, not by a unit test, which is why one now pins it.
    """
    from datetime import datetime, timezone

    return {
        "sub": str(login.id),
        "role": "vendor",
        "vendor_id": str(login.vendor_id),
        "iat": int(datetime.now(timezone.utc).timestamp()),
    }


def _me(principal: VendorPrincipal) -> PartnerMe:
    return PartnerMe(
        login_id=principal.login.id,
        email=principal.login.email,
        display_name=principal.login.display_name,
        vendor_id=principal.vendor.id,
        vendor_name=principal.vendor.name,
        vendor_is_active=bool(principal.vendor.is_active),
    )


async def _lookup_login(db: AsyncSession, email: str) -> Optional[VendorUser]:
    from sqlalchemy import select

    return (
        await db.execute(
            select(VendorUser).where(VendorUser.email == email.strip().lower())
        )
    ).scalar_one_or_none()


@router.post("/auth/login", response_model=PartnerTokenResponse)
async def partner_login(
    data: PartnerLoginRequest,
    db: AsyncSession = Depends(get_db),
    _=Depends(auth_rate_limiter),
):
    email = str(data.email).strip().lower()
    # The IP limiter alone is rotatable; this one is keyed on the account being
    # attacked rather than on where the attack comes from.
    await check_account_rate_limit(
        email, action="partner_login", max_attempts=10, window_seconds=900,
    )

    login = await _lookup_login(db, email)
    # `verify_password` returns False for a null hash, so an invite that was
    # never accepted simply fails here rather than needing its own branch.
    if login is None or not verify_password(data.password, login.password_hash):
        raise HTTPException(status_code=401, detail=_BAD_CREDENTIALS)

    if not login.is_active:
        raise HTTPException(
            status_code=403, detail="This login has been disabled. Contact NexAround.",
        )

    vendor = await ExperienceRepository(db).get_vendor(login.vendor_id)
    if vendor is None:
        raise HTTPException(status_code=401, detail=_BAD_CREDENTIALS)
    # Told plainly here rather than as a puzzling 403 on the next call.
    if not vendor.is_active:
        raise HTTPException(
            status_code=403,
            detail="Your listing is currently suspended. Contact NexAround.",
        )

    from datetime import datetime, timezone
    login.last_login_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(login)

    claims = _claims(login)
    principal = VendorPrincipal(login=login, vendor=vendor)
    return PartnerTokenResponse(
        access_token=create_access_token(claims),
        refresh_token=create_refresh_token(claims),
        me=_me(principal),
    )


@router.post("/auth/forgot-password", response_model=PartnerMessageResponse)
async def partner_forgot_password(
    data: PartnerForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
    _=Depends(auth_rate_limiter),
):
    """Send a reset link, and say nothing about whether the address exists.

    A deliberate divergence from `AuthService.forgot_password`, which raises
    404 "No account registered with this email address". That is fine for the
    traveller app, where anyone can sign up anyway; here it would let anyone
    enumerate the vendor roster one address at a time. Do not "fix" it back.
    """
    email = str(data.email).strip().lower()
    await check_account_rate_limit(
        email, action="partner_reset", max_attempts=5, window_seconds=3600,
    )

    login = await _lookup_login(db, email)
    if login is not None and login.is_active:
        vendor = await ExperienceRepository(db).get_vendor(login.vendor_id)
        if vendor is not None:
            token = await store_link_token(login.id, is_reset=True)
            from app.core.config import settings
            link = (
                f"{settings.PARTNER_PORTAL_URL.rstrip('/')}"
                f"/set-password?token={token}"
            )
            await send_vendor_invite_email(
                login.email, vendor.name, link, is_reset=True,
            )

    return PartnerMessageResponse(
        message=(
            "If that address has a partner account, a reset link is on its way. "
            "The link is valid for one hour."
        )
    )


@router.get("/auth/check-token", response_model=PartnerMessageResponse)
async def partner_check_token(
    token: str = Query(..., min_length=10, max_length=256),
    _=Depends(auth_rate_limiter),
):
    """Whether a link is still usable, so the form can say so before typing.

    Read-only: this must NOT consume the token, or checking the page would
    burn the link the traveller is about to use.
    """
    from app.core.rate_limiter import get_redis_client
    from app.services.partner_auth import invite_key, reset_key

    redis = await get_redis_client()
    alive = False
    if redis:
        alive = bool(
            await redis.get(invite_key(token)) or await redis.get(reset_key(token))
        )
    if not alive:
        raise HTTPException(
            status_code=400,
            detail="This link has expired or has already been used. "
                   "Ask NexAround to send a new one.",
        )
    return PartnerMessageResponse(message="Link is valid.")


@router.post("/auth/set-password", response_model=PartnerMessageResponse)
async def partner_set_password(
    data: PartnerSetPasswordRequest,
    db: AsyncSession = Depends(get_db),
    _=Depends(auth_rate_limiter),
):
    """Accept an invite or a reset link and set the password.

    No token is issued here on purpose: the vendor signs in afterwards, so a
    link that has already been used yields nothing to whoever finds it later.
    """
    login_id = await consume_link_token(data.token)
    if login_id is None:
        raise HTTPException(
            status_code=400,
            detail="This link has expired or has already been used. "
                   "Ask NexAround to send a new one.",
        )

    login = await db.get(VendorUser, login_id)
    if login is None:
        raise HTTPException(status_code=400, detail="This login no longer exists.")

    from datetime import datetime, timezone
    login.password_hash = get_password_hash(data.new_password)
    # Signs out every other session: their tokens predate this moment.
    login.password_changed_at = datetime.now(timezone.utc)
    await db.commit()

    return PartnerMessageResponse(
        message="Password set. You can now sign in."
    )


@router.post("/auth/refresh", response_model=PartnerTokenResponse)
async def partner_refresh(
    db: AsyncSession = Depends(get_db),
    authorization: str = Header(...),
):
    """Exchange a refresh token for a new pair.

    The only place a partner refresh token is accepted — `get_current_vendor`
    rejects them, which is what stops a 30-day token acting as an hour-long one.
    """
    from app.core.security import decode_token_with_blacklist_check
    from app.services.partner_auth import session_is_current

    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    payload = await decode_token_with_blacklist_check(authorization.split(" ", 1)[1])
    if not payload or payload.get("type") != "refresh" or payload.get("role") != "vendor":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    try:
        login_id = uuid.UUID(str(payload.get("sub")))
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    login = await db.get(VendorUser, login_id)
    if login is None or not login.is_active:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    if not session_is_current(payload.get("iat"), login.password_changed_at):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    vendor = await ExperienceRepository(db).get_vendor(login.vendor_id)
    if vendor is None or not vendor.is_active:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    claims = _claims(login)
    return PartnerTokenResponse(
        access_token=create_access_token(claims),
        refresh_token=create_refresh_token(claims),
        me=_me(VendorPrincipal(login=login, vendor=vendor)),
    )


@router.post("/auth/logout", response_model=PartnerMessageResponse)
async def partner_logout(
    authorization: str = Header(...),
    _principal: VendorPrincipal = Depends(get_current_vendor),
):
    if authorization.startswith("Bearer "):
        await blacklist_token(authorization.split(" ", 1)[1])
    return PartnerMessageResponse(message="Signed out.")


@router.get("/me", response_model=PartnerMe)
async def partner_me(
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return _me(principal)
