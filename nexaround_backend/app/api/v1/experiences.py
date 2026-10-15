"""App-facing Experiences endpoints: the vendor marketplace in Discovery."""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request, Response,
    status,
)
from fastapi.responses import StreamingResponse
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
    COUNTRY_MODE_KEY, NEARBY_THRESHOLD_M, booking_window_error, is_nearby,
    parse_country_mode, unavailable_error, validate_enquiry_payload,
)
from app.services.experience_upload import (
    VIDEO_MEDIA_TYPES, parse_range, video_file,
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
    """List of countries that have active, published vendor experiences.

    Also carries `country_mode`: the app fetches this before it has a location,
    and in country mode it needs none, so this is where it learns not to wait.
    """
    repo = ExperienceRepository(db)
    countries = await repo.get_active_countries()
    country_mode = parse_country_mode(
        await SettingsService(db).get_setting_fresh(COUNTRY_MODE_KEY, "")
    )
    return {"countries": countries, "country_mode": country_mode}


_VIDEO_CHUNK = 1024 * 1024


@router.get("/videos/{name}")
async def get_experience_video(name: str, request: Request):
    """A package video, with byte-range support.

    Its own route rather than the `/static` mount because that cannot answer
    `Range`, and iOS will not play (or seek in) a video without it. The name is
    matched against a strict pattern, so only our own uploads can be named. The
    file name is a random UUID that never changes content, hence the long cache.
    """
    path = video_file(name)
    if path is None:
        raise HTTPException(status_code=404, detail="Video not found")

    import os

    size = os.path.getsize(path)
    media_type = VIDEO_MEDIA_TYPES[os.path.splitext(name)[1]]
    headers = {
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=31536000, immutable",
    }
    try:
        byte_range = parse_range(request.headers.get("range"), size)
    except ValueError:
        return Response(
            status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE,
            headers={**headers, "Content-Range": f"bytes */{size}"},
        )

    start, end = byte_range if byte_range else (0, size - 1)

    def stream():
        with open(path, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                data = f.read(min(_VIDEO_CHUNK, left))
                if not data:
                    break
                left -= len(data)
                yield data

    headers["Content-Length"] = str(end - start + 1)
    if byte_range:
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    return StreamingResponse(
        stream(),
        status_code=206 if byte_range else 200,
        media_type=media_type,
        headers=headers,
    )


@router.get("/nearby", response_model=ExperienceNearbyResponse)
async def nearby_experiences(
    lat: Optional[float] = Query(None, ge=-90.0, le=90.0),
    lng: Optional[float] = Query(None, ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, max_length=60),
    country_code: Optional[str] = Query(None, max_length=2),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    """Vendor packages, by country or nearest first, depending on the switch.

    `experiences_country_mode` (Admin > Settings) is on by default: the list is
    filtered by `country_code` (every country when absent), ordered by the
    admin's vendor order, and carries no distances, so `lat`/`lng` are optional
    there. With it off, this is nearest first and they are required. Vendors
    are sparse, so that mode deliberately never returns an empty list just
    because the user is far from one: `has_nearby` tells the app whether to
    show the "showing the nearest" banner, and `nearby_threshold_m` is echoed
    so that rule stays
    tunable server-side.
    """
    repo = ExperienceRepository(db)
    country_mode = parse_country_mode(
        await SettingsService(db).get_setting_fresh(COUNTRY_MODE_KEY, "")
    )

    if country_mode:
        found = await repo.get_packages_by_country(
            category=category, country_code=country_code, limit=limit, offset=offset
        )
        total = await repo.count_published_packages(
            category=category, country_code=country_code
        )
        # `has_nearby` true keeps the app's "showing the nearest" banner away.
        return ExperienceNearbyResponse(
            packages=[package_to_card(pkg) for pkg in found],
            total=total,
            limit=limit,
            offset=offset,
            nearest_distance_m=None,
            has_nearby=True,
            nearby_threshold_m=NEARBY_THRESHOLD_M,
            country_mode=True,
        )

    if lat is None or lng is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="lat and lng are required for nearest-first experiences.",
        )

    rows = await repo.get_nearest_packages(
        latitude=lat,
        longitude=lng,
        category=category,
        country_code=country_code,
        limit=limit,
        offset=offset,
    )
    total = await repo.count_published_packages(
        category=category, country_code=country_code, located_only=True
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
                pickup_location=enquiry.pickup_location or "",
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
    # Checked here as well as by the app's calendar: an app from before the
    # package had a window offers a year ahead.
    date_error = booking_window_error(
        data.preferred_date,
        datetime.now(timezone.utc).date(),
        package.booking_window_days,
    )
    if date_error:
        errors.append(date_error)
    # The vendor's blocked dates. The app's calendar greys them out, but an app
    # from before they existed offers every day, so the server is the authority.
    blocked_error = unavailable_error(data.preferred_date, package.unavailable_ranges)
    if blocked_error:
        errors.append(blocked_error)
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
        pickup_location=(data.pickup_location or "").strip() or None,
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
