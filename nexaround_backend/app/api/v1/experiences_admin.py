"""Admin CRUD for the Experiences marketplace.

Kept out of `admin.py`, which is already long, following the precedent of
`telemetry_admin.py` — it imports the same `verify_admin_token` dependency.
"""

import io
import os
import uuid
from typing import List, Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile,
    status,
)
from PIL import Image
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import verify_admin_token
from app.core.config import settings
from app.core.database import get_db
from app.models.experience import ExperiencePackage, ExperienceVendor, VendorUser
from app.models.user import User
from app.schemas.partner import (
    VendorAppAccessCreate, VendorLoginAdminResponse, VendorLoginCreate,
    VendorLoginListResponse, VendorLoginUpdate,
)
from app.api.v1.partner import (
    _ADMIN_ONLY_VENDOR_CONTACTS, _PARTNER_PACKAGE_SCALARS, _PARTNER_VENDOR_SCALARS,
)
from app.services import (
    audit, enquiry_lifecycle, enquiry_notifications, partner_activity,
    partner_events,
)
from app.services.email_service import send_vendor_invite_email
from app.services.experience_upload import save_experience_images, save_experience_video
from app.services.partner_auth import store_link_token
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.experience import (
    ExperienceReviewAdminResponse,
    ExperienceReviewListResponse,
    ExperienceReviewUpdate,
    ExperienceEnquiryAdminResponse,
    ExperienceEnquiryListResponse,
    ExperienceEnquiryUpdate,
    ExperiencePackageAdminResponse,
    ExperiencePackageCreate,
    ExperiencePackageListResponse,
    ExperiencePackageUpdate,
    ExperienceVendorAdminResponse,
    ExperienceVendorCreate,
    ExperienceVendorListResponse,
    ExperienceVendorUpdate,
)
from app.services import experience_reviews, google_places_client
from app.services.experience_service import (
    apply_package_derived_fields, apply_vendor_cascade,
)
from app.services.settings_service import SettingsService
from app.services.experience_format import (
    apply_price_options, package_field_value, price_options_for_save, vendor_place_problem,
)
from app.utils.geo_utils import get_lat_lng, point_or_none

router = APIRouter(prefix="/admin/experiences", tags=["Admin Experiences"])

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
UPLOAD_DIR = "app/static/uploads/experiences"

# Every column create and update copy across. A field missing here is accepted
# by the schema, sent by the form and then silently dropped - which is exactly
# what happened to the three social links: they saved without error and came
# back empty on the next load.
_VENDOR_SCALARS = (
    "name", "description", "address", "google_place_id", "city", "country_code",
    "contact_phone", "contact_whatsapp", "contact_instagram", "contact_facebook",
    "contact_x", "contact_email", "website", "logo_url",
    "photo_urls", "rating", "review_count", "internal_notes", "is_active",
    "sort_order",
)

_PACKAGE_SCALARS = (
    "title", "summary", "description", "category", "tags", "photo_urls",
    "video_urls", "unavailable_ranges", "price_amount", "price_currency", "price_usd", "price_basis", "duration_minutes",
    "max_participants", "booking_window_days", "inclusions", "languages",
    "uses_vendor_location", "meeting_point_address", "region_label", "is_active",
    "sort_order",
)


def _vendor_response(
    vendor: ExperienceVendor, package_count: int = 0, rating=(None, 0)
) -> ExperienceVendorAdminResponse:
    lat, lng = get_lat_lng(vendor.location)
    return ExperienceVendorAdminResponse(
        id=vendor.id,
        name=vendor.name,
        description=vendor.description,
        latitude=lat,
        longitude=lng,
        address=vendor.address,
        google_place_id=vendor.google_place_id,
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
        rating=float(vendor.rating) if vendor.rating is not None else None,
        review_count=vendor.review_count or 0,
        internal_notes=vendor.internal_notes,
        is_active=vendor.is_active,
        sort_order=vendor.sort_order or 0,
        package_count=package_count,
        traveller_rating=rating[0],
        traveller_review_count=rating[1],
        created_at=vendor.created_at,
        updated_at=vendor.updated_at,
    )


