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
from typing import List, Optional

from fastapi import (
    APIRouter, Depends, File, Header, HTTPException, Query, UploadFile, status,
)
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
    ENQUIRY_STATUSES,
    PartnerEnquiryListResponse, PartnerEnquiryResponse, PartnerEnquiryUpdate,
    PartnerForgotPasswordRequest, PartnerLoginRequest, PartnerMe,
    PartnerMessageResponse, PartnerPackageCreate, PartnerPackageListResponse,
    PartnerPackageResponse, PartnerPackageUpdate, PartnerSetPasswordRequest,
    PartnerTokenResponse, PartnerStatsResponse, PartnerVendorProfileResponse,
    PartnerVendorProfileUpdate,
)
from app.services import google_places_client
from app.services.email_service import send_vendor_invite_email
from app.services.experience_upload import save_experience_images
from app.services.settings_service import SettingsService
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
    "contact_phone", "contact_whatsapp", "contact_instagram",
    "contact_facebook", "contact_x", "contact_email", "website",
    "logo_url", "photo_urls",
)

_PARTNER_PACKAGE_SCALARS = (
    "title", "summary", "description", "category", "tags", "photo_urls",
    "price_amount", "price_currency", "price_basis", "duration_minutes",
    "max_participants", "inclusions", "languages", "uses_vendor_location",
    "meeting_point_address",
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
        price_amount=float(package.price_amount) if package.price_amount is not None else None,
        price_currency=package.price_currency,
        price_basis=package.price_basis,
        duration_minutes=package.duration_minutes,
        max_participants=package.max_participants,
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


def _enquiry_out(e) -> PartnerEnquiryResponse:
    return PartnerEnquiryResponse(
        id=e.id,
        package_id=e.package_id,
        package_title_snapshot=e.package_title_snapshot,
        contact_name=e.contact_name,
        contact_phone=e.contact_phone,
        contact_email=e.contact_email,
        preferred_date=e.preferred_date,
        party_size=e.party_size,
        message=e.message,
        status=e.status,
        vendor_notes=e.vendor_notes,
        created_at=e.created_at,
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
    from app.utils.geo_utils import create_point

    vendor = principal.vendor
    for key in _PARTNER_VENDOR_SCALARS:
        setattr(vendor, key, getattr(data, key))
    vendor.location = create_point(data.latitude, data.longitude)

    # A vendor that moved drags its packages with it. `apply_vendor_cascade`
    # does not commit, so the call and the commit are both needed - forgetting
    # the call leaves every package on the old coordinates with a stale
    # `is_published`.
    count = await apply_vendor_cascade(db, vendor)
    await db.commit()
    await db.refresh(vendor)
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
        **{key: getattr(data, key) for key in _PARTNER_PACKAGE_SCALARS},
    )
    apply_package_derived_fields(
        package, principal.vendor, data.latitude, data.longitude
    )
    db.add(package)
    await db.commit()
    await db.refresh(package)
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

    for key in _PARTNER_PACKAGE_SCALARS:
        setattr(package, key, getattr(data, key))
    apply_package_derived_fields(
        package, principal.vendor, data.latitude, data.longitude
    )
    await db.commit()
    await db.refresh(package)
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
    await db.delete(package)
    await db.commit()
    return {"status": "deleted"}


# ── Enquiries ───────────────────────────────────────────────────────────────

@router.get("/enquiries", response_model=PartnerEnquiryListResponse)
async def list_partner_enquiries(
    status_filter: Optional[str] = Query(None, alias="status"),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    """This vendor's enquiries.

    There is deliberately NO `vendor_id` parameter. The admin version of this
    endpoint has one, and copying it across would hand vendor A vendor B's
    entire inbox with a single query string. The scope comes from the token.
    """
    rows, total = await ExperienceRepository(db).list_enquiries(
        status=status_filter,
        vendor_id=principal.vendor.id,
        page=page,
        page_size=page_size,
    )
    return PartnerEnquiryListResponse(
        enquiries=[_enquiry_out(r) for r in rows],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.patch("/enquiries/{enquiry_id}", response_model=PartnerEnquiryResponse)
async def update_partner_enquiry(
    enquiry_id: uuid.UUID,
    data: PartnerEnquiryUpdate,
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    enquiry = await ExperienceRepository(db).get_enquiry_for_vendor(
        enquiry_id, principal.vendor.id
    )
    if enquiry is None:
        raise HTTPException(status_code=404, detail="Enquiry not found")

    if data.status is not None:
        # The column has no CHECK constraint, so an unvalidated status would
        # let a vendor write "deleted" and vanish the row from every filtered
        # admin view.
        if data.status not in ENQUIRY_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Status must be one of: {', '.join(ENQUIRY_STATUSES)}",
            )
        enquiry.status = data.status
    if data.vendor_notes is not None:
        # Their own field. `admin_notes` is the platform's and stays untouched.
        enquiry.vendor_notes = data.vendor_notes

    await db.commit()
    await db.refresh(enquiry)
    return _enquiry_out(enquiry)


# ── Stats ───────────────────────────────────────────────────────────────────

@router.get("/stats", response_model=PartnerStatsResponse)
async def partner_stats(
    db: AsyncSession = Depends(get_db),
    principal: VendorPrincipal = Depends(get_current_vendor),
):
    return PartnerStatsResponse(
        **await ExperienceRepository(db).vendor_stats(principal.vendor.id)
    )


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
        results.append({
            "place_id": place.get("id"),
            "name": (place.get("displayName") or {}).get("text"),
            "address": place.get("formattedAddress"),
            "latitude": location.get("latitude"),
            "longitude": location.get("longitude"),
        })
    return {"places": results}
