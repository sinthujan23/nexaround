"""Experiences marketplace: serialisation and the write-path cascade rules.

The cascade rules are the subtle part. Two columns on `experience_packages` are
derived from the vendor — `location` (copied down unless the package has its own
meeting point) and `is_published` (vendor active AND package active). Both exist
so the Discovery query can be a single-table partial index scan, and both go
stale silently if a write path forgets them: the card still renders, it is just
in the wrong place or visible when it should not be. `apply_vendor_cascade` is
the single place that keeps them honest.
"""

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.experience import ExperiencePackage, ExperienceReview, ExperienceVendor
from app.schemas.experience import (
    ExperiencePackageCard,
    ExperiencePackageDetail,
    ExperienceVendorPublic,
    MyReviewOut,
    ReviewPublic,
    ReviewSummary,
)
from app.services.experience_format import (
    DEFAULT_BOOKING_WINDOW_DAYS, format_duration, format_price, is_published,
    resolve_package_point, strip_markdown,
)
from app.services.ride_apps_service import COUNTRY_NAMES
from app.utils.geo_utils import get_lat_lng, point_or_none


def _cover(photo_urls: Optional[list]) -> Optional[str]:
    return photo_urls[0] if photo_urls else None


# (average, count) from published reviews, as the repository returns them.
RatingSummary = tuple[Optional[float], int]
NO_REVIEWS: RatingSummary = (None, 0)


def vendor_to_public(
    vendor: ExperienceVendor, rating: RatingSummary = NO_REVIEWS
) -> ExperienceVendorPublic:
    lat, lng = get_lat_lng(vendor.location)
    return ExperienceVendorPublic(
        id=vendor.id,
        name=vendor.name,
        description=vendor.description,
        address=vendor.address,
        latitude=lat,
        longitude=lng,
        contact_phone=vendor.contact_phone,
        contact_whatsapp=vendor.contact_whatsapp,
        contact_instagram=vendor.contact_instagram,
        contact_facebook=vendor.contact_facebook,
        contact_x=vendor.contact_x,
        website=vendor.website,
        logo_url=vendor.logo_url,
        photo_urls=vendor.photo_urls or [],
        # Travellers' real reviews. The hand-typed numbers on the vendor row are
        # not served any more: they could not be told from the real thing.
        rating=rating[0],
        review_count=rating[1],
    )


def review_to_public(review: ExperienceReview) -> ReviewPublic:
    return ReviewPublic(
        id=review.id,
        reviewer_name=review.reviewer_name,
        rating=review.rating,
        comment=review.comment,
        created_at=review.created_at,
        edited=review.edited_at is not None,
        vendor_reply=review.vendor_reply,
        vendor_replied_at=review.vendor_replied_at,
    )


def review_to_mine(review: ExperienceReview) -> MyReviewOut:
    return MyReviewOut(
        id=review.id,
        rating=review.rating,
        comment=review.comment,
        status=review.status,
        created_at=review.created_at,
        edited_at=review.edited_at,
        vendor_reply=review.vendor_reply if review.status == "published" else None,
        vendor_replied_at=review.vendor_replied_at if review.status == "published" else None,
    )


def review_summary_out(summary: dict) -> ReviewSummary:
    """`summarize()`'s dict as the API shape, five stars first."""
    breakdown = summary["breakdown"]
    return ReviewSummary(
        average=summary["average"],
        count=summary["count"],
        breakdown=[breakdown[star] for star in (5, 4, 3, 2, 1)],
    )