def _package_response(
    package: ExperiencePackage, rating=(None, 0)
) -> ExperiencePackageAdminResponse:
    lat, lng = get_lat_lng(package.location)
    return ExperiencePackageAdminResponse(
        id=package.id,
        vendor_id=package.vendor_id,
        title=package.title,
        summary=package.summary,
        description=package.description,
        category=package.category,
        tags=package.tags or [],
        photo_urls=package.photo_urls or [],
        video_urls=package.video_urls or [],
        unavailable_ranges=package.unavailable_ranges or [],
        price_amount=(
            float(package.price_amount) if package.price_amount is not None else None
        ),
        price_currency=package.price_currency or "USD",
        price_usd=float(package.price_usd) if package.price_usd is not None else None,
        price_basis=package.price_basis or "per_person",
        price_options=package.price_options or [],
        duration_minutes=package.duration_minutes,
        max_participants=package.max_participants,
        booking_window_days=package.booking_window_days,
        inclusions=package.inclusions or [],
        languages=package.languages or [],
        uses_vendor_location=package.uses_vendor_location,
        latitude=lat,
        longitude=lng,
        meeting_point_address=package.meeting_point_address,
        region_label=package.region_label,
        is_active=package.is_active,
        is_published=package.is_published,
        rating_avg=rating[0],
        rating_count=rating[1],
        sort_order=package.sort_order or 0,
        created_at=package.created_at,
        updated_at=package.updated_at,
    )


# --- Vendors ----------------------------------------------------------------

