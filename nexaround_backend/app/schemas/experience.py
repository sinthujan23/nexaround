"""Schemas for the Experiences marketplace.

House conventions: Pydantic v2, `from_attributes`, XBase/XCreate/XResponse
naming, no global `{data: ...}` envelope — bare objects or a named-key wrapper.

One rule worth stating loudly: **the vendor's email address is never serialised
to the app.** It is the destination for enquiry notifications and nothing more;
the phone and WhatsApp numbers are the public contact channels.
"""

import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from app.services.experience_format import (
    MAX_BOOKING_WINDOW_DAYS, MAX_PRICE_OPTIONS, MAX_UNAVAILABLE_RANGES,
    NEARBY_THRESHOLD_M, PRICE_BASES,
)
from app.services.currencies import check_price_currency
from app.services.experience_upload import MAX_VIDEOS_PER_PACKAGE


class PriceOptionBase(BaseModel):
    """One price a package is sold at. A blank min is 1 and a blank max is the
    package's Max participants."""

    # Kept from the package's options; a missing or unknown one gets a new id.
    id: Optional[str] = Field(None, max_length=16)
    amount: float = Field(..., ge=0)
    basis: str = "per_person"
    min_people: Optional[int] = Field(None, ge=1, le=100)
    max_people: Optional[int] = Field(None, ge=1, le=100)

    @field_validator("basis")
    @classmethod
    def _known_basis(cls, value):
        if value not in PRICE_BASES:
            raise ValueError(f"basis must be one of {', '.join(PRICE_BASES)}")
        return value

    @model_validator(mode="after")
    def _min_not_above_max(self):
        if self.min_people and self.max_people and self.min_people > self.max_people:
            raise ValueError("Min people cannot be more than max people.")
        return self


class PriceOption(PriceOptionBase):
    """The admin's view: the dollar price is typed here, never converted."""

    usd: Optional[float] = Field(None, ge=0)


class PriceOptionOut(BaseModel):
    """A price as the app shows and books it."""

    id: str
    # "LKR 8,000 ($24) / person (min 3)", made like `price_label`.
    label: str
    basis: str
    # The guests the option allows, blanks already filled in.
    min_people: int = 1
    max_people: Optional[int] = None


class DateRange(BaseModel):
    """Inclusive: a single day is a range whose start and end are the same."""

    start: date
    end: date

    @model_validator(mode="after")
    def _ordered(self):
        if self.end < self.start:
            raise ValueError("A date range cannot end before it starts.")
        return self


# --- App-facing -------------------------------------------------------------

class ExperienceVendorPublic(BaseModel):
    """The vendor as the app sees it. Note the absence of `contact_email`."""

    id: uuid.UUID
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    # None when the vendor is listed by country only. The app reads a missing
    # coordinate as 0.0 and falls back to the address.
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    contact_phone: Optional[str] = None
    contact_whatsapp: Optional[str] = None
    contact_instagram: Optional[str] = None
    contact_facebook: Optional[str] = None
    contact_x: Optional[str] = None
    website: Optional[str] = None
    logo_url: Optional[str] = None
    photo_urls: list[str] = []
    rating: Optional[float] = None
    review_count: int = 0


class ExperiencePackageCard(BaseModel):
    """The Discovery card unit — one per package, vendor name as subtitle."""

    id: uuid.UUID
    title: str
    summary: Optional[str] = None
    category: Optional[str] = None
    vendor_id: uuid.UUID
    vendor_name: str
    vendor_whatsapp: Optional[str] = None
    vendor_instagram: Optional[str] = None
    vendor_facebook: Optional[str] = None
    vendor_x: Optional[str] = None
    cover_photo_url: Optional[str] = None
    photo_count: int = 0
    price_amount: Optional[float] = None
    price_currency: str = "USD"
    price_basis: str = "per_person"
    # Carries the admin's typed dollar price in brackets: "QAR 499 ($137)".
    price_label: str = ""
    duration_minutes: Optional[int] = None
    duration_label: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    distance_m: Optional[float] = None
    tags: list[str] = []
    # From travellers' published reviews; None with no review yet.
    rating_avg: Optional[float] = None
    rating_count: int = 0
    # Group size; a group price also shows it in `price_label` ("(max 4)").
    max_participants: Optional[int] = None
    # Every price, first one first; `price_label` is the first. Empty when the
    # price is on request.
    price_options: list[PriceOptionOut] = []
    # Admin's free-text region, e.g. "Kerala State · Munnar region".
    region_label: Optional[str] = None
    # The vendor's country, ISO 3166-1 alpha-2 and its English name. The app
    # shows it on cards in the "All countries" list.
    country_code: Optional[str] = None
    country_name: Optional[str] = None


