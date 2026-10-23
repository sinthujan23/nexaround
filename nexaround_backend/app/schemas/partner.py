"""Schemas for the partner portal.

Kept apart from `schemas/experience.py` for one reason: the admin schemas carry
fields a vendor must never send or see - `is_active`, `rating`, `review_count`,
`internal_notes`, `sort_order`, `google_place_id` - and the admin update path is
a full-replacement loop with a default for every field. A vendor schema that
inherits from `ExperienceVendorBase` would therefore hand back those defaults on
every save. These are declared from scratch, and a test asserts the forbidden
names appear in none of them.
"""
import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.experience import DateRange, PriceOptionBase
from app.services.currencies import check_price_currency
from app.services.experience_format import (
    MAX_BOOKING_WINDOW_DAYS, MAX_PRICE_OPTIONS, MAX_UNAVAILABLE_RANGES,
)


# --- Admin-side: managing a vendor's logins ---------------------------------

class VendorLoginCreate(BaseModel):
    email: EmailStr
    display_name: Optional[str] = Field(None, max_length=120)


class VendorAppAccessCreate(BaseModel):
    """Give the vendor to a traveller account, to manage from the app."""

    user_id: uuid.UUID


class VendorLoginUpdate(BaseModel):
    is_active: bool


class VendorLoginAdminResponse(BaseModel):
    """What the admin panel shows about a login.

    `password_hash` is deliberately absent; `has_password` is the fact the admin
    actually wants - whether the invite has been accepted yet.
    """

    id: uuid.UUID
    vendor_id: uuid.UUID
    # "portal" (email and password, partner.nexaround.com) or "app" (a
    # traveller account given the vendor; no email of its own).
    kind: str = "portal"
    email: Optional[str] = None
    display_name: Optional[str] = None
    # The traveller account behind an app login, as the admin searched it.
    app_user_id: Optional[uuid.UUID] = None
    app_user_email: Optional[str] = None
    app_user_name: Optional[str] = None
    is_active: bool
    has_password: bool
    last_login_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


class VendorLoginListResponse(BaseModel):
    logins: list[VendorLoginAdminResponse]


# --- Partner-side: auth -----------------------------------------------------

class PartnerLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=1, max_length=200)


class PartnerForgotPasswordRequest(BaseModel):
    email: EmailStr


class PartnerSetPasswordRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=256)
    new_password: str = Field(..., min_length=8, max_length=100)


class PartnerMe(BaseModel):
    """The signed-in identity, for the sidebar and the suspension banner."""

    login_id: uuid.UUID
    # None for an app login (VendorUser.app_user_id), which has no email.
    email: Optional[str] = None
    display_name: Optional[str] = None
    vendor_id: uuid.UUID
    vendor_name: str
    vendor_is_active: bool


class PartnerTokenResponse(BaseModel):
    access_token: str
    # None for an app session: the app trades the traveller's own token for a
    # new one instead (POST /partner/app/session).
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    me: PartnerMe


# --- The app's way in -------------------------------------------------------

class PartnerAppVendor(BaseModel):
    """A vendor the signed-in traveller has been given to manage."""

    vendor_id: uuid.UUID
    vendor_name: str
    logo_url: Optional[str] = None


class PartnerAppAccessResponse(BaseModel):
    vendors: list[PartnerAppVendor]


class PartnerAppSessionRequest(BaseModel):
    vendor_id: uuid.UUID


class PartnerMessageResponse(BaseModel):
    status: str = "ok"
    message: str


# --- Partner-side: the business profile -------------------------------------

class PartnerVendorProfileUpdate(BaseModel):
    """Everything a vendor may change about themselves, and nothing else; an
    admin reviews it before travellers see it (services/vendor_review).

    The six forbidden names are simply not declared, and neither are the
    traveller-facing contacts (phone, WhatsApp, Instagram, Facebook, X) or
    where the business is (address, city, country, map point, website), which
    only an admin sets. Pydantic's default `extra="ignore"` means a client that
    sends `is_active` - or an older portal that still sends the address - has
    it dropped before it can reach the save.
    """

    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    contact_email: Optional[str] = Field(None, max_length=255)
    logo_url: Optional[str] = Field(None, max_length=500)
    photo_urls: list[str] = []