@router.get("/vendors", response_model=ExperienceVendorListResponse)
async def list_vendors(
    search: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    vendors, total = await repo.list_vendors(
        search=search, is_active=is_active, page=page, page_size=page_size
    )
    out = []
    ratings = await repo.vendor_rating_summaries([v.id for v in vendors])
    for vendor in vendors:
        packages = await repo.list_packages_for_vendor(vendor.id)
        out.append(_vendor_response(vendor, len(packages), ratings.get(vendor.id, (None, 0))))
    return ExperienceVendorListResponse(
        vendors=out, total=total, page=page, page_size=page_size
    )


@router.get("/vendors/{vendor_id}", response_model=ExperienceVendorAdminResponse)
async def get_vendor(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    packages = await repo.list_packages_for_vendor(vendor_id)
    rating = (await repo.vendor_rating_summaries([vendor_id])).get(vendor_id, (None, 0))
    return _vendor_response(vendor, len(packages), rating)


def _require_findable(data) -> None:
    """422 unless the vendor has a country and a complete or empty pin."""
    problem = vendor_place_problem(data.latitude, data.longitude, data.country_code)
    if problem:
        raise HTTPException(status_code=422, detail=problem)


@router.post(
    "/vendors",
    response_model=ExperienceVendorAdminResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_vendor(
    data: ExperienceVendorCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    _require_findable(data)
    vendor = ExperienceVendor(
        location=point_or_none(data.latitude, data.longitude),
        **{key: getattr(data, key) for key in _VENDOR_SCALARS},
    )
    db.add(vendor)
    await db.commit()
    await db.refresh(vendor)
    return _vendor_response(vendor, 0)


@router.put("/vendors/{vendor_id}", response_model=ExperienceVendorAdminResponse)
async def update_vendor(
    vendor_id: uuid.UUID,
    data: ExperienceVendorUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    _require_findable(data)

    # Judged on what the vendor can see, plus is_active for suspend/restore:
    # an edit to internal_notes or sort_order must not reach their feed.
    before = partner_activity.snapshot(
        vendor, _PARTNER_VENDOR_SCALARS + _ADMIN_ONLY_VENDOR_CONTACTS + ("is_active",)
    )
    for key in _VENDOR_SCALARS:
        setattr(vendor, key, getattr(data, key))
    vendor.location = point_or_none(data.latitude, data.longitude)

    # A vendor that moved drags its packages with it; one that was deactivated
    # hides them. Without this the cards stay at the old coordinates forever.
    count = await apply_vendor_cascade(db, vendor)
    activity = partner_activity.profile_updated(
        db, vendor, before, actor=partner_activity.ADMIN,
    )
    await db.commit()
    await db.refresh(vendor)
    await partner_activity.announce(activity)
    # Suspending a vendor ends their open portal sessions now; any other edit
    # refreshes the name and package visibility they are looking at.
    await partner_events.publish(vendor.id, partner_events.ACCOUNT_CHANGED)
    return _vendor_response(vendor, count)


@router.delete("/vendors/{vendor_id}")
async def delete_vendor(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    await db.delete(vendor)  # packages cascade at the FK
    await db.commit()
    await partner_events.publish(vendor_id, partner_events.ACCOUNT_CHANGED)
    return {"status": "success"}


# --- Packages ---------------------------------------------------------------

@router.get(
    "/vendors/{vendor_id}/packages", response_model=ExperiencePackageListResponse
)
async def list_vendor_packages(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    packages = await repo.list_packages_for_vendor(vendor_id)
    ratings = await repo.rating_summaries([p.id for p in packages])
    return ExperiencePackageListResponse(
        packages=[_package_response(p, ratings.get(p.id, (None, 0))) for p in packages],
        total=len(packages),
    )


@router.post(
    "/vendors/{vendor_id}/packages",
    response_model=ExperiencePackageAdminResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_package(
    vendor_id: uuid.UUID,
    data: ExperiencePackageCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")

    package = ExperiencePackage(
        vendor_id=vendor.id,
        **{key: package_field_value(data, key) for key in _PACKAGE_SCALARS},
    )
    apply_price_options(package, price_options_for_save(data, None))
    apply_package_derived_fields(package, vendor, data.latitude, data.longitude)
    db.add(package)
    await db.flush()  # the feed line links to the package's id
    activity = partner_activity.package_created(db, package, actor=partner_activity.ADMIN)
    await db.commit()
    await db.refresh(package)
    await partner_events.publish(vendor.id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return _package_response(package)


@router.put("/packages/{package_id}", response_model=ExperiencePackageAdminResponse)
async def update_package(
    package_id: uuid.UUID,
    data: ExperiencePackageUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    package = await repo.get_package(package_id, published_only=False)
    if not package:
        raise HTTPException(status_code=404, detail="Package not found")
    vendor = await repo.get_vendor(package.vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")

    before = partner_activity.snapshot(
        package, _PARTNER_PACKAGE_SCALARS + ("vendor_price_options",)
    )
    for key in _PACKAGE_SCALARS:
        setattr(package, key, package_field_value(data, key))
    apply_price_options(package, price_options_for_save(data, package.price_options))
    apply_package_derived_fields(package, vendor, data.latitude, data.longitude)
    activity = partner_activity.package_updated(
        db, package, before, actor=partner_activity.ADMIN,
    )

    await db.commit()
    await db.refresh(package)
    await partner_events.publish(vendor.id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return _package_response(package)


@router.delete("/packages/{package_id}")
async def delete_package(
    package_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    package = await repo.get_package(package_id, published_only=False)
    if not package:
        raise HTTPException(status_code=404, detail="Package not found")
    vendor_id = package.vendor_id
    activity = partner_activity.package_deleted(db, package, actor=partner_activity.ADMIN)
    await db.delete(package)
    await db.commit()
    await partner_events.publish(vendor_id, partner_events.PACKAGES_CHANGED)
    await partner_activity.announce(activity)
    return {"status": "success"}


# --- Enquiries --------------------------------------------------------------

@router.get("/enquiries", response_model=ExperienceEnquiryListResponse)
async def list_enquiries(
    status_filter: Optional[str] = Query(None, alias="status"),
    vendor_id: Optional[uuid.UUID] = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    repo = ExperienceRepository(db)
    rows, total = await repo.list_enquiries(
        status=status_filter, vendor_id=vendor_id, page=page, page_size=page_size
    )
    return ExperienceEnquiryListResponse(
        enquiries=[ExperienceEnquiryAdminResponse.model_validate(r) for r in rows],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.patch(
    "/enquiries/{enquiry_id}", response_model=ExperienceEnquiryAdminResponse
)
async def update_enquiry(
    enquiry_id: uuid.UUID,
    data: ExperienceEnquiryUpdate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    from datetime import datetime, timezone

    from app.models.experience import ExperienceEnquiry

    enquiry = await db.get(ExperienceEnquiry, enquiry_id)
    if not enquiry:
        raise HTTPException(status_code=404, detail="Enquiry not found")
    event = None
    # An admin may set any status, including reopening a cancelled request; a
    # confirmation still needs a date. Vendors never see who asked.
    if data.status is not None and data.status not in (*enquiry_lifecycle.ALL_STATUSES, "spam"):
        raise HTTPException(status_code=400, detail="Unknown status.")
    booked = enquiry_lifecycle.booked_date(enquiry, data.confirmed_date)
    if data.status == enquiry_lifecycle.CONFIRMED and booked is None:
        raise HTTPException(status_code=400, detail="Choose the confirmed date.")
    if data.status is not None and (
        data.status != enquiry.status or data.confirmed_date is not None
    ):
        event = enquiry_lifecycle.apply_status(
            enquiry, data.status,
            now=datetime.now(timezone.utc),
            confirmed_date=data.confirmed_date,
            reason=data.cancellation_reason,
        )
    if data.admin_notes is not None:
        enquiry.admin_notes = data.admin_notes
    # A confirmation or cancellation reaches the vendor's bell (web and app):
    # package, date and guests only, never who the traveller is.
    activity = partner_activity.request_updated(db, enquiry, event) if event else None
    await db.commit()
    await db.refresh(enquiry)
    if event in (enquiry_lifecycle.CONFIRMED, enquiry_lifecycle.PROVIDER_CANCELLED):
        background_tasks.add_task(enquiry_notifications.booking_update, enquiry.id, event)
    elif event == enquiry_lifecycle.CUSTOMER_CANCELLED:
        background_tasks.add_task(enquiry_notifications.customer_cancelled, enquiry.id)
    if activity:
        background_tasks.add_task(partner_activity.announce, activity)
        background_tasks.add_task(enquiry_notifications.vendor_update_alert, enquiry.id, event)
    return ExperienceEnquiryAdminResponse.model_validate(enquiry)


# --- Reviews ----------------------------------------------------------------

async def _review_admin_out(db: AsyncSession, review) -> ExperienceReviewAdminResponse:
    vendor = await db.get(ExperienceVendor, review.vendor_id)
    return ExperienceReviewAdminResponse(
        id=review.id,
        package_id=review.package_id,
        package_title=review.package.title if review.package else None,
        vendor_id=review.vendor_id,
        vendor_name=vendor.name if vendor else None,
        reviewer_name=review.reviewer_name,
        rating=review.rating,
        comment=review.comment,
        status=review.status,
        vendor_reply=review.vendor_reply,
        vendor_replied_at=review.vendor_replied_at,
        created_at=review.created_at,
        edited_at=review.edited_at,
        hidden_at=review.hidden_at,
    )


@router.get("/reviews", response_model=ExperienceReviewListResponse)
async def list_reviews(
    status_filter: Optional[str] = Query(None, alias="status"),
    package_id: Optional[uuid.UUID] = Query(None),
    vendor_id: Optional[uuid.UUID] = Query(None),
    rating: Optional[int] = Query(None, ge=1, le=5),
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Every review, hidden ones included, newest first."""
    if status_filter and status_filter not in experience_reviews.STATUSES:
        raise HTTPException(status_code=400, detail="Unknown status.")
    rows, total = await ExperienceRepository(db).list_reviews_admin(
        status=status_filter, package_id=package_id, vendor_id=vendor_id,
        rating=rating, page=page, page_size=page_size,
    )
    return ExperienceReviewListResponse(
        reviews=[await _review_admin_out(db, r) for r in rows],
        total=total, page=page, page_size=page_size,
    )


@router.patch("/reviews/{review_id}", response_model=ExperienceReviewAdminResponse)
async def update_review(
    review_id: uuid.UUID,
    data: ExperienceReviewUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Hide or restore a review, and/or take the provider's reply down. A hidden
    review leaves every average and list at once, and comes back the same way."""
    from datetime import datetime, timezone

    review = await ExperienceRepository(db).get_review(review_id)
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")
    if data.status is not None:
        if data.status not in experience_reviews.STATUSES:
            raise HTTPException(status_code=400, detail="Unknown status.")
        if data.status != review.status:
            review.status = data.status
            review.hidden_at = (
                datetime.now(timezone.utc) if data.status == experience_reviews.HIDDEN else None
            )
    if data.clear_reply:
        review.vendor_reply = None
        review.vendor_replied_at = None
    await db.commit()
    await db.refresh(review)
    return await _review_admin_out(db, review)


# --- Supporting endpoints ---------------------------------------------------

@router.post("/upload")
async def upload_experience_images(
    files: List[UploadFile] = File(...),
    _=Depends(verify_admin_token),
):
    """Multi-image upload for vendor and package galleries.

    The validation and storage live in `experience_upload` so the partner
    router runs exactly the same checks — see that module for why they are not
    two copies.
    """
    return {"urls": await save_experience_images(files)}


@router.post("/upload-video")
async def upload_experience_video(
    file: UploadFile = File(...),
    _=Depends(verify_admin_token),
):
    """One video for a package. Sent one per request so the panel can show
    progress per file and each stays under the proxy's body-size cap."""
    return {"urls": [await save_experience_video(file)]}


@router.get("/place-search")
async def admin_place_search(
    query: str = Query(..., min_length=2),
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Google text search for positioning a vendor.

    `/places/search` cannot be reused: it requires a *user* JWT and an admin
    holds an admin-role token. Proxying here keeps the Google key server-side,
    which is this project's standing rule.
    """
    # SettingsService caches per process and the API runs two workers, so a key
    # saved in the admin panel can be live in one worker and stale in the
    # other. One cheap reload on this low-volume endpoint removes the
    # "search silently returns nothing until you restart" trap.
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


# ── Partner portal logins ───────────────────────────────────────────────────
#
# A vendor's credentials live in `vendor_users`, not `users` — see the model
# docstring for why that separation is structural rather than stylistic. These
# endpoints are how a login comes into existence: the admin names the email,
# the vendor sets their own password from the link. The admin never sees or
# chooses the password.

async def _login_response(vu: VendorUser, app_user: Optional[User] = None) -> VendorLoginAdminResponse:
    return VendorLoginAdminResponse(
        id=vu.id,
        vendor_id=vu.vendor_id,
        kind="app" if vu.app_user_id else "portal",
        email=vu.email,
        display_name=vu.display_name,
        app_user_id=vu.app_user_id,
        app_user_email=app_user.email if app_user else None,
        app_user_name=app_user.display_name if app_user else None,
        is_active=bool(vu.is_active),
        # The question the admin is actually asking of this row.
        has_password=vu.password_hash is not None,
        last_login_at=vu.last_login_at,
        created_at=vu.created_at,
    )


async def _send_link(vu: VendorUser, vendor: ExperienceVendor, *, is_reset: bool) -> None:
    token = await store_link_token(vu.id, is_reset=is_reset)
    link = f"{settings.PARTNER_PORTAL_URL.rstrip('/')}/set-password?token={token}"
    await send_vendor_invite_email(vu.email, vendor.name, link, is_reset=is_reset)


@router.get("/vendors/{vendor_id}/logins", response_model=VendorLoginListResponse)
async def list_vendor_logins(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    rows = (
        await db.execute(
            select(VendorUser)
            .where(VendorUser.vendor_id == vendor_id)
            .order_by(VendorUser.created_at.asc())
        )
    ).scalars().all()
    return VendorLoginListResponse(
        logins=[
            await _login_response(r, await db.get(User, r.app_user_id) if r.app_user_id else None)
            for r in rows
        ]
    )


@router.post(
    "/vendors/{vendor_id}/app-access",
    response_model=VendorLoginAdminResponse,
    status_code=status.HTTP_201_CREATED,
)
async def give_vendor_app_access(
    vendor_id: uuid.UUID,
    data: VendorAppAccessCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """Let a traveller account manage this vendor from the app.

    An app login: no email, no password, no invite. The app shows its
    "Vendor portal" button from then on (GET /partner/app/access).
    """
    vendor = await ExperienceRepository(db).get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    user = await db.get(User, data.user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=404, detail="App user not found")

    vu = VendorUser(
        vendor_id=vendor_id,
        app_user_id=user.id,
        display_name=((user.display_name or "").strip() or (user.email or "").split("@")[0] or None),
    )
    db.add(vu)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409, detail="That app user already has access to this vendor.",
        )
    await db.refresh(vu)
    await partner_events.publish(vendor_id, partner_events.ACCOUNT_CHANGED)
    return await _login_response(vu, user)


@router.post(
    "/vendors/{vendor_id}/logins",
    response_model=VendorLoginAdminResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_vendor_login(
    vendor_id: uuid.UUID,
    data: VendorLoginCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    vendor = await ExperienceRepository(db).get_vendor(vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")

    vu = VendorUser(
        vendor_id=vendor_id,
        email=str(data.email).strip().lower(),
        display_name=data.display_name,
    )
    db.add(vu)
    try:
        await db.commit()
    except IntegrityError:
        # The email is unique across every vendor. Without this the unique
        # index surfaces as a 500 and the admin sees "something went wrong"
        # instead of "that address already has a login".
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="That email address already has a partner login.",
        )
    await db.refresh(vu)

    await _send_link(vu, vendor, is_reset=False)
    return await _login_response(vu)


@router.post(
    "/logins/{login_id}/resend-invite", response_model=VendorLoginAdminResponse,
)
async def resend_vendor_invite(
    login_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    vu = await db.get(VendorUser, login_id)
    if not vu:
        raise HTTPException(status_code=404, detail="Login not found")
    if not vu.email:
        raise HTTPException(
            status_code=400, detail="App access has no email or password to set.",
        )
    vendor = await ExperienceRepository(db).get_vendor(vu.vendor_id)
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")

    # Sending a fresh token revokes the previous one (see `store_link_token`),
    # so "resend because the first email went astray" closes the old link
    # rather than leaving two live.
    await _send_link(vu, vendor, is_reset=vu.password_hash is not None)
    return await _login_response(vu)


@router.patch("/logins/{login_id}", response_model=VendorLoginAdminResponse)
async def update_vendor_login(
    login_id: uuid.UUID,
    data: VendorLoginUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    vu = await db.get(VendorUser, login_id)
    if not vu:
        raise HTTPException(status_code=404, detail="Login not found")
    vu.is_active = data.is_active
    await db.commit()
    await db.refresh(vu)
    if not vu.is_active:
        # Requests are already refused for a disabled login; this makes the
        # devices list say so too.
        await audit.revoke_sessions_for(
            actor_type="vendor", actor_id=str(vu.id), reason="admin", by="admin",
        )
    # A disabled login's open portal tabs are signed out now, not in an hour.
    await partner_events.publish(vu.vendor_id, partner_events.ACCOUNT_CHANGED)
    return await _login_response(vu, await db.get(User, vu.app_user_id) if vu.app_user_id else None)


@router.delete("/logins/{login_id}")
async def delete_vendor_login(
    login_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    vu = await db.get(VendorUser, login_id)
    if not vu:
        raise HTTPException(status_code=404, detail="Login not found")
    vendor_id = vu.vendor_id
    login_id_str = str(vu.id)
    await db.delete(vu)
    await db.commit()
    await audit.revoke_sessions_for(
        actor_type="vendor", actor_id=login_id_str, reason="admin", by="admin",
    )
    await partner_events.publish(vendor_id, partner_events.ACCOUNT_CHANGED)
    return {"status": "deleted"}