class ExperiencePackageDetail(ExperiencePackageCard):
    # Plain text: the formatting symbols stripped, for app versions that cannot
    # show formatting. `description_md` is the formatted text itself.
    description: Optional[str] = None
    description_md: Optional[str] = None
    photo_urls: list[str] = []
    # Relative API paths; the app prefixes the API origin, as for photos.
    video_urls: list[str] = []
    # Days the package cannot be booked; everything else is available.
    unavailable_ranges: list[DateRange] = []
    max_participants: Optional[int] = None
    # How many days ahead the app's calendar lets a traveller pick a date.
    # Always set: a package without its own window gets the platform default.
    booking_window_days: int
    inclusions: list[str] = []
    languages: list[str] = []
    meeting_point_address: Optional[str] = None
    vendor: ExperienceVendorPublic


class ExperienceNearbyResponse(BaseModel):
    packages: list[ExperiencePackageCard]
    total: int
    limit: int = 20
    offset: int = 0
    nearest_distance_m: Optional[float] = None
    has_nearby: bool = False
    nearby_threshold_m: int = NEARBY_THRESHOLD_M
    # Admin > Settings > "Browse by country". The app swaps "Near me" for "All
    # countries" when it is on, so it must learn the mode from the server.
    country_mode: bool = False


class ExperienceEnquiryCreate(BaseModel):
    package_id: uuid.UUID
    contact_name: str = Field(..., min_length=2, max_length=120)
    contact_phone: str = Field(..., min_length=6, max_length=32)
    contact_email: Optional[str] = Field(None, max_length=255)
    preferred_date: Optional[date] = None
    party_size: Optional[int] = Field(None, ge=1, le=100)
    pickup_location: Optional[str] = Field(None, max_length=500)
    message: Optional[str] = Field(None, max_length=2000)
    # The price option chosen. Absent from apps before price options, which
    # showed only the first one; that is the one recorded.
    price_option_id: Optional[str] = Field(None, max_length=16)
    # The Experience Booking Terms version the traveller ticked. Absent only
    # from apps older than the terms (see legal_service.customer_terms_error).
    accepted_terms_version: Optional[int] = Field(None, ge=1)


class ExperienceEnquiryResponse(BaseModel):
    id: uuid.UUID
    status: str
    vendor_name: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


# --- Admin ------------------------------------------------------------------

class ExperienceVendorBase(BaseModel):
    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    # Both or neither; the country is always required. With no pin it is what
    # the vendor is found by (checked in the endpoints with `vendor_place_problem`).
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    address: Optional[str] = Field(None, max_length=500)
    google_place_id: Optional[str] = Field(None, max_length=255)
    city: Optional[str] = Field(None, max_length=120)
    country_code: Optional[str] = Field(None, max_length=2)
    contact_phone: Optional[str] = Field(None, max_length=32)
    contact_whatsapp: Optional[str] = Field(None, max_length=32)
    contact_instagram: Optional[str] = Field(None, max_length=255)
    contact_facebook: Optional[str] = Field(None, max_length=500)
    contact_x: Optional[str] = Field(None, max_length=255)
    contact_email: Optional[str] = Field(None, max_length=255)
    website: Optional[str] = Field(None, max_length=500)
    logo_url: Optional[str] = Field(None, max_length=500)
    photo_urls: list[str] = []
    rating: Optional[float] = Field(None, ge=0, le=5)
    review_count: int = 0
    internal_notes: Optional[str] = None
    is_active: bool = True
    sort_order: int = 0


class ExperienceVendorCreate(ExperienceVendorBase):
    pass


class ExperienceVendorUpdate(ExperienceVendorBase):
    pass