class PartnerReviewState(BaseModel):
    """Where a vendor's own edits stand. The other fields of the response are
    what the vendor last asked for, which is live once `review_status` is
    "approved"."""

    review_status: str = "approved"  # approved | pending | changes_requested
    review_note: Optional[str] = None
    submitted_at: Optional[datetime] = None
    reviewed_at: Optional[datetime] = None


class PartnerVendorProfileResponse(PartnerVendorProfileUpdate, PartnerReviewState):
    """The profile plus the read-only facts a vendor should be able to see.

    `is_active` is here so the portal can say "your listing is hidden"; it is
    NOT on the update schema, so saying so costs nothing. `internal_notes` is
    absent in both directions.
    """

    id: uuid.UUID
    is_active: bool
    # Shown read-only: only an admin sets where the business is.
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    address: Optional[str] = None
    city: Optional[str] = None
    country_code: Optional[str] = None
    website: Optional[str] = None
    # Shown read-only: only an admin sets how travellers reach the vendor.
    contact_phone: Optional[str] = None
    contact_whatsapp: Optional[str] = None
    contact_instagram: Optional[str] = None
    contact_facebook: Optional[str] = None
    contact_x: Optional[str] = None
    rating: Optional[float] = None
    review_count: int = 0
    package_count: int = 0
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


# --- Partner-side: packages -------------------------------------------------

class PartnerPackageBase(BaseModel):
    title: str = Field(..., max_length=255)
    summary: Optional[str] = Field(None, max_length=500)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=60)
    tags: list[str] = []
    photo_urls: list[str] = []
    # Dates this package cannot be booked; everything else is available.
    unavailable_ranges: list[DateRange] = Field(
        default_factory=list, max_length=MAX_UNAVAILABLE_RANGES
    )
    price_amount: Optional[float] = Field(None, ge=0)
    price_currency: Optional[str] = Field("LKR", max_length=10)
    price_basis: Optional[str] = Field("per_person", max_length=20)
    # Every price, first one first, without the dollar price: only an admin
    # sets that. None (a form from before price options) makes the single
    # fields above the first option and keeps the rest.
    price_options: Optional[list[PriceOptionBase]] = Field(None, max_length=MAX_PRICE_OPTIONS)
    duration_minutes: Optional[int] = Field(None, ge=0)
    max_participants: Optional[int] = Field(None, ge=1)
    # How far ahead travellers may book: the vendor's own business rule.
    booking_window_days: Optional[int] = Field(None, ge=1, le=MAX_BOOKING_WINDOW_DAYS)
    inclusions: list[str] = []
    languages: list[str] = []
    # The vendor's own publish toggle. Safe to expose: `is_published` stays
    # gated behind the vendor's own `is_active`, which only an admin can set.
    # No meeting point: where travellers meet the vendor is an admin's to set
    # (an older portal that still sends one has it dropped).
    is_active: bool = True


class PartnerPackageCreate(PartnerPackageBase):
    # On what the vendor sends only, never on responses: a stored value from
    # before the list must still load.
    @field_validator("price_currency", mode="before")
    @classmethod
    def _known_currency(cls, value):
        # One of the app's currencies (the dropdown's list).
        return check_price_currency(value)


class PartnerPackageUpdate(PartnerPackageCreate):
    pass


class PartnerPackageResponse(PartnerPackageBase, PartnerReviewState):
    id: uuid.UUID
    vendor_id: uuid.UUID
    # Whether travellers see the live version (approved once, switched on,
    # listing live). `is_approved` is false for a new package still waiting.
    is_published: bool = False
    is_approved: bool = True
    # Read-only: set by NexAround.
    uses_vendor_location: bool = True
    meeting_point_address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class PartnerPackageListResponse(BaseModel):
    packages: list[PartnerPackageResponse]


