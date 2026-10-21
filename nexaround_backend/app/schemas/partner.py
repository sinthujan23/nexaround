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
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.schemas.experience import DateRange
from app.services.currencies import check_price_currency
from app.services.experience_format import MAX_BOOKING_WINDOW_DAYS, MAX_UNAVAILABLE_RANGES


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
    """Everything a vendor may change about themselves, and nothing else.

    The six forbidden names are simply not declared, and neither are the
    traveller-facing contacts (phone, WhatsApp, Instagram, Facebook, X), which
    only an admin sets. Pydantic's default `extra="ignore"` means a client that
    sends `is_active` has it dropped before it can reach the setattr loop.
    """

    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    address: Optional[str] = Field(None, max_length=500)
    city: Optional[str] = Field(None, max_length=120)
    country_code: Optional[str] = Field(None, max_length=2)
    contact_email: Optional[str] = Field(None, max_length=255)
    website: Optional[str] = Field(None, max_length=500)
    logo_url: Optional[str] = Field(None, max_length=500)
    photo_urls: list[str] = []


class PartnerVendorProfileResponse(PartnerVendorProfileUpdate):
    """The profile plus the read-only facts a vendor should be able to see.

    `is_active` is here so the portal can say "your listing is hidden"; it is
    NOT on the update schema, so saying so costs nothing. `internal_notes` is
    absent in both directions.
    """

    id: uuid.UUID
    is_active: bool
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
    duration_minutes: Optional[int] = Field(None, ge=0)
    max_participants: Optional[int] = Field(None, ge=1)
    # How far ahead travellers may book: the vendor's own business rule.
    booking_window_days: Optional[int] = Field(None, ge=1, le=MAX_BOOKING_WINDOW_DAYS)
    inclusions: list[str] = []
    languages: list[str] = []
    uses_vendor_location: bool = True
    meeting_point_address: Optional[str] = Field(None, max_length=500)
    # The vendor's own publish toggle. Safe to expose: `is_published` stays
    # gated behind the vendor's own `is_active`, which only an admin can set.
    is_active: bool = True
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)


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


class PartnerPackageResponse(PartnerPackageBase):
    id: uuid.UUID
    vendor_id: uuid.UUID
    is_published: bool = False
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
