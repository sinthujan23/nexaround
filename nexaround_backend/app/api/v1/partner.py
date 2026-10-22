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
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import (
    APIRouter, Depends, File, Header, HTTPException, Query, Request,
    UploadFile, status,
)
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import VendorPrincipal, get_current_user, get_current_vendor, oauth2_scheme
from app.core.config import settings
from app.core.database import async_session, get_db
from app.core.rate_limiter import auth_rate_limiter, check_account_rate_limit
from app.core.security import (
    blacklist_token, create_access_token, create_refresh_token,
    get_password_hash, verify_password,
)
from app.models.experience import ExperienceVendor, VendorUser
from app.models.user import User
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.audit import (
    PartnerAuditEventOut, PartnerAuditListResponse, PartnerSessionListResponse,
    PartnerSessionOut,
)
from app.schemas.partner import (
    PartnerActivity, PartnerActivityListResponse, PartnerActivityUnreadResponse,
    PartnerAppAccessResponse, PartnerAppSessionRequest, PartnerAppVendor,
    PartnerForgotPasswordRequest, PartnerLoginRequest, PartnerMe,
    PartnerMessageResponse, PartnerPackageCreate, PartnerPackageListResponse,
    PartnerPackageResponse, PartnerPackageUpdate, PartnerReviewListResponse,
    PartnerReviewReply, PartnerReviewResponse, PartnerSetPasswordRequest,
    PartnerTokenResponse, PartnerStatsResponse, PartnerVendorProfileResponse,
    PartnerVendorProfileUpdate,
)
from app.services import (
    audit, google_places_client, partner_activity, partner_events,
)
from app.services.email_service import send_vendor_invite_email
from app.services import experience_reviews
from app.services.experience_format import (
    apply_price_options, package_field_value, price_options_for_save,
)
from app.services.experience_upload import save_experience_images
from app.services.settings_service import SettingsService
from app.services.partner_auth import consume_link_token, store_link_token

router = APIRouter(prefix="/partner", tags=["Partner Portal"])

# Returned for every outcome of /auth/login. Distinguishing "no such email"
# from "wrong password" from "invite not accepted" would enumerate the vendor
# roster for anyone with a browser.
_BAD_CREDENTIALS = "Invalid email or password."

# How long a sign-in stays "active" after its newest access token was issued.
_ACCESS_TTL = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)


def _claims(login: VendorUser, sid) -> dict:
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
        # Ties the token to a row in `auth_sessions`: that row is what an
        # admin (or the vendor) revokes to sign this device out.
        "sid": str(sid),
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


async def _failed_sign_in(request: Request, email: str, login, reason: str) -> None:
    """Record a refused sign-in. Kept against the vendor when the address is
    theirs, so the portal can warn them about guessing; otherwise admin-only."""
    await audit.record(
        actor_type="anonymous",
        actor_id=str(login.id) if login is not None else None,
        actor_label=email[:255],
        vendor_id=login.vendor_id if login is not None else None,
        category="auth", action="auth.login_failed",
        summary="Failed sign-in attempt",
        method="POST", route="/api/v1/partner/auth/login", status_code=401,
        success=False, meta=audit.client_meta(request), detail={"reason": reason},
    )