# --- Partner-side: stats ----------------------------------------------------

class PartnerReviewResponse(BaseModel):
    """A published review of one of this vendor's packages.

    No `user_id`, no contact detail: the vendor sees what a traveller sees, the
    "Anna K." name included. Hidden reviews are not listed at all.
    """

    id: uuid.UUID
    package_id: uuid.UUID
    package_title: Optional[str] = None
    reviewer_name: str
    rating: int
    comment: Optional[str] = None
    created_at: datetime
    edited_at: Optional[datetime] = None
    vendor_reply: Optional[str] = None
    vendor_replied_at: Optional[datetime] = None


class PartnerReviewListResponse(BaseModel):
    reviews: list[PartnerReviewResponse]
    total: int
    page: int = 1
    page_size: int = 25
    # Across every published review, not just this page.
    average: Optional[float] = None
    review_count: int = 0
    # Published reviews without a reply yet.
    unanswered: int = 0


class PartnerReviewReply(BaseModel):
    """The provider's answer. Empty (or null) takes the reply down."""

    reply: Optional[str] = Field(None, max_length=1000)


class PartnerStatsResponse(BaseModel):
    packages_total: int = 0
    packages_published: int = 0
    # Requests the vendor has not answered yet.
    requests_waiting: int = 0


# --- Partner-side: requests -------------------------------------------------

class PartnerRequest(BaseModel):
    """A traveller's request as the vendor sees it: what, when, how many and
    at which price. Never who asked, how to reach them, where to pick them up
    or what they wrote: NexAround arranges the booking with the traveller."""

    id: uuid.UUID
    # "#3F9A1C", to name the request to NexAround.
    reference: str
    package_id: Optional[uuid.UUID] = None
    package_title: str
    # None for a traveller who is flexible about the day.
    preferred_date: Optional[date] = None
    confirmed_date: Optional[date] = None
    party_size: Optional[int] = None
    price_label: Optional[str] = None
    # new | contacted | confirmed | closed | customer_cancelled | provider_cancelled
    status: str
    # The vendor's own answer: confirmed | other_date | cancelled.
    vendor_response: Optional[str] = None
    vendor_offered_date: Optional[date] = None
    vendor_response_reason: Optional[str] = None
    vendor_responded_at: Optional[datetime] = None
    # The traveller's answer to the date offered: accepted | declined.
    offer_response: Optional[str] = None
    can_answer: bool = False
    created_at: datetime


class PartnerRequestListResponse(BaseModel):
    requests: list[PartnerRequest]
    total: int
    # Open and not answered yet.
    waiting: int = 0


class PartnerRequestAnswer(BaseModel):
    """Confirm (for `day`, required when the traveller is flexible), offer
    another `day`, or cancel when no other day works. `reason` is a key of
    enquiry_lifecycle.DECLINE_REASONS; `note` reaches NexAround only."""

    action: str = Field(..., pattern="^(confirmed|other_date|cancelled)$")
    day: Optional[date] = None
    reason: Optional[str] = Field(None, max_length=30)
    note: Optional[str] = Field(None, max_length=1000)


# --- Activity feed (the portal's bell) --------------------------------------

class PartnerActivity(BaseModel):
    id: uuid.UUID
    kind: str
    title: str
    body: Optional[str] = None
    # "traveller", "vendor" or "admin". The portal shows "You" when
    # actor_login_id is the viewer's own login, the name for a teammate, and
    # "NexAround" for an admin.
    actor: str
    actor_login_id: Optional[uuid.UUID] = None
    actor_name: Optional[str] = None
    enquiry_id: Optional[uuid.UUID] = None
    package_id: Optional[uuid.UUID] = None
    created_at: datetime


class PartnerActivityListResponse(BaseModel):
    items: list[PartnerActivity]
    has_more: bool
    unread: int
    # This login's watermark as it was before this read; the portal
    # highlights the lines newer than it.
    seen_at: Optional[datetime] = None


class PartnerActivityUnreadResponse(BaseModel):
    unread: int
    seen_at: Optional[datetime] = None
