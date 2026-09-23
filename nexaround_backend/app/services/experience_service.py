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

from app.models.experience import ExperiencePackage, ExperienceVendor
from app.schemas.experience import (
    ExperiencePackageCard,
    ExperiencePackageDetail,
    ExperienceVendorPublic,
)
from app.services.experience_format import (
    format_duration, format_price, is_published, resolve_package_point,
)
from app.utils.geo_utils import create_point, get_lat_lng


def _cover(photo_urls: Optional[list]) -> Optional[str]:
    return photo_urls[0] if photo_urls else None


def vendor_to_public(vendor: ExperienceVendor) -> ExperienceVendorPublic:
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
        rating=float(vendor.rating) if vendor.rating is not None else None,
        review_count=vendor.review_count or 0,
    )


def package_to_card(
    package: ExperiencePackage, distance_m: Optional[float] = None
) -> ExperiencePackageCard:
    lat, lng = get_lat_lng(package.location)
    amount = float(package.price_amount) if package.price_amount is not None else None
    vendor = package.vendor
    vendor_name = vendor.name if vendor else ""
    vendor_whatsapp = vendor.contact_whatsapp if vendor else None
    vendor_instagram = vendor.contact_instagram if vendor else None
    vendor_facebook = vendor.contact_facebook if vendor else None
    vendor_x = vendor.contact_x if vendor else None

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
            amount, package.price_currency or "USD", package.price_basis or "per_person"
        ),
        duration_minutes=package.duration_minutes,
        duration_label=format_duration(package.duration_minutes),
        latitude=lat,
        longitude=lng,
        distance_m=distance_m,
        tags=package.tags or [],
    )


def package_to_detail(
    package: ExperiencePackage, distance_m: Optional[float] = None
) -> ExperiencePackageDetail:
    card = package_to_card(package, distance_m)
    return ExperiencePackageDetail(
        **card.model_dump(),
        description=package.description,
        photo_urls=package.photo_urls or [],
        max_participants=package.max_participants,
        inclusions=package.inclusions or [],
        languages=package.languages or [],
        meeting_point_address=package.meeting_point_address,
        vendor=vendor_to_public(package.vendor),
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
    package.location = create_point(lat, lng)
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
            package.location = create_point(vendor_lat, vendor_lng)
        package.is_published = is_published(vendor.is_active, package.is_active)
    return len(rows)
