"""App-facing Experiences endpoints: the vendor marketplace in Discovery."""

import uuid
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import (
    APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request, Response,
    status,
)
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user, get_current_user_optional
from app.core.database import async_session, get_db
from app.core.rate_limiter import RateLimiter, get_client_ip, get_redis_client
from app.models.experience import (
    ExperienceEnquiry, ExperiencePackage, ExperienceReview, ExperienceVendor,
    ProviderApplication,
)
from app.models.user import User
from app.repositories.experience_repository import ExperienceRepository
from app.schemas.experience import (
    ExperienceEnquiryCreate,
    ExperienceEnquiryResponse,
    ExperienceNearbyResponse,
    ExperiencePackageDetail,
    ExperienceVendorPublic,
    MyEnquiryCancel, MyEnquiryOfferAnswer,
    MyEnquiryListResponse,
    MyEnquiryOut,
    MyReviewOut,
    ProviderApplicationCreate,
    ProviderApplicationCreated,
    ReviewCreate,
    ReviewListResponse,
)
from app.services.email_service import send_new_enquiry_email
from app.services.experience_format import (
    COUNTRY_MODE_KEY, NEARBY_THRESHOLD_M, booking_window_error, is_nearby,
    parse_country_mode, pick_price_option, too_many_guests, unavailable_error,
    validate_enquiry_payload,
)
from app.services.experience_upload import (
    VIDEO_MEDIA_TYPES, parse_range, video_file,
)
from app.services.experience_service import (
    NO_REVIEWS, package_to_card, package_to_detail, review_summary_out,
    review_to_mine, review_to_public, vendor_to_public,
)
from app.services import experience_reviews, image_preview
from app.services import (
    audit, enquiry_lifecycle, enquiry_notifications, legal_service,
    fx_service, partner_activity, partner_events,
)
from app.services.currencies import PRICE_CURRENCIES
from app.services.settings_service import SettingsService

router = APIRouter(prefix="/experiences", tags=["Experiences"])


async def _public_repo(db: AsyncSession) -> ExperienceRepository:
    """The repository for app-facing reads: vendors who have not accepted the
    Provider Agreement in time are left out of everything."""
    return ExperienceRepository(
        db, hidden_vendor_ids=await legal_service.hidden_vendor_ids(db)
    )


@router.get("/countries")
async def experience_countries(
    db: AsyncSession = Depends(get_db),
):
    """List of countries that have active, published vendor experiences.

    Also carries `country_mode`: the app fetches this before it has a location,
    and in country mode it needs none, so this is where it learns not to wait.
    """
    repo = await _public_repo(db)
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


async def _shown_currency(db: AsyncSession, currency: Optional[str]) -> tuple[Optional[str], dict]:
    """The traveller's picked currency, if it is one we price in, and today's
    rates. Nothing to do for none or an unknown code."""
    code = (currency or "").strip().upper()
    if code not in PRICE_CURRENCIES:
        return None, {}
    return code, await fx_service.usd_rates(db)


