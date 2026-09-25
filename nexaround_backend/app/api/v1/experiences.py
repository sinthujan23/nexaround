"""App-facing Experiences endpoints: the vendor marketplace in Discovery."""

import uuid
from typing import Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, HTTPException, Query, status,
)
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user_optional
from app.core.database import async_session, get_db
from app.models.experience import ExperienceEnquiry
from app.models.user import User
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.experience import (
    ExperienceEnquiryCreate,
    ExperienceEnquiryResponse,
    ExperienceNearbyResponse,
    ExperiencePackageDetail,
    ExperienceVendorPublic,
)
from app.services.email_service import send_vendor_enquiry_email
from app.services.experience_format import (
    NEARBY_THRESHOLD_M, is_nearby, validate_enquiry_payload,
)
from app.services.experience_service import (
    package_to_card, package_to_detail, vendor_to_public,
)
from app.services import partner_activity, partner_events
from app.services.settings_service import SettingsService

router = APIRouter(prefix="/experiences", tags=["Experiences"])


@router.get("/countries")
async def experience_countries(
    db: AsyncSession = Depends(get_db),
):
    """List of countries that have active, published vendor experiences."""
    repo = ExperienceRepository(db)
    countries = await repo.get_active_countries()
    return {"countries": countries}


@router.get("/nearby", response_model=ExperienceNearbyResponse)
async def nearby_experiences(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, max_length=60),
    country_code: Optional[str] = Query(None, max_length=2),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    """Vendor packages, nearest first, with optional country or category filter.

    Vendors are sparse, so this deliberately never returns an empty list just
    because the user is far from one. `has_nearby` tells the app whether to show
    the "showing the nearest" banner; `nearby_threshold_m` is echoed so that
    rule stays tunable server-side.
    """
    repo = ExperienceRepository(db)
    rows = await repo.get_nearest_packages(
        latitude=lat,
        longitude=lng,
        category=category,
        country_code=country_code,
        limit=limit,
        offset=offset,
    )
    total = await repo.count_published_packages(
        category=category, country_code=country_code
    )

    packages = [package_to_card(pkg, distance) for pkg, distance in rows]
    nearest = rows[0][1] if rows else None

    return ExperienceNearbyResponse(
        packages=packages,
        total=total,
        limit=limit,
        offset=offset,
        nearest_distance_m=nearest,
        has_nearby=is_nearby(nearest),
        nearby_threshold_m=NEARBY_THRESHOLD_M,
    )


@router.get("/packages/{package_id}", response_model=ExperiencePackageDetail)
async def get_experience_package(
    package_id: uuid.UUID,
    lat: Optional[float] = Query(None, ge=-90.0, le=90.0),
    lng: Optional[float] = Query(None, ge=-180.0, le=180.0),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    repo = ExperienceRepository(db)
    package = await repo.get_package(package_id)
    if not package:
        raise HTTPException(status_code=404, detail="Experience not found")

    distance = None
    if lat is not None and lng is not None:
        distance = await repo.distance_to(package, lat, lng)

    return package_to_detail(package, distance)


@router.get("/vendors/{vendor_id}", response_model=ExperienceVendorPublic)
async def get_experience_vendor(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    repo = ExperienceRepository(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor or not vendor.is_active:
        raise HTTPException(status_code=404, detail="Vendor not found")
    return vendor_to_public(vendor)


async def _dispatch_enquiry_email(enquiry_id: uuid.UUID) -> None:
    """Send the vendor notification on its own session.

    Runs after the response, so the request's session is already closed — this
    opens its own rather than reusing a dead one.
    """
    async with async_session() as db:
        enquiry = await db.get(ExperienceEnquiry, enquiry_id)
        if not enquiry:
            return

        recipients: list[str] = []
        if enquiry.vendor_id:
            repo = ExperienceRepository(db)
            vendor = await repo.get_vendor(enquiry.vendor_id)
            if vendor and vendor.contact_email:
                recipients.append(vendor.contact_email)

        # Copy the platform inbox so the client sees demand even for a vendor
        # who has not given an address yet.
        platform_email = await SettingsService(db).get_setting("contact_email")
        if platform_email and platform_email not in recipients:
            recipients.append(platform_email)

        for address in recipients:
            await send_vendor_enquiry_email(
                address,
                vendor_name=enquiry.vendor_name_snapshot or "your agency",
                package_title=enquiry.package_title_snapshot or "an experience",
                contact_name=enquiry.contact_name,
                contact_phone=enquiry.contact_phone,
                contact_email=enquiry.contact_email or "",
                preferred_date=(
                    enquiry.preferred_date.isoformat() if enquiry.preferred_date else ""
                ),
                party_size=str(enquiry.party_size) if enquiry.party_size else "",
                message=enquiry.message or "",
            )


@router.post(
    "/enquiries",
    response_model=ExperienceEnquiryResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_experience_enquiry(
    data: ExperienceEnquiryCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    repo = ExperienceRepository(db)
    package = await repo.get_package(data.package_id)
    if not package:
        raise HTTPException(status_code=404, detail="Experience not found")

    errors = validate_enquiry_payload(data.model_dump())
    if errors:
        raise HTTPException(status_code=400, detail=" ".join(errors))

    enquiry = ExperienceEnquiry(
        package_id=package.id,
        vendor_id=package.vendor_id,
        user_id=current_user.id if current_user else None,
        # Snapshots so the record survives the package being deleted — an
        # enquiry is evidence of demand the client shows vendors.
        package_title_snapshot=package.title,
        vendor_name_snapshot=package.vendor.name if package.vendor else None,
        contact_name=data.contact_name.strip(),
        contact_phone=data.contact_phone.strip(),
        contact_email=(data.contact_email or "").strip() or None,
        preferred_date=data.preferred_date,
        party_size=data.party_size,
        message=(data.message or "").strip() or None,
        status="new",
    )
    db.add(enquiry)
    activity = None
    if enquiry.vendor_id:
        await db.flush()  # the feed line links to the enquiry's id
        activity = partner_activity.enquiry_created(db, enquiry)
    await db.commit()
    await db.refresh(enquiry)

    # Queued before the email: tasks run in order, and a slow SMTP handshake
    # should not hold up the vendor's live portal alert.
    background_tasks.add_task(
        partner_events.publish,
        enquiry.vendor_id,
        partner_events.ENQUIRY_CREATED,
        {
            "id": enquiry.id,
            "package_title": enquiry.package_title_snapshot,
            "contact_name": enquiry.contact_name,
            "party_size": enquiry.party_size,
            "preferred_date": enquiry.preferred_date,
            "created_at": enquiry.created_at,
        },
    )
    background_tasks.add_task(partner_activity.announce, activity)
    background_tasks.add_task(_dispatch_enquiry_email, enquiry.id)

    return ExperienceEnquiryResponse(
        id=enquiry.id,
        status=enquiry.status,
        vendor_name=enquiry.vendor_name_snapshot,
        created_at=enquiry.created_at,
    )