class ExperienceVendorAdminResponse(ExperienceVendorBase):
    id: uuid.UUID
    package_count: int = 0
    # From travellers' published reviews, across all of the vendor's packages.
    # `rating` / `review_count` above are the old hand-typed numbers; they are
    # no longer shown anywhere.
    traveller_rating: Optional[float] = None
    traveller_review_count: int = 0
    created_at: datetime
    updated_at: Optional[datetime] = None


class ExperienceVendorListResponse(BaseModel):
    vendors: list[ExperienceVendorAdminResponse]
    total: int
    page: int = 1
    page_size: int = 50


class ExperiencePackageBase(BaseModel):
    title: str = Field(..., max_length=255)
    summary: Optional[str] = Field(None, max_length=500)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=60)
    tags: list[str] = []
    photo_urls: list[str] = []
    video_urls: list[str] = Field(default_factory=list, max_length=MAX_VIDEOS_PER_PACKAGE)
    unavailable_ranges: list[DateRange] = Field(
        default_factory=list, max_length=MAX_UNAVAILABLE_RANGES
    )
    price_amount: Optional[float] = Field(None, ge=0)
    price_currency: str = Field("USD", max_length=10)
    # Typed, never converted: see ExperiencePackage.price_usd.
    price_usd: Optional[float] = Field(None, ge=0)
    price_basis: str = Field("per_person", max_length=20)
    # Every price, first one first. None (a form from before price options)
    # makes the single price fields above the first option and keeps the rest.
    price_options: Optional[list[PriceOption]] = Field(None, max_length=MAX_PRICE_OPTIONS)
    duration_minutes: Optional[int] = Field(None, ge=0)
    max_participants: Optional[int] = Field(None, ge=1)
    # None: the platform default (DEFAULT_BOOKING_WINDOW_DAYS).
    booking_window_days: Optional[int] = Field(None, ge=1, le=MAX_BOOKING_WINDOW_DAYS)
    inclusions: list[str] = []
    languages: list[str] = []
    uses_vendor_location: bool = True
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    meeting_point_address: Optional[str] = Field(None, max_length=500)
    region_label: Optional[str] = Field(None, max_length=120)
    is_active: bool = True
    sort_order: int = 0


class ExperiencePackageCreate(ExperiencePackageBase):
    # On what the admin sends only, never on responses: a stored value from
    # before the list must still load.
    @field_validator("price_currency", mode="before")
    @classmethod
    def _known_currency(cls, value):
        # One of the app's currencies (the dropdown's list).
        return check_price_currency(value) or "USD"


class ExperiencePackageUpdate(ExperiencePackageCreate):
    pass


class ExperiencePackageAdminResponse(ExperiencePackageBase):
    id: uuid.UUID
    vendor_id: uuid.UUID
    is_published: bool = True
    rating_avg: Optional[float] = None
    rating_count: int = 0
    created_at: datetime
    updated_at: Optional[datetime] = None


class ExperiencePackageListResponse(BaseModel):
    packages: list[ExperiencePackageAdminResponse]
    total: int


class ExperienceEnquiryAdminResponse(BaseModel):
    id: uuid.UUID
    package_id: Optional[uuid.UUID] = None
    vendor_id: Optional[uuid.UUID] = None
    user_id: Optional[uuid.UUID] = None
    package_title_snapshot: Optional[str] = None
    vendor_name_snapshot: Optional[str] = None
    contact_name: str
    contact_phone: str
    contact_email: Optional[str] = None
    preferred_date: Optional[date] = None
    party_size: Optional[int] = None
    pickup_location: Optional[str] = None
    message: Optional[str] = None
    # The price chosen, as it read then; `label` is what to show.
    price_option: Optional[dict] = None
    status: str
    admin_notes: Optional[str] = None
    terms_version: Optional[int] = None
    terms_accepted_at: Optional[datetime] = None
    # The booking: confirmed by the provider for a day, or cancelled by either
    # side (the status says whose). `free_cancellation_last_day` is derived.
    confirmed_date: Optional[date] = None
    confirmed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancellation_reason: Optional[str] = None
    late_cancellation: Optional[bool] = None
    free_cancellation_last_day: Optional[date] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class ExperienceEnquiryListResponse(BaseModel):
    enquiries: list[ExperienceEnquiryAdminResponse]
    total: int
    page: int = 1
    page_size: int = 50