@router.get("/nearby", response_model=ExperienceNearbyResponse)
async def nearby_experiences(
    lat: Optional[float] = Query(None, ge=-90.0, le=90.0),
    lng: Optional[float] = Query(None, ge=-180.0, le=180.0),
    category: Optional[str] = Query(None, max_length=60),
    country_code: Optional[str] = Query(None, max_length=2),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    currency: Optional[str] = Query(None, max_length=3),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    """Vendor packages, by country or nearest first, depending on the switch.

    `currency`: the one the traveller picked in the app; every card then also
    carries its price in it (`display_label`). Display only.

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
    repo = await _public_repo(db)
    shown, per_usd = await _shown_currency(db, currency)
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
        ratings = await repo.rating_summaries([pkg.id for pkg in found])
        # `has_nearby` true keeps the app's "showing the nearest" banner away.
        return ExperienceNearbyResponse(
            packages=[
                package_to_card(
                    pkg, rating=ratings.get(pkg.id, NO_REVIEWS), shown=shown, per_usd=per_usd,
                )
                for pkg in found
            ],
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

    ratings = await repo.rating_summaries([pkg.id for pkg, _ in rows])
    packages = [
        package_to_card(pkg, distance, ratings.get(pkg.id, NO_REVIEWS), shown, per_usd)
        for pkg, distance in rows
    ]
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
    currency: Optional[str] = Query(None, max_length=3),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    repo = await _public_repo(db)
    shown, per_usd = await _shown_currency(db, currency)
    package = await repo.get_package(package_id)
    if not package:
        raise HTTPException(status_code=404, detail="Experience not found")

    distance = None
    if lat is not None and lng is not None:
        distance = await repo.distance_to(package, lat, lng)

    rating = (await repo.rating_summaries([package.id])).get(package.id, NO_REVIEWS)
    vendor_rating = (
        await repo.vendor_rating_summaries([package.vendor_id])
    ).get(package.vendor_id, NO_REVIEWS)
    detail = package_to_detail(package, distance, rating, vendor_rating, shown, per_usd)
    # The gallery shows each photo's colours, blurred, while it loads.
    detail.image_previews = await image_preview.previews_for(detail.photo_urls)
    return detail


@router.get("/packages/{package_id}/reviews", response_model=ReviewListResponse)
async def list_package_reviews(
    package_id: uuid.UUID,
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    """A package's published reviews, newest first, with its average and the
    five-to-one breakdown. Open to everyone, like the package itself."""
    repo = await _public_repo(db)
    package = await repo.get_package(package_id)
    if not package:
        raise HTTPException(status_code=404, detail="Experience not found")
    summary = await repo.package_review_summary(package_id)
    reviews = await repo.list_package_reviews(package_id, limit, offset)
    return ReviewListResponse(
        summary=review_summary_out(summary),
        reviews=[review_to_public(r) for r in reviews],
        total=summary["count"],
        limit=limit,
        offset=offset,
    )


@router.get("/vendors/{vendor_id}", response_model=ExperienceVendorPublic)
async def get_experience_vendor(
    vendor_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _user: Optional[User] = Depends(get_current_user_optional),
):
    repo = await _public_repo(db)
    vendor = await repo.get_vendor(vendor_id)
    if not vendor or not vendor.is_active or vendor.id in repo.hidden_vendor_ids:
        raise HTTPException(status_code=404, detail="Vendor not found")
    rating = (await repo.vendor_rating_summaries([vendor.id])).get(vendor.id, NO_REVIEWS)
    return vendor_to_public(vendor, rating)


async def _dispatch_enquiry_email(enquiry_id: uuid.UUID) -> None:
    """Email the new enquiry to the platform inbox, on its own session.

    Only to Nexaround, never to the vendor: the team contacts the traveller
    and the vendor itself, so a booking cannot be arranged around the
    platform's commission.

    Runs after the response, so the request's session is already closed — this
    opens its own rather than reusing a dead one.
    """
    async with async_session() as db:
        enquiry = await db.get(ExperienceEnquiry, enquiry_id)
        if not enquiry:
            return

        platform_email = await SettingsService(db).get_setting("contact_email")
        if platform_email:
            await send_new_enquiry_email(
                platform_email,
                vendor_name=enquiry.vendor_name_snapshot or "a vendor",
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
                price=(enquiry.price_option or {}).get("label", ""),
            )


@router.post(
    "/enquiries",
    response_model=ExperienceEnquiryResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_experience_enquiry(
    data: ExperienceEnquiryCreate,
    background_tasks: BackgroundTasks,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    repo = await _public_repo(db)
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
    # The price chosen, and the guests it allows ("at least 3" for a
    # per-person price). Copied onto the request as it reads now.
    price_option, option_error = pick_price_option(
        package.price_options, data.price_option_id, data.party_size,
        package.price_currency or "USD", package.max_participants,
    )
    if option_error:
        errors.append(option_error)
    # The package's own maximum (the boat's seats), price or not.
    elif guests_error := too_many_guests(data.party_size, package.max_participants):
        errors.append(guests_error)
    if errors:
        raise HTTPException(status_code=400, detail=" ".join(errors))

    # The Experience Booking Terms. The app sends the version the traveller
    # ticked; anything else is refused, except from an app too old to show
    # them, which is let through (unrecorded) for legal_service's grace period.
    now = datetime.now(timezone.utc)
    terms = await legal_service.get_current(db, legal_service.CUSTOMER)
    terms_error = legal_service.customer_terms_error(
        data.accepted_terms_version,
        terms.version,
        await legal_service.first_published_at(db, legal_service.CUSTOMER),
        now,
    )
    if terms_error:
        raise HTTPException(status_code=terms_error[0], detail=terms_error[1])
    accepted_terms = data.accepted_terms_version is not None

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
        price_option=price_option,
        status="new",
        terms_version=terms.version if accepted_terms else None,
        terms_accepted_at=now if accepted_terms else None,
    )
    db.add(enquiry)
    await db.flush()  # the feed line and the acceptance link to the enquiry's id
    if accepted_terms and current_user and not await legal_service.user_has_accepted(
        db, current_user.id, terms.version
    ):
        # Once per version per account; the enquiry row itself already proves
        # the version for this request, signed in or not.
        legal_service.record_acceptance(
            db,
            kind=legal_service.CUSTOMER,
            version=terms.version,
            method="app",
            meta=audit.client_meta(request),
            accepted_at=now,
            user_id=current_user.id,
            enquiry_id=enquiry.id,
            party_label=enquiry.contact_name,
        )
    # The vendor's bell (web portal and app) says a request came in, never
    # who sent it: see partner_activity.request_text.
    activity = partner_activity.request_received(db, enquiry)
    await db.commit()
    await db.refresh(enquiry)

    # The details go to Nexaround only (email to the inbox); the vendor gets
    # the feed line, a push and an email with the same facts, and answers in
    # the portal's Requests.
    background_tasks.add_task(_dispatch_enquiry_email, enquiry.id)
    background_tasks.add_task(partner_activity.announce, activity)
    background_tasks.add_task(
        partner_events.publish, enquiry.vendor_id, partner_events.REQUESTS_CHANGED,
    )
    background_tasks.add_task(enquiry_notifications.vendor_request_alert, enquiry.id)
    # The traveller's copy: what they asked for and the terms they accepted.
    background_tasks.add_task(enquiry_notifications.request_received, enquiry.id)

    return ExperienceEnquiryResponse(
        id=enquiry.id,
        status=enquiry.status,
        vendor_name=enquiry.vendor_name_snapshot,
        created_at=enquiry.created_at,
    )


# ── My requests: the traveller's own enquiries ──────────────────────────────


def _my_enquiry_out(
    enquiry: ExperienceEnquiry,
    package: Optional[ExperiencePackage],
    vendor: Optional[ExperienceVendor],
    review=None,
) -> MyEnquiryOut:
    """Snapshots first: the package or vendor may have been deleted since."""
    return MyEnquiryOut(
        id=enquiry.id,
        package_id=enquiry.package_id,
        package_title=enquiry.package_title_snapshot or (package.title if package else "Experience"),
        vendor_name=enquiry.vendor_name_snapshot or (vendor.name if vendor else None),
        cover_photo_url=(package.photo_urls or [None])[0] if package else None,
        vendor_phone=vendor.contact_phone if vendor else None,
        vendor_whatsapp=vendor.contact_whatsapp if vendor else None,
        preferred_date=enquiry.preferred_date,
        party_size=enquiry.party_size,
        pickup_location=enquiry.pickup_location,
        message=enquiry.message,
        status=enquiry.status,
        created_at=enquiry.created_at,
        confirmed_date=enquiry.confirmed_date,
        confirmed_at=enquiry.confirmed_at,
        cancelled_at=enquiry.cancelled_at,
        cancellation_reason=enquiry.cancellation_reason,
        late_cancellation=enquiry.late_cancellation,
        free_cancellation_last_day=enquiry.free_cancellation_last_day,
        can_cancel=enquiry_lifecycle.customer_cancel_error(enquiry.status) is None,
        offered_date=enquiry_lifecycle.pending_offer(enquiry),
        offer_reason=(
            enquiry_lifecycle.DECLINE_REASONS.get(enquiry.vendor_response_reason or "")
            if enquiry_lifecycle.pending_offer(enquiry) else None
        ),
        # Offered only while the package still exists to be reviewed, and not
        # on a request that was cancelled.
        can_review=(
            enquiry.package_id is not None
            and enquiry.status not in enquiry_lifecycle.CANCELLED
        ),
        review=review_to_mine(review) if review is not None else None,
    )


async def _my_enquiries_out(
    db: AsyncSession, enquiries: list[ExperienceEnquiry]
) -> list[MyEnquiryOut]:
    """Two lookups for the whole page, not two per request."""
    from sqlalchemy import select

    package_ids = {e.package_id for e in enquiries if e.package_id}
    vendor_ids = {e.vendor_id for e in enquiries if e.vendor_id}
    # Every caller passes one traveller's own requests.
    user_id = next((e.user_id for e in enquiries if e.user_id), None)
    packages = {
        p.id: p for p in (await db.execute(
            select(ExperiencePackage).where(ExperiencePackage.id.in_(package_ids))
        )).scalars().all()
    } if package_ids else {}
    vendors = {
        v.id: v for v in (await db.execute(
            select(ExperienceVendor).where(ExperienceVendor.id.in_(vendor_ids))
        )).scalars().all()
    } if vendor_ids else {}
    reviews = await ExperienceRepository(db).reviews_by_user(
        user_id, list(package_ids)
    ) if user_id else {}
    return [
        _my_enquiry_out(
            e, packages.get(e.package_id), vendors.get(e.vendor_id),
            reviews.get(e.package_id),
        )
        for e in enquiries
    ]


@router.get("/enquiries/mine", response_model=MyEnquiryListResponse)
async def my_enquiries(
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The signed-in traveller's requests, newest first."""
    from sqlalchemy import select

    rows = (await db.execute(
        select(ExperienceEnquiry)
        .where(ExperienceEnquiry.user_id == current_user.id)
        .order_by(ExperienceEnquiry.created_at.desc())
        .limit(limit)
    )).scalars().all()
    return MyEnquiryListResponse(enquiries=await _my_enquiries_out(db, list(rows)))


@router.post("/enquiries/{enquiry_id}/offer", response_model=MyEnquiryOut)
async def answer_offered_date(
    enquiry_id: uuid.UUID,
    data: MyEnquiryOfferAnswer,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The traveller accepts or declines the date the provider offered.

    Accepting confirms the booking for that date; declining cancels the
    request. The provider and NexAround hear either way.
    """
    from sqlalchemy import select

    # Scoped in the query: another traveller's request is simply not found.
    enquiry = (await db.execute(
        select(ExperienceEnquiry).where(
            ExperienceEnquiry.id == enquiry_id,
            ExperienceEnquiry.user_id == current_user.id,
        )
    )).scalar_one_or_none()
    if enquiry is None:
        raise HTTPException(status_code=404, detail="Request not found")
    now = datetime.now(timezone.utc)
    error = enquiry_lifecycle.offer_response_error(enquiry, now.date())
    if error:
        raise HTTPException(status_code=409, detail=error)

    event = enquiry_lifecycle.respond_to_offer(enquiry, data.accept, now=now)
    # The vendor hears it too: package, date and guests, never who.
    activity = partner_activity.request_updated(
        db, enquiry, event, actor=partner_activity.TRAVELLER,
    ) if event else None
    await db.commit()
    await db.refresh(enquiry)

    if event == enquiry_lifecycle.CONFIRMED:
        # The traveller's confirmation, with the date and the cancellation rule.
        background_tasks.add_task(enquiry_notifications.booking_update, enquiry.id, event)
    background_tasks.add_task(enquiry_notifications.offer_answered, enquiry.id)
    if activity:
        background_tasks.add_task(partner_activity.announce, activity)
        background_tasks.add_task(
            partner_events.publish, enquiry.vendor_id, partner_events.REQUESTS_CHANGED,
        )
        background_tasks.add_task(enquiry_notifications.vendor_update_alert, enquiry.id, event)

    return (await _my_enquiries_out(db, [enquiry]))[0]


@router.post("/enquiries/{enquiry_id}/cancel", response_model=MyEnquiryOut)
async def cancel_my_enquiry(
    enquiry_id: uuid.UUID,
    data: MyEnquiryCancel,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The traveller cancels. Stamped with the server's time, which is what the
    72-hour rule is judged on, and the platform inbox is told at once."""
    from sqlalchemy import select

    # Scoped in the query: another traveller's request is simply not found.
    enquiry = (await db.execute(
        select(ExperienceEnquiry).where(
            ExperienceEnquiry.id == enquiry_id,
            ExperienceEnquiry.user_id == current_user.id,
        )
    )).scalar_one_or_none()
    if enquiry is None:
        raise HTTPException(status_code=404, detail="Request not found")

    error = enquiry_lifecycle.customer_cancel_error(enquiry.status)
    if error:
        raise HTTPException(status_code=409, detail=error)

    event = enquiry_lifecycle.apply_status(
        enquiry, enquiry_lifecycle.CUSTOMER_CANCELLED,
        now=datetime.now(timezone.utc), reason=data.reason,
    )
    # The vendor hears it too: package, date and guests, never who.
    activity = partner_activity.request_updated(
        db, enquiry, event, actor=partner_activity.TRAVELLER,
    ) if event else None
    await db.commit()
    await db.refresh(enquiry)

    background_tasks.add_task(enquiry_notifications.customer_cancelled, enquiry.id)
    if activity:
        background_tasks.add_task(partner_activity.announce, activity)
        background_tasks.add_task(
            partner_events.publish, enquiry.vendor_id, partner_events.REQUESTS_CHANGED,
        )
        background_tasks.add_task(enquiry_notifications.vendor_update_alert, enquiry.id, event)

    return (await _my_enquiries_out(db, [enquiry]))[0]


@router.get("/packages/{package_id}/review/mine", response_model=Optional[MyReviewOut])
async def my_package_review(
    package_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The signed-in traveller's own review of this package, or null."""
    review = await ExperienceRepository(db).get_user_review(current_user.id, package_id)
    return review_to_mine(review) if review is not None else None


@router.put("/packages/{package_id}/review", response_model=MyReviewOut)
async def review_package(
    package_id: uuid.UUID,
    data: ReviewCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Rate a package, or change the rating already given.

    Open to every signed-in traveller, once per package: a second send edits
    the first. Published at once; an admin can hide it, and the provider can
    reply to it.
    """
    from sqlalchemy.exc import IntegrityError

    # The same view a traveller has of the package: an unpublished package, or
    # one whose provider is hidden, cannot be reviewed.
    public = await _public_repo(db)
    package = await public.get_package(package_id)
    if package is None:
        raise HTTPException(status_code=404, detail="Experience not found")

    repo = ExperienceRepository(db)
    now = datetime.now(timezone.utc)
    comment = experience_reviews.clean_comment(data.comment)
    review = await repo.get_user_review(current_user.id, package.id)
    activity = None
    if review is not None:
        if review.rating != data.rating or review.comment != comment:
            review.rating = data.rating
            review.comment = comment
            review.edited_at = now
    else:
        review = ExperienceReview(
            id=uuid.uuid4(),
            package_id=package.id,
            vendor_id=package.vendor_id,
            user_id=current_user.id,
            reviewer_name=experience_reviews.reviewer_display_name(current_user.display_name),
            rating=data.rating,
            comment=comment,
            status=experience_reviews.PUBLISHED,
            created_at=now,
        )
        db.add(review)
        activity = partner_activity.review_received(db, review, package)
    try:
        await db.commit()
    except IntegrityError:
        # A second tap that raced the first: the package already has the review.
        await db.rollback()
        raise HTTPException(status_code=409, detail="You have already reviewed this experience.")
    await db.refresh(review)

    background_tasks.add_task(partner_activity.announce, activity)
    return review_to_mine(review)


@router.delete("/packages/{package_id}/review", status_code=status.HTTP_204_NO_CONTENT)
async def delete_package_review(
    package_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete the signed-in traveller's own review of this package."""
    repo = ExperienceRepository(db)
    review = await repo.get_user_review(current_user.id, package_id)
    if review is None:
        raise HTTPException(status_code=404, detail="Review not found")
    await db.delete(review)
    await db.commit()
    return None


# ── "List your experience": businesses asking to join ───────────────────────

# Anyone may send one, signed in or not; a script must not flood the inbox.
_application_limiter = RateLimiter(requests_per_minute=3, window_seconds=600)


async def _too_many_applications(ip: str) -> bool:
    key = f"rate_limit:provider_application:ip:{ip}"
    try:
        return await _application_limiter._check_rate_limit(key, await get_redis_client())
    except Exception:
        return await _application_limiter._check_rate_limit(key, None)


async def _email_application(application_id: uuid.UUID) -> None:
    """Tell the platform inbox, on its own session. Never raises."""
    from app.services import email_service
    from app.services.ride_apps_service import COUNTRY_NAMES

    try:
        async with async_session() as db:
            app_row = await db.get(ProviderApplication, application_id)
            inbox = await SettingsService(db).get_setting("contact_email")
            if not app_row or not inbox:
                return
            place = ", ".join(
                p for p in (app_row.city, COUNTRY_NAMES.get(app_row.country_code, app_row.country_code)) if p
            )
            await email_service.send_experience_update_email(
                inbox,
                subject=f"New provider application: {app_row.business_name}",
                heading="A business wants to list its experiences",
                intro="Sent from the app's List your experience form. "
                      "Review it in Admin > Provider applications.",
                rows=(
                    ("Business", app_row.business_name),
                    ("Contact", app_row.contact_name),
                    ("Phone", app_row.contact_phone),
                    ("Email", app_row.contact_email),
                    ("Location", place),
                    ("Offers", app_row.offering),
                    ("Links", app_row.links),
                ),
            )
    except Exception:
        import logging
        logging.getLogger(__name__).exception("provider application email failed for %s", application_id)


@router.post(
    "/provider-applications",
    response_model=ProviderApplicationCreated,
    status_code=status.HTTP_201_CREATED,
)
async def create_provider_application(
    data: ProviderApplicationCreate,
    background_tasks: BackgroundTasks,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """The app's "List your experience" form. Stored for Admin > Provider
    applications and emailed to the platform inbox; nothing is published."""
    from app.services.ride_apps_service import COUNTRY_NAMES

    if await _too_many_applications(get_client_ip(request)):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many applications from here. Please try again later.",
        )
    if data.country_code not in COUNTRY_NAMES:
        raise HTTPException(status_code=400, detail="Please choose your country.")

    row = ProviderApplication(
        user_id=current_user.id if current_user else None,
        business_name=data.business_name.strip(),
        contact_name=data.contact_name.strip(),
        contact_phone=data.contact_phone,
        contact_email=data.contact_email,
        country_code=data.country_code,
        city=(data.city or "").strip() or None,
        offering=data.offering.strip(),
        links=(data.links or "").strip() or None,
        status="new",
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    background_tasks.add_task(_email_application, row.id)
    return ProviderApplicationCreated(id=row.id, status=row.status)
