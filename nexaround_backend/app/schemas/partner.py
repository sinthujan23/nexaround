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

from pydantic import BaseModel, EmailStr, Field


# --- Admin-side: managing a vendor's logins ---------------------------------

class VendorLoginCreate(BaseModel):
    email: EmailStr
    display_name: Optional[str] = Field(None, max_length=120)


class VendorLoginUpdate(BaseModel):
    is_active: bool


class VendorLoginAdminResponse(BaseModel):
    """What the admin panel shows about a login.

    `password_hash` is deliberately absent; `has_password` is the fact the admin
    actually wants - whether the invite has been accepted yet.
    """

    id: uuid.UUID
    vendor_id: uuid.UUID
    email: str
    display_name: Optional[str] = None
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
    email: str
    display_name: Optional[str] = None
    vendor_id: uuid.UUID
    vendor_name: str
    vendor_is_active: bool


class PartnerTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    me: PartnerMe


class PartnerMessageResponse(BaseModel):
    status: str = "ok"
    message: str


# --- Partner-side: the business profile -------------------------------------

class PartnerVendorProfileUpdate(BaseModel):
    """Everything a vendor may change about themselves, and nothing else.

    The six forbidden names are simply not declared. Pydantic's default
    `extra="ignore"` means a client that sends `is_active` has it dropped before
    it can reach the setattr loop.
    """

    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    address: Optional[str] = Field(None, max_length=500)
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


class PartnerVendorProfileResponse(PartnerVendorProfileUpdate):
    """The profile plus the read-only facts a vendor should be able to see.

    `is_active` is here so the portal can say "your listing is hidden"; it is
    NOT on the update schema, so saying so costs nothing. `internal_notes` is
    absent in both directions.
    """

    id: uuid.UUID
    is_active: bool
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
    price_amount: Optional[float] = Field(None, ge=0)
    price_currency: Optional[str] = Field("LKR", max_length=10)
    price_basis: Optional[str] = Field("per_person", max_length=20)
    duration_minutes: Optional[int] = Field(None, ge=0)
    max_participants: Optional[int] = Field(None, ge=1)
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
    pass


class PartnerPackageUpdate(PartnerPackageBase):
    pass


class PartnerPackageResponse(PartnerPackageBase):
    id: uuid.UUID
    vendor_id: uuid.UUID
    is_published: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class PartnerPackageListResponse(BaseModel):
    packages: list[PartnerPackageResponse]


# --- Partner-side: enquiries ------------------------------------------------

ENQUIRY_STATUSES = ("new", "contacted", "closed")


class PartnerEnquiryResponse(BaseModel):
    """The traveller's enquiry as the vendor sees it.

    No `admin_notes` - that is the platform's private commentary. No `user_id` -
    the vendor has the contact details they need and does not get an identifier
    that maps into the traveller app.
    """

    id: uuid.UUID
    package_id: Optional[uuid.UUID] = None
    package_title_snapshot: Optional[str] = None
    contact_name: str
    contact_phone: str
    contact_email: Optional[str] = None
    preferred_date: Optional[date] = None
    party_size: Optional[int] = None
    message: Optional[str] = None
    status: str
    vendor_notes: Optional[str] = None
    created_at: Optional[datetime] = None


class PartnerEnquiryListResponse(BaseModel):
    enquiries: list[PartnerEnquiryResponse]
    total: int
    page: int = 1
    page_size: int = 25


class PartnerEnquiryUpdate(BaseModel):
    status: Optional[str] = Field(None, max_length=20)
    vendor_notes: Optional[str] = None


# --- Partner-side: stats ----------------------------------------------------

class PartnerStatsResponse(BaseModel):
    packages_total: int = 0
    packages_published: int = 0
    enquiries_total: int = 0
    enquiries_new: int = 0
    enquiries_last_30d: int = 0


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