def package_to_card(
    package: ExperiencePackage,
    distance_m: Optional[float] = None,
    rating: RatingSummary = NO_REVIEWS,
) -> ExperiencePackageCard:
    lat, lng = get_lat_lng(package.location)
    amount = float(package.price_amount) if package.price_amount is not None else None
    usd = float(package.price_usd) if package.price_usd is not None else None
    vendor = package.vendor
    vendor_name = vendor.name if vendor else ""
    vendor_whatsapp = vendor.contact_whatsapp if vendor else None
    vendor_instagram = vendor.contact_instagram if vendor else None
    vendor_facebook = vendor.contact_facebook if vendor else None
    vendor_x = vendor.contact_x if vendor else None
    country_code = ((vendor.country_code if vendor else None) or "").strip().upper()
    if country_code == "94":  # legacy rows hold the dial code, as in the country list
        country_code = "LK"

    return ExperiencePackageCard(
        id=package.id,
        title=package.title,
        summary=package.summary,
        category=package.category,
        vendor_id=package.vendor_id,
        vendor_name=vendor_name,
        vendor_whatsapp=vendor_whatsapp,
        vendor_instagram=vendor_instagram,
        vendor_facebook=vendor_facebook,
        vendor_x=vendor_x,
        cover_photo_url=_cover(package.photo_urls),
        photo_count=len(package.photo_urls or []),
        price_amount=amount,
        price_currency=package.price_currency or "USD",
        price_basis=package.price_basis or "per_person",
        # Rendered server-side so the app, the admin panel and any future
        # surface cannot disagree about how a price reads.
        price_label=format_price(
            amount,
            package.price_currency or "USD",
            package.price_basis or "per_person",
            package.max_participants,
            usd,
        ),
        max_participants=package.max_participants,
        duration_minutes=package.duration_minutes,
        duration_label=format_duration(package.duration_minutes),
        latitude=lat,
        longitude=lng,
        distance_m=distance_m,
        tags=package.tags or [],
        region_label=package.region_label,
        country_code=country_code or None,
        country_name=COUNTRY_NAMES.get(country_code) if country_code else None,
        rating_avg=rating[0],
        rating_count=rating[1],
    )


def package_to_detail(
    package: ExperiencePackage,
    distance_m: Optional[float] = None,
    rating: RatingSummary = NO_REVIEWS,
    vendor_rating: RatingSummary = NO_REVIEWS,
) -> ExperiencePackageDetail:
    card = package_to_card(package, distance_m, rating)
    return ExperiencePackageDetail(
        **card.model_dump(),
        description=strip_markdown(package.description),
        description_md=package.description,
        photo_urls=package.photo_urls or [],
        video_urls=package.video_urls or [],
        unavailable_ranges=package.unavailable_ranges or [],
        booking_window_days=package.booking_window_days or DEFAULT_BOOKING_WINDOW_DAYS,
        inclusions=package.inclusions or [],
        languages=package.languages or [],
        meeting_point_address=package.meeting_point_address,
        vendor=vendor_to_public(package.vendor, vendor_rating),
    )


def apply_package_derived_fields(
    package: ExperiencePackage,
    vendor: ExperienceVendor,
    override_lat: Optional[float] = None,
    override_lng: Optional[float] = None,
) -> None:
    """Set a package's derived `location` and `is_published` from its vendor."""
    vendor_lat, vendor_lng = get_lat_lng(vendor.location)
    lat, lng = resolve_package_point(
        vendor_lat, vendor_lng, package.uses_vendor_location, override_lat, override_lng
    )
    package.location = point_or_none(lat, lng)
    package.is_published = is_published(vendor.is_active, package.is_active)


async def apply_vendor_cascade(db: AsyncSession, vendor: ExperienceVendor) -> int:
    """Re-derive every package of a vendor after the vendor changes.

    Called on any vendor save. A vendor that moves drags along every package
    still following it; a vendor that is deactivated hides all of them.
    """
    rows = (
        await db.execute(
            select(ExperiencePackage).where(ExperiencePackage.vendor_id == vendor.id)
        )
    ).scalars().all()

    vendor_lat, vendor_lng = get_lat_lng(vendor.location)
    for package in rows:
        if package.uses_vendor_location:
            package.location = point_or_none(vendor_lat, vendor_lng)
        package.is_published = is_published(vendor.is_active, package.is_active)
    return len(rows)
