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
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.admin import verify_admin_token
from app.core.database import get_db
from app.models.experience import ExperiencePackage, ExperienceVendor
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

_VENDOR_SCALARS = (
    "name", "description", "address", "google_place_id", "city", "country_code",
    "contact_phone", "contact_whatsapp", "contact_email", "website", "logo_url",
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