@router.post("/auth/login", response_model=PartnerTokenResponse)
async def partner_login(
    data: PartnerLoginRequest,
    request: Request,
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
        await _failed_sign_in(
            request, email, login,
            "no such account" if login is None else "wrong password",
        )
        raise HTTPException(status_code=401, detail=_BAD_CREDENTIALS)

    if not login.is_active:
        await _failed_sign_in(request, email, login, "login disabled")
        raise HTTPException(
            status_code=403, detail="This login has been disabled. Contact NexAround.",
        )

    vendor = await ExperienceRepository(db).get_vendor(login.vendor_id)
    if vendor is None:
        await _failed_sign_in(request, email, login, "vendor missing")
        raise HTTPException(status_code=401, detail=_BAD_CREDENTIALS)
    # Told plainly here rather than as a puzzling 403 on the next call.
    if not vendor.is_active:
        await _failed_sign_in(request, email, login, "vendor suspended")
        raise HTTPException(
            status_code=403,
            detail="Your listing is currently suspended. Contact NexAround.",
        )

    from datetime import datetime, timezone
    login.last_login_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(login)

    sid = await audit.start_session(
        actor_type="vendor", actor_id=str(login.id), actor_label=login.label,
        vendor_id=login.vendor_id, request=request, ttl=_ACCESS_TTL,
    )
    meta = audit.client_meta(request)
    await audit.record(
        actor_type="vendor", actor_id=str(login.id), actor_label=login.label,
        vendor_id=login.vendor_id, session_id=sid,
        category="auth", action="auth.login",
        summary=f"Signed in from {audit.describe_device(meta['browser'], meta['os'])}",
        method="POST", route="/api/v1/partner/auth/login", status_code=200,
        meta=meta,
    )

    claims = _claims(login, sid)
    principal = VendorPrincipal(login=login, vendor=vendor)
    return PartnerTokenResponse(
        access_token=create_access_token(claims),
        refresh_token=create_refresh_token(claims),
        me=_me(principal),
    )


@router.post("/auth/forgot-password", response_model=PartnerMessageResponse)
async def partner_forgot_password(
    data: PartnerForgotPasswordRequest,
    request: Request,
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
            await audit.record(
                actor_type="anonymous", actor_id=str(login.id),
                actor_label=login.label, vendor_id=login.vendor_id,
                category="auth", action="auth.password_reset_requested",
                summary="Password reset link requested",
                method="POST", route="/api/v1/partner/auth/forgot-password",
                status_code=200, meta=audit.client_meta(request),
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
    request: Request,
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
    first_password = login.password_hash is None
    login.password_hash = get_password_hash(data.new_password)
    # Signs out every other session: their tokens predate this moment.
    login.password_changed_at = datetime.now(timezone.utc)
    await db.commit()
    # The same cut-off, made visible: the devices list shows them as signed out.
    await audit.revoke_sessions_for(
        actor_type="vendor", actor_id=str(login.id), reason="password",
        by=login.label,
    )
    await audit.record(
        actor_type="vendor", actor_id=str(login.id), actor_label=login.label,
        vendor_id=login.vendor_id, category="auth",
        action="auth.password_set" if first_password else "auth.password_reset",
        summary=(
            "Accepted the invite and set a password" if first_password
            else "Reset the password; all devices signed out"
        ),
        method="POST", route="/api/v1/partner/auth/set-password", status_code=200,
        meta=audit.client_meta(request),
    )
    await partner_events.publish(login.vendor_id, partner_events.ACCOUNT_CHANGED)

    return PartnerMessageResponse(
        message="Password set. You can now sign in."
    )


@router.post("/auth/refresh", response_model=PartnerTokenResponse)
async def partner_refresh(
    request: Request,
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

    # The same sign-in, still: a revoked device cannot refresh its way back in.
    sid = payload.get("sid")
    from datetime import datetime, timezone
    if not await audit.session_is_live(
        sid, actor_type="vendor", actor_id=str(login.id),
        ip=audit.client_meta(request)["ip"],
        extend_to=datetime.now(timezone.utc) + _ACCESS_TTL,
    ):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    claims = _claims(login, sid)
    return PartnerTokenResponse(
        access_token=create_access_token(claims),
        refresh_token=create_refresh_token(claims),
        me=_me(VendorPrincipal(login=login, vendor=vendor)),
    )


@router.post("/auth/logout", response_model=PartnerMessageResponse)
async def partner_logout(
    request: Request,
    authorization: str = Header(...),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    token = authorization.split(" ", 1)[1] if authorization.startswith("Bearer ") else None
    sid = None
    if token:
        await blacklist_token(token)
        from app.core.security import decode_token
        sid = (decode_token(token) or {}).get("sid")
    # Revoking the session (not just blacklisting this one access token) is
    # what also kills the refresh token that came with it.
    row = await audit.revoke_session(
        sid, reason="user", by=principal.login.label,
        actor_type="vendor", actor_id=str(principal.login.id),
    )
    if row is not None:
        await audit.record(
            actor_type="vendor", actor_id=str(principal.login.id),
            actor_label=principal.login.label, vendor_id=principal.vendor.id,
            session_id=row.id, category="auth", action="auth.logout",
            summary="Signed out", method="POST",
            route="/api/v1/partner/auth/logout", status_code=200,
            meta=audit.client_meta(request),
        )
    return PartnerMessageResponse(message="Signed out.")


@router.get("/me", response_model=PartnerMe)
async def partner_me(
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return _me(principal)


# ── The app's way in ─────────────────────────────────────────────────────────
# A traveller an admin gave a vendor to (VendorUser.app_user_id) manages it
# from the app. These two endpoints are the only ones here that take the
# TRAVELLER's token. The second trades it for a partner token naming the app
# login, so everything after it is the same partner API as the web portal's,
# with the same scoping, audit trail and suspension checks.

async def _app_logins(db: AsyncSession, user_id, vendor_id=None) -> list[VendorUser]:
    from sqlalchemy import select

    query = select(VendorUser).where(
        VendorUser.app_user_id == user_id, VendorUser.is_active.is_(True),
    )
    if vendor_id is not None:
        query = query.where(VendorUser.vendor_id == vendor_id)
    return list((await db.execute(query)).scalars().all())


@router.get("/app/access", response_model=PartnerAppAccessResponse)
async def partner_app_access(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """The vendors this traveller may manage: what shows the app's button."""
    vendors = []
    for login in await _app_logins(db, user.id):
        vendor = await db.get(ExperienceVendor, login.vendor_id)
        if vendor is not None and vendor.is_active:
            vendors.append(PartnerAppVendor(
                vendor_id=vendor.id, vendor_name=vendor.name, logo_url=vendor.logo_url,
            ))
    vendors.sort(key=lambda v: v.vendor_name.lower())
    return PartnerAppAccessResponse(vendors=vendors)


@router.post("/app/session", response_model=PartnerTokenResponse)
async def partner_app_session(
    data: PartnerAppSessionRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """A partner token for one of the traveller's vendors.

    No refresh token: the app asks again with the traveller's token when this
    one expires. Rate-limited per account, not per IP, because mobile
    networks put many phones behind one address.
    """
    await check_account_rate_limit(
        str(user.id), action="partner_app_session", max_attempts=30, window_seconds=600,
    )
    logins = await _app_logins(db, user.id, data.vendor_id)
    # 404, as everywhere in this API: a 403 would confirm the vendor exists.
    if not logins:
        raise HTTPException(status_code=404, detail="You don't manage this business.")
    login = logins[0]
    vendor = await db.get(ExperienceVendor, login.vendor_id)
    if vendor is None:
        raise HTTPException(status_code=404, detail="You don't manage this business.")
    if not vendor.is_active:
        raise HTTPException(
            status_code=403,
            detail="Your listing is currently suspended. Contact NexAround.",
        )

    # Keeps the devices list and the audit trail naming the person.
    name = (user.display_name or "").strip() or (user.email or "").split("@")[0] or None
    if name:
        login.display_name = name[:120]
    login.last_login_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(login)

    sid = await audit.start_session(
        actor_type="vendor", actor_id=str(login.id), actor_label=login.label,
        vendor_id=login.vendor_id, request=request, ttl=_ACCESS_TTL,
    )
    await audit.record(
        actor_type="vendor", actor_id=str(login.id), actor_label=login.label,
        vendor_id=login.vendor_id, session_id=sid,
        category="auth", action="auth.login",
        summary="Signed in from the NexAround app",
        method="POST", route="/api/v1/partner/app/session", status_code=200,
        meta=audit.client_meta(request),
    )
    return PartnerTokenResponse(
        access_token=create_access_token(_claims(login, sid)),
        me=_me(VendorPrincipal(login=login, vendor=vendor)),
    )


@router.get("/events")
async def partner_event_stream(token: str = Depends(oauth2_scheme)):
    """Live updates for an open portal tab, as Server-Sent Events.

    The portal reads this with `fetch`, not `EventSource`, because EventSource
    cannot send an Authorization header, and a token in the query string would
    be written to the nginx access log.

    Authenticated on a session of its own that is closed before streaming
    starts. Taking `get_current_vendor` as a dependency instead would hold its
    DB session for the life of the response — FastAPI closes yield-dependencies
    only after the response is sent — so every open tab would pin a pool
    connection for up to an hour.
    """
    from app.core.rate_limiter import get_redis_client
    from app.core.security import decode_token

    async with async_session() as db:
        principal = await get_current_vendor(db=db, token=token)
    vendor_id = principal.vendor.id

    # Generous: a tab reconnects after network blips and API restarts. This
    # only bounds how many hour-long streams one login can hold open.
    await check_account_rate_limit(
        str(principal.login.id),
        action="partner_events",
        max_attempts=120,
        window_seconds=3600,
    )

    redis = await get_redis_client()
    if redis is None:
        raise HTTPException(status_code=503, detail="Live updates are unavailable.")

    async def session_problem() -> Optional[str]:
        # The same checks as every other partner request: the blacklist
        # (logout), the password-change cutoff, a disabled login, a suspended
        # or deleted vendor.
        try:
            async with async_session() as db:
                await get_current_vendor(db=db, token=token)
        except HTTPException as exc:
            if exc.status_code == status.HTTP_403_FORBIDDEN:
                return str(exc.detail)
            return partner_events.SESSION_EXPIRED_MESSAGE
        return None

    # Verified by get_current_vendor above, so `exp` is present and trusted.
    expires_at = float(decode_token(token)["exp"])

    return StreamingResponse(
        partner_events.stream(
            redis, vendor_id, expires_at=expires_at, session_problem=session_problem,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            # nginx buffers proxied responses by default, which would hold
            # events back until a buffer filled.
            "X-Accel-Buffering": "no",
        },
    )


# ── What a vendor may write to their own rows ───────────────────────────────
#
# Separate tuples, never the admin ones. `_VENDOR_SCALARS` drives a
# full-replacement loop and every field on the admin schema has a default, so
# importing it here would let a vendor write those defaults by pressing Save -
# even though their own schema never declares the fields. Concretely they would
# flip `is_active` back to True (un-suspending themselves, and
# `apply_vendor_cascade` would re-publish every package), wipe `rating` and
# `review_count`, zero `sort_order`, blank `internal_notes`, and re-point
# `google_place_id` at someone else's Google listing.

_PARTNER_VENDOR_SCALARS = (
    "name", "description", "address", "city", "country_code",
    "contact_email", "website", "logo_url", "photo_urls",
)

# How travellers reach a vendor directly. Admin only: bookings go through
# Nexaround, so a vendor cannot add a direct line around the commission. The
# portal shows them read-only.
_ADMIN_ONLY_VENDOR_CONTACTS = (
    "contact_phone", "contact_whatsapp", "contact_instagram",
    "contact_facebook", "contact_x",
)

_PARTNER_PACKAGE_SCALARS = (
    "title", "summary", "description", "category", "tags", "photo_urls",
    "unavailable_ranges",
    "price_amount", "price_currency", "price_basis", "duration_minutes",
    "max_participants", "booking_window_days", "inclusions", "languages",
    "uses_vendor_location", "meeting_point_address",
    # Kept deliberately: on a package this is the vendor's own publish toggle.
    # It is safe because `is_published` stays gated behind the vendor's
    # `is_active`, which only an admin can set - so a suspended vendor cannot
    # surface anything by flipping it.
    "is_active",
)


def _profile_response(vendor, package_count: int) -> PartnerVendorProfileResponse:
    """The vendor's own record, minus anything only the platform should see.

    Not `_vendor_response` from the admin router: that one returns
    `internal_notes`, which the model comment marks admin-only.
    """
    from app.utils.geo_utils import get_lat_lng

    lat, lng = get_lat_lng(vendor.location)
    return PartnerVendorProfileResponse(
        id=vendor.id,
        name=vendor.name,
        description=vendor.description,
        latitude=lat,
        longitude=lng,
        address=vendor.address,
        city=vendor.city,
        country_code=vendor.country_code,
        contact_phone=vendor.contact_phone,
        contact_whatsapp=vendor.contact_whatsapp,
        contact_instagram=vendor.contact_instagram,
        contact_facebook=vendor.contact_facebook,
        contact_x=vendor.contact_x,
        contact_email=vendor.contact_email,
        website=vendor.website,
        logo_url=vendor.logo_url,
        photo_urls=vendor.photo_urls or [],
        # Read-only here, and absent from the update schema: the vendor should
        # be able to see that their listing is hidden without being able to
        # un-hide it.
        is_active=bool(vendor.is_active),
        rating=float(vendor.rating) if vendor.rating is not None else None,
        review_count=vendor.review_count or 0,
        package_count=package_count,
        created_at=vendor.created_at,
        updated_at=vendor.updated_at,
    )


def _package_out(package) -> PartnerPackageResponse:
    from app.utils.geo_utils import get_lat_lng

    lat, lng = get_lat_lng(package.location)
    return PartnerPackageResponse(
        id=package.id,
        vendor_id=package.vendor_id,
        title=package.title,
        summary=package.summary,
        description=package.description,
        category=package.category,
        tags=package.tags or [],
        photo_urls=package.photo_urls or [],
        unavailable_ranges=package.unavailable_ranges or [],
        price_amount=float(package.price_amount) if package.price_amount is not None else None,
        price_currency=package.price_currency,
        price_basis=package.price_basis,
        # No dollar price: PriceOptionBase has none, so it is dropped here.
        price_options=package.price_options or [],
        duration_minutes=package.duration_minutes,
        max_participants=package.max_participants,
        booking_window_days=package.booking_window_days,
        inclusions=package.inclusions or [],
        languages=package.languages or [],
        uses_vendor_location=bool(package.uses_vendor_location),
        meeting_point_address=package.meeting_point_address,
        is_active=bool(package.is_active),
        is_published=bool(package.is_published),
        latitude=lat,
        longitude=lng,
        created_at=package.created_at,
        updated_at=package.updated_at,
    )


# ── Profile ─────────────────────────────────────────────────────────────────

@router.get("/profile", response_model=PartnerVendorProfileResponse)
async def get_partner_profile(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    packages = await ExperienceRepository(db).list_packages_for_vendor(
        principal.vendor.id
    )
    return _profile_response(principal.vendor, len(packages))


@router.put("/profile", response_model=PartnerVendorProfileResponse)
async def update_partner_profile(
    data: PartnerVendorProfileUpdate,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    from app.services.experience_service import apply_vendor_cascade
    from app.services.experience_format import vendor_place_problem
    from app.utils.geo_utils import point_or_none

    problem = vendor_place_problem(data.latitude, data.longitude, data.country_code)
    if problem:
        raise HTTPException(status_code=422, detail=problem)

    vendor = principal.vendor
    before = partner_activity.snapshot(vendor, _PARTNER_VENDOR_SCALARS)
    for key in _PARTNER_VENDOR_SCALARS:
        setattr(vendor, key, getattr(data, key))
    vendor.location = point_or_none(data.latitude, data.longitude)

    # A vendor that moved drags its packages with it. `apply_vendor_cascade`
    # does not commit, so the call and the commit are both needed - forgetting
    # the call leaves every package on the old coordinates with a stale
    # `is_published`.
    count = await apply_vendor_cascade(db, vendor)
    activity = partner_activity.profile_updated(
        db, vendor, before, actor=partner_activity.VENDOR, login=principal.login,
    )
    await db.commit()
    await db.refresh(vendor)
    await partner_events.publish(vendor.id, partner_events.ACCOUNT_CHANGED)
    await partner_activity.announce(activity)
    return _profile_response(vendor, count)


# ── Packages ────────────────────────────────────────────────────────────────

@router.get("/packages", response_model=PartnerPackageListResponse)
async def list_partner_packages(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    rows = await ExperienceRepository(db).list_packages_for_vendor(principal.vendor.id)
    return PartnerPackageListResponse(packages=[_package_out(p) for p in rows])


@router.post(
    "/packages",
    response_model=PartnerPackageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_partner_package(
    data: PartnerPackageCreate,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    from app.models.experience import ExperiencePackage
    from app.services.experience_service import apply_package_derived_fields

    package = ExperiencePackage(
        # Taken from the token, never from the body: a vendor_id in the payload
        # would be a way to file a package under someone else's name.
        vendor_id=principal.vendor.id,
        **{key: package_field_value(data, key) for key in _PARTNER_PACKAGE_SCALARS},
    )
    apply_price_options(package, price_options_for_save(data, None, vendor=True))

    apply_package_derived_fields(
        package, principal.vendor, data.latitude, data.longitude
    )
    db.add(package)
    await db.flush()  # the feed line links to the package's id
    activity = partner_activity.package_created(
        db, package, actor=partner_activity.VENDOR, login=principal.login,
    )
    await db.commit()
    await db.refresh(package)
    await partner_events.publish(principal.vendor.id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return _package_out(package)


@router.get("/packages/{package_id}", response_model=PartnerPackageResponse)
async def get_partner_package(
    package_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    package = await ExperienceRepository(db).get_package_for_vendor(
        package_id, principal.vendor.id
    )
    if package is None:
        # 404, not 403: a 403 would confirm the id exists and belongs to
        # someone else, which is an enumeration oracle over the marketplace.
        raise HTTPException(status_code=404, detail="Package not found")
    return _package_out(package)


@router.put("/packages/{package_id}", response_model=PartnerPackageResponse)
async def update_partner_package(
    package_id: uuid.UUID,
    data: PartnerPackageUpdate,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    from app.services.experience_service import apply_package_derived_fields

    repo = ExperienceRepository(db)
    package = await repo.get_package_for_vendor(package_id, principal.vendor.id)
    if package is None:
        raise HTTPException(status_code=404, detail="Package not found")

    before = partner_activity.snapshot(
        package, _PARTNER_PACKAGE_SCALARS + ("vendor_price_options",)
    )
    for key in _PARTNER_PACKAGE_SCALARS:
        setattr(package, key, package_field_value(data, key))
    apply_price_options(package, price_options_for_save(data, package.price_options, vendor=True))
    apply_package_derived_fields(
        package, principal.vendor, data.latitude, data.longitude
    )
    activity = partner_activity.package_updated(
        db, package, before, actor=partner_activity.VENDOR, login=principal.login,
    )
    await db.commit()
    await db.refresh(package)
    await partner_events.publish(principal.vendor.id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return _package_out(package)


@router.delete("/packages/{package_id}")
async def delete_partner_package(
    package_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    repo = ExperienceRepository(db)
    package = await repo.get_package_for_vendor(package_id, principal.vendor.id)
    if package is None:
        raise HTTPException(status_code=404, detail="Package not found")
    activity = partner_activity.package_deleted(
        db, package, actor=partner_activity.VENDOR, login=principal.login,
    )
    await db.delete(package)
    await db.commit()
    await partner_events.publish(principal.vendor.id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return {"status": "deleted"}


# ── Reviews ─────────────────────────────────────────────────────────────────

def _review_out(r) -> PartnerReviewResponse:
    return PartnerReviewResponse(
        id=r.id,
        package_id=r.package_id,
        package_title=r.package.title if r.package else None,
        reviewer_name=r.reviewer_name,
        rating=r.rating,
        comment=r.comment,
        created_at=r.created_at,
        edited_at=r.edited_at,
        vendor_reply=r.vendor_reply,
        vendor_replied_at=r.vendor_replied_at,
    )


@router.get("/reviews", response_model=PartnerReviewListResponse)
async def list_partner_reviews(
    unanswered: bool = Query(False),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """This vendor's published reviews. The scope comes from the token, never
    from a parameter, like the enquiries above; hidden reviews are not listed."""
    repo = ExperienceRepository(db)
    vendor_id = principal.vendor.id
    rows, total = await repo.list_reviews_for_vendor(
        vendor_id, unanswered_only=unanswered, page=page, page_size=page_size
    )
    average, count = (await repo.vendor_rating_summaries([vendor_id])).get(
        vendor_id, (None, 0)
    )
    _, open_count = await repo.list_reviews_for_vendor(
        vendor_id, unanswered_only=True, page=1, page_size=1
    )
    return PartnerReviewListResponse(
        reviews=[_review_out(r) for r in rows],
        total=total,
        page=page,
        page_size=page_size,
        average=average,
        review_count=count,
        unanswered=open_count,
    )


@router.put("/reviews/{review_id}/reply", response_model=PartnerReviewResponse)
async def reply_to_partner_review(
    review_id: uuid.UUID,
    data: PartnerReviewReply,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Answer a review in public, or edit the answer. An empty reply takes it
    down. Scoped in the query: another vendor's review is a 404."""
    review = await ExperienceRepository(db).get_review_for_vendor(
        review_id, principal.vendor.id
    )
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")
    reply = experience_reviews.clean_reply(data.reply)
    review.vendor_reply = reply
    review.vendor_replied_at = datetime.now(timezone.utc) if reply else None
    await db.commit()
    await db.refresh(review)
    return _review_out(review)


# ── Stats ───────────────────────────────────────────────────────────────────

@router.get("/stats", response_model=PartnerStatsResponse)
async def partner_stats(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return PartnerStatsResponse(
        **await ExperienceRepository(db).vendor_stats(principal.vendor.id)
    )


# ── Activity feed ───────────────────────────────────────────────────────────
#
# What the bell shows. Scoped by the token's vendor like everything else here;
# "notifications" is the same feed minus this login's own actions, and only
# those lines count as unread.

def _not_mine(login_id):
    from sqlalchemy import or_
    from app.models.experience import VendorActivity

    return or_(
        VendorActivity.actor_login_id.is_(None),
        VendorActivity.actor_login_id != login_id,
    )


def _shown(vendor_id):
    """This vendor's lines, less the enquiry lines written before vendors
    stopped seeing requests: they name the traveller."""
    from sqlalchemy import and_
    from app.models.experience import VendorActivity

    return and_(
        VendorActivity.vendor_id == vendor_id,
        VendorActivity.kind.notlike("enquiry.%"),
    )


async def _unread_count(db: AsyncSession, principal: VendorPrincipal) -> int:
    from sqlalchemy import func, select
    from app.models.experience import VendorActivity

    # A login that has never opened the panel counts from when it was
    # created, so a newly invited teammate does not inherit the whole history
    # as unread.
    since = principal.login.activity_seen_at or principal.login.created_at
    query = (
        select(func.count())
        .select_from(VendorActivity)
        .where(_shown(principal.vendor.id), _not_mine(principal.login.id))
    )
    if since is not None:
        query = query.where(VendorActivity.created_at > since)
    return int(await db.scalar(query) or 0)


@router.get("/activity", response_model=PartnerActivityListResponse)
async def list_partner_activity(
    scope: str = Query("all", pattern="^(all|notifications)$"),
    before: Optional[datetime] = Query(None),
    limit: int = Query(30, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Newest first. Page back with `before` = the last row's `created_at`."""
    from sqlalchemy import select
    from app.models.experience import VendorActivity

    query = select(VendorActivity).where(_shown(principal.vendor.id))
    if scope == "notifications":
        query = query.where(_not_mine(principal.login.id))
    if before is not None:
        query = query.where(VendorActivity.created_at < before)
    rows = (
        await db.execute(
            query.order_by(VendorActivity.created_at.desc()).limit(limit + 1)
        )
    ).scalars().all()

    return PartnerActivityListResponse(
        items=[PartnerActivity(**partner_activity.to_payload(r)) for r in rows[:limit]],
        has_more=len(rows) > limit,
        unread=await _unread_count(db, principal),
        seen_at=principal.login.activity_seen_at or principal.login.created_at,
    )


@router.get("/activity/unread", response_model=PartnerActivityUnreadResponse)
async def partner_activity_unread(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return PartnerActivityUnreadResponse(
        unread=await _unread_count(db, principal),
        seen_at=principal.login.activity_seen_at or principal.login.created_at,
    )


@router.post("/activity/seen", response_model=PartnerActivityUnreadResponse)
async def mark_partner_activity_seen(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Clear this login's bell. Teammates keep their own count."""
    from datetime import timezone

    login = principal.login
    login.activity_seen_at = datetime.now(timezone.utc)
    await db.commit()
    # This login's other open tabs clear their badge too.
    await partner_events.publish(
        principal.vendor.id, "activity.seen", {"login_id": str(login.id)},
    )
    return PartnerActivityUnreadResponse(unread=0, seen_at=login.activity_seen_at)


# ── Media and map search ────────────────────────────────────────────────────
#
# Both mirror the admin endpoints but add a per-vendor quota. The admin ones
# have none because an admin is trusted; an authenticated third party writing
# unbounded files to a named volume can fill the host disk, and every
# place-search spends real Google money.

@router.post("/upload")
async def partner_upload(
    files: List[UploadFile] = File(...),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Gallery images for this vendor's own profile and packages.

    The validation is `save_experience_images`, shared with the admin router so
    the two cannot drift — and this is the copy a semi-trusted caller reaches.
    """
    await check_account_rate_limit(
        str(principal.vendor.id),
        action="partner_upload",
        max_attempts=200,
        window_seconds=3600,
    )
    return {"urls": await save_experience_images(files)}


@router.get("/place-search")
async def partner_place_search(
    query: str = Query(..., min_length=2),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Google text search, for placing a pin on the map.

    Proxied rather than called from the browser so the Google key stays
    server-side, which is this project's standing rule.
    """
    await check_account_rate_limit(
        str(principal.vendor.id),
        action="partner_place_search",
        max_attempts=60,
        window_seconds=3600,
    )

    # Same reload as the admin version: SettingsService caches per process and
    # the API runs two workers, so a key saved in the admin panel can be live
    # in one and stale in the other.
    await SettingsService(db).load_settings()

    raw = await google_places_client.text_search(
        query=query, latitude=lat, longitude=lng
    )
    results = []
    for place in raw or []:
        location = place.get("location") or {}
        parts = google_places_client.extract_place_address_parts(place)
        results.append({
            "place_id": place.get("id"),
            "name": (place.get("displayName") or {}).get("text"),
            "address": place.get("formattedAddress"),
            "latitude": location.get("latitude"),
            "longitude": location.get("longitude"),
            "city": parts["city"],
            "country_code": parts["country_code"],
            "country_name": parts["country_name"],
        })
    return {"places": results}


# ── Devices and account activity ────────────────────────────────────────────

def _current_sid(authorization: str):
    from app.core.security import decode_token

    token = authorization.split(" ", 1)[1] if authorization.startswith("Bearer ") else ""
    return audit.parse_sid((decode_token(token) or {}).get("sid"))


@router.get("/sessions", response_model=PartnerSessionListResponse)
async def list_partner_sessions(
    authorization: str = Header(...),
    principal: VendorPrincipal = Depends(get_current_vendor),
    db: AsyncSession = Depends(get_db),
):
    """The devices signed in to *this* login. Not the vendor's other logins:
    nobody here can sign a colleague out."""
    from datetime import timezone

    from sqlalchemy import select

    from app.models.audit import AuthSession

    current = _current_sid(authorization)
    now = datetime.now(timezone.utc)
    rows = (await db.execute(
        select(AuthSession)
        .where(
            AuthSession.actor_type == "vendor",
            AuthSession.actor_id == str(principal.login.id),
            AuthSession.created_at >= now - timedelta(days=30),
        )
        .order_by(AuthSession.last_seen_at.desc())
        .limit(50)
    )).scalars().all()
    return PartnerSessionListResponse(items=[
        PartnerSessionOut(
            id=r.id, actor_label=r.actor_label, is_you=True, ip=r.ip,
            last_ip=r.last_ip, browser=r.browser, os=r.os,
            device_type=r.device_type, created_at=r.created_at,
            last_seen_at=r.last_seen_at, status=audit.session_status(r, now),
            is_current=(r.id == current),
        )
        for r in rows
    ])


async def _record_revocation(request, principal, row) -> None:
    await audit.record(
        actor_type="vendor", actor_id=str(principal.login.id),
        actor_label=principal.login.label, vendor_id=principal.vendor.id,
        category="auth", action="auth.session_revoked",
        summary=(
            f"Signed out {audit.describe_device(row.browser, row.os)} "
            f"({row.ip or 'unknown IP'})"
        ),
        method="POST", route="/api/v1/partner/sessions/{session_id}/revoke",
        path=request.url.path, target_id=str(row.id), status_code=200,
        meta=audit.client_meta(request),
    )


@router.post("/sessions/revoke-others", response_model=PartnerMessageResponse)
async def revoke_other_partner_sessions(
    request: Request,
    authorization: str = Header(...),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """Sign out every device except the one making this request."""
    count = await audit.revoke_sessions_for(
        actor_type="vendor", actor_id=str(principal.login.id), reason="user",
        by=principal.login.label, except_sid=_current_sid(authorization),
    )
    if count:
        await audit.record(
            actor_type="vendor", actor_id=str(principal.login.id),
            actor_label=principal.login.label, vendor_id=principal.vendor.id,
            category="auth", action="auth.sessions_revoked",
            summary=f"Signed out {count} other device{'s' if count != 1 else ''}",
            method="POST", route="/api/v1/partner/sessions/revoke-others",
            status_code=200, meta=audit.client_meta(request),
        )
    return PartnerMessageResponse(
        message=f"Signed out {count} other device{'s' if count != 1 else ''}."
    )


@router.post("/sessions/{session_id}/revoke", response_model=PartnerMessageResponse)
async def revoke_partner_session(
    session_id: uuid.UUID,
    request: Request,
    authorization: str = Header(...),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    if _current_sid(authorization) == session_id:
        raise HTTPException(
            status_code=400,
            detail="That is the device you are using. Use Sign out instead.",
        )
    # Scoped to this login in the lookup: someone else's session id is a 404,
    # the same as one that does not exist.
    row = await audit.revoke_session(
        session_id, reason="user", by=principal.login.label,
        actor_type="vendor", actor_id=str(principal.login.id),
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Device not found.")
    await _record_revocation(request, principal, row)
    return PartnerMessageResponse(message="Device signed out.")


@router.get("/audit", response_model=PartnerAuditListResponse)
async def list_partner_audit(
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    category: Optional[str] = Query(None, pattern="^(auth|change)$"),
    principal: VendorPrincipal = Depends(get_current_vendor),
    db: AsyncSession = Depends(get_db),
):
    """Sign-ins and changes on this vendor's account, newest first.

    Scoped by the vendor on the verified principal, never by a parameter. Admin
    activity is not listed: that is internal, and the vendor already sees what
    an admin changed on their listing in the activity feed.
    """
    from sqlalchemy import func, select

    from app.models.audit import AuditEvent

    conds = [
        AuditEvent.vendor_id == principal.vendor.id,
        AuditEvent.actor_type != "admin",
        AuditEvent.category.in_(("auth", "change")),
    ]
    if category:
        conds.append(AuditEvent.category == category)
    total = (await db.execute(
        select(func.count()).select_from(AuditEvent).where(*conds)
    )).scalar_one()
    rows = (await db.execute(
        select(AuditEvent).where(*conds)
        .order_by(AuditEvent.occurred_at.desc(), AuditEvent.id)
        .offset((page - 1) * page_size).limit(page_size)
    )).scalars().all()
    me = str(principal.login.id)
    return PartnerAuditListResponse(
        items=[
            PartnerAuditEventOut(
                id=r.id, occurred_at=r.occurred_at,
                actor_label=r.actor_label,
                # A failed attempt carries the login id too, but nobody who is
                # signed in made it.
                is_you=(r.actor_type == "vendor" and r.actor_id == me),
                category=r.category, summary=r.summary, success=r.success,
                ip=r.ip, browser=r.browser, os=r.os, device_type=r.device_type,
            )
            for r in rows
        ],
        total=total, page=page, page_size=page_size,
    )