class ExperienceEnquiryUpdate(BaseModel):
    status: Optional[str] = Field(None, max_length=20)
    admin_notes: Optional[str] = None
    confirmed_date: Optional[date] = None
    cancellation_reason: Optional[str] = Field(None, max_length=1000)


# --- The traveller's own requests (app: My requests) ------------------------

class MyEnquiryOut(BaseModel):
    """One request as the traveller who sent it sees it."""

    id: uuid.UUID
    package_id: Optional[uuid.UUID] = None
    package_title: str
    vendor_name: Optional[str] = None
    cover_photo_url: Optional[str] = None
    # So the traveller can reach the provider from the request itself.
    vendor_phone: Optional[str] = None
    vendor_whatsapp: Optional[str] = None
    preferred_date: Optional[date] = None
    party_size: Optional[int] = None
    pickup_location: Optional[str] = None
    message: Optional[str] = None
    status: str
    created_at: datetime
    confirmed_date: Optional[date] = None
    confirmed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancellation_reason: Optional[str] = None
    late_cancellation: Optional[bool] = None
    free_cancellation_last_day: Optional[date] = None
    can_cancel: bool = False
    # Whether the package still exists to be rated and the request was not
    # cancelled: the app offers "Rate this experience" on the request itself.
    # `review` is the traveller's own review of that package, if any.
    can_review: bool = False
    review: Optional["MyReviewOut"] = None


class MyEnquiryListResponse(BaseModel):
    enquiries: list[MyEnquiryOut]


class MyEnquiryCancel(BaseModel):
    reason: Optional[str] = Field(None, max_length=1000)


# --- Ratings and reviews ----------------------------------------------------

class ReviewCreate(BaseModel):
    """What a traveller sends to rate a booking (a repeat send edits it)."""

    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=1000)


class MyReviewOut(BaseModel):
    """The traveller's own review of a booking."""

    id: uuid.UUID
    rating: int
    comment: Optional[str] = None
    # "hidden" when a moderator took it down; the traveller is told, the
    # public list no longer shows it.
    status: str = "published"
    created_at: datetime
    edited_at: Optional[datetime] = None
    vendor_reply: Optional[str] = None
    vendor_replied_at: Optional[datetime] = None


class ReviewPublic(BaseModel):
    """A review as any traveller sees it. First name and last initial only."""

    id: uuid.UUID
    reviewer_name: str
    rating: int
    comment: Optional[str] = None
    created_at: datetime
    edited: bool = False
    vendor_reply: Optional[str] = None
    vendor_replied_at: Optional[datetime] = None


class ReviewSummary(BaseModel):
    average: Optional[float] = None
    count: int = 0
    # How many reviews gave 5, 4, 3, 2 and 1 stars, in that order.
    breakdown: list[int] = [0, 0, 0, 0, 0]


class ReviewListResponse(BaseModel):
    summary: ReviewSummary
    reviews: list[ReviewPublic]
    total: int
    limit: int
    offset: int


class ExperienceReviewAdminResponse(BaseModel):
    """A review as the admin panel sees it, hidden ones included."""

    id: uuid.UUID
    package_id: uuid.UUID
    package_title: Optional[str] = None
    vendor_id: uuid.UUID
    vendor_name: Optional[str] = None
    reviewer_name: str
    rating: int
    comment: Optional[str] = None
    status: str
    vendor_reply: Optional[str] = None
    vendor_replied_at: Optional[datetime] = None
    created_at: datetime
    edited_at: Optional[datetime] = None
    hidden_at: Optional[datetime] = None


class ExperienceReviewListResponse(BaseModel):
    reviews: list[ExperienceReviewAdminResponse]
    total: int
    page: int = 1
    page_size: int = 25


class ExperienceReviewUpdate(BaseModel):
    status: Optional[str] = Field(None, max_length=12)
    # Takes the provider's reply down (the provider can write another).
    clear_reply: bool = False


MyEnquiryOut.model_rebuild()
