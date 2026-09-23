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

from pydantic import BaseModel, Field

from app.services.experience_format import NEARBY_THRESHOLD_M


# --- App-facing -------------------------------------------------------------

class ExperienceVendorPublic(BaseModel):
    """The vendor as the app sees it. Note the absence of `contact_email`."""

    id: uuid.UUID
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    latitude: float
    longitude: float
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
    price_label: str = ""
    duration_minutes: Optional[int] = None
    duration_label: str = ""
    latitude: float
    longitude: float
    distance_m: Optional[float] = None
    tags: list[str] = []


class ExperiencePackageDetail(ExperiencePackageCard):
    description: Optional[str] = None
    photo_urls: list[str] = []
    max_participants: Optional[int] = None
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


class ExperienceEnquiryCreate(BaseModel):
    package_id: uuid.UUID
    contact_name: str = Field(..., min_length=2, max_length=120)
    contact_phone: str = Field(..., min_length=6, max_length=32)
    contact_email: Optional[str] = Field(None, max_length=255)
    preferred_date: Optional[date] = None
    party_size: Optional[int] = Field(None, ge=1, le=100)
    message: Optional[str] = Field(None, max_length=2000)


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
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
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
    price_amount: Optional[float] = Field(None, ge=0)
    price_currency: str = Field("USD", max_length=10)
    price_basis: str = Field("per_person", max_length=20)
    duration_minutes: Optional[int] = Field(None, ge=0)
    max_participants: Optional[int] = Field(None, ge=1)
    inclusions: list[str] = []
    languages: list[str] = []
    uses_vendor_location: bool = True
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    meeting_point_address: Optional[str] = Field(None, max_length=500)
    is_active: bool = True
    sort_order: int = 0


class ExperiencePackageCreate(ExperiencePackageBase):
    pass


class ExperiencePackageUpdate(ExperiencePackageBase):
    pass


class ExperiencePackageAdminResponse(ExperiencePackageBase):
    id: uuid.UUID
    vendor_id: uuid.UUID
    is_published: bool = True
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
    message: Optional[str] = None
    status: str
    admin_notes: Optional[str] = None
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
