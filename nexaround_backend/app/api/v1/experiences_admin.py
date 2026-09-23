"""Admin CRUD for the Experiences marketplace.

Kept out of `admin.py`, which is already long, following the precedent of
`telemetry_admin.py` — it imports the same `verify_admin_token` dependency.
"""

import io
import os
import uuid
from typing import List, Optional

from fastapi import (
    APIRouter, Depends, File, HTTPException, Query, UploadFile, status,
)
from PIL import Image
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import verify_admin_token
from app.core.config import settings
from app.core.database import get_db
from app.models.experience import ExperiencePackage, ExperienceVendor, VendorUser
from app.schemas.partner import (
    VendorLoginAdminResponse, VendorLoginCreate, VendorLoginListResponse,
    VendorLoginUpdate,
)
from app.services.email_service import send_vendor_invite_email
from app.services.partner_auth import store_link_token
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.experience import (
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
from app.services import google_places_client
from app.services.experience_service import (
    apply_package_derived_fields, apply_vendor_cascade,
)
from app.services.settings_service import SettingsService
from app.utils.geo_utils import create_point, get_lat_lng

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
    "price_amount", "price_currency", "price_basis", "duration_minutes",
    "max_participants", "inclusions", "languages", "uses_vendor_location",
    "meeting_point_address", "is_active", "sort_order",
)


def _vendor_response(
    vendor: ExperienceVendor, package_count: int = 0
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
        created_at=vendor.created_at,
        updated_at=vendor.updated_at,
    )


def _package_response(package: ExperiencePackage) -> ExperiencePackageAdminResponse:
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
        price_amount=(
            float(package.price_amount) if package.price_amount is not None else None
        ),
        price_currency=package.price_currency or "USD",
        price_basis=package.price_basis or "per_person",
        duration_minutes=package.duration_minutes,
        max_participants=package.max_participants,
        inclusions=package.inclusions or [],
        languages=package.languages or [],
        uses_vendor_location=package.uses_vendor_location,
        latitude=lat,
        longitude=lng,
        meeting_point_address=package.meeting_point_address,
        is_active=package.is_active,
        is_published=package.is_published,
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
    for vendor in vendors:
        packages = await repo.list_packages_for_vendor(vendor.id)
        out.append(_vendor_response(vendor, len(packages)))
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
    return _vendor_response(vendor, len(packages))


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
    vendor = ExperienceVendor(
        location=create_point(data.latitude, data.longitude),
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

    for key in _VENDOR_SCALARS:
        setattr(vendor, key, getattr(data, key))
    vendor.location = create_point(data.latitude, data.longitude)

    # A vendor that moved drags its packages with it; one that was deactivated
    # hides them. Without this the cards stay at the old coordinates forever.
    count = await apply_vendor_cascade(db, vendor)
    await db.commit()
    await db.refresh(vendor)
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
    return ExperiencePackageListResponse(
        packages=[_package_response(p) for p in packages], total=len(packages)
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
        **{key: getattr(data, key) for key in _PACKAGE_SCALARS},
    )
    apply_package_derived_fields(package, vendor, data.latitude, data.longitude)
    db.add(package)
    await db.commit()
    await db.refresh(package)
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

    for key in _PACKAGE_SCALARS:
        setattr(package, key, getattr(data, key))
    apply_package_derived_fields(package, vendor, data.latitude, data.longitude)

    await db.commit()
    await db.refresh(package)
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
    await db.delete(package)
    await db.commit()
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
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    from app.models.experience import ExperienceEnquiry

    enquiry = await db.get(ExperienceEnquiry, enquiry_id)
    if not enquiry:
        raise HTTPException(status_code=404, detail="Enquiry not found")
    if data.status is not None:
        enquiry.status = data.status
    if data.admin_notes is not None:
        enquiry.admin_notes = data.admin_notes
    await db.commit()
    await db.refresh(enquiry)
    return ExperienceEnquiryAdminResponse.model_validate(enquiry)


# --- Supporting endpoints ---------------------------------------------------

@router.post("/upload")
async def upload_experience_images(
    files: List[UploadFile] = File(...),
    _=Depends(verify_admin_token),
):
    """Multi-image upload for vendor and package galleries.

    Mirrors `travel_stories.upload_story_images` — extension allowlist, size
    cap and a real Pillow decode, so a renamed executable cannot land in the
    static directory. Returns `/static/...` paths, which the app serves without
    auth headers.
    """
    os.makedirs(UPLOAD_DIR, exist_ok=True)

    urls = []
    for file in files:
        filename = file.filename or ""
        file_ext = os.path.splitext(filename)[1].lower()
        if file_ext not in ALLOWED_IMAGE_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"File extension '{file_ext}' is not allowed. "
                    "Only JPG, PNG, WEBP, and GIF images are permitted."
                ),
            )

        content = await file.read()
        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File size exceeds maximum allowed limit (10MB)",
            )

        try:
            img = Image.open(io.BytesIO(content))
            img.verify()
            if img.format not in ["JPEG", "PNG", "WEBP", "GIF"]:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid image format",
                )
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded file is not a valid image",
            )

        unique_filename = f"{uuid.uuid4()}{file_ext}"
        with open(os.path.join(UPLOAD_DIR, unique_filename), "wb") as buffer:
            buffer.write(content)
        urls.append(f"/static/uploads/experiences/{unique_filename}")

    return {"urls": urls}


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
        results.append({
            "place_id": place.get("id"),
            "name": (place.get("displayName") or {}).get("text"),
            "address": place.get("formattedAddress"),
            "latitude": location.get("latitude"),
            "longitude": location.get("longitude"),
        })
    return {"places": results}


# ── Partner portal logins ───────────────────────────────────────────────────
#
# A vendor's credentials live in `vendor_users`, not `users` — see the model
# docstring for why that separation is structural rather than stylistic. These
# endpoints are how a login comes into existence: the admin names the email,
# the vendor sets their own password from the link. The admin never sees or
# chooses the password.

async def _login_response(vu: VendorUser) -> VendorLoginAdminResponse:
    return VendorLoginAdminResponse(
        id=vu.id,
        vendor_id=vu.vendor_id,
        email=vu.email,
        display_name=vu.display_name,
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
        logins=[await _login_response(r) for r in rows]
    )


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
    return await _login_response(vu)


@router.delete("/logins/{login_id}")
async def delete_vendor_login(
    login_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    vu = await db.get(VendorUser, login_id)
    if not vu:
        raise HTTPException(status_code=404, detail="Login not found")
    await db.delete(vu)
    await db.commit()
    return {"status": "deleted"}
