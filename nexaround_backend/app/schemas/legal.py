import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class LegalDocumentOut(BaseModel):
    """The current version of a document, as the app, portal and website show it."""

    kind: str
    version: int
    title: str
    body: str
    highlights: list[str] = []
    published_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class CustomerTermsOut(LegalDocumentOut):
    # True when the signed-in traveller has accepted this version, so the app
    # shows a one-line reminder instead of the checkbox. False when signed out.
    accepted: bool = False


# --- Partner portal ---------------------------------------------------------

class PartnerAgreementOut(BaseModel):
    document: LegalDocumentOut
    accepted_version: Optional[int] = None
    accepted_at: Optional[datetime] = None
    # The portal blocks everything behind the agreement while this is true.
    required: bool
    # When the vendor's experiences leave the app if they have not accepted.
    grace_ends_at: datetime
    listed: bool


class PartnerAgreementAccept(BaseModel):
    version: int
    # The "I am authorised to accept for <business>" box, checked server-side
    # too so the record can never say otherwise.
    authorised: bool

    @field_validator("authorised")
    @classmethod
    def must_be_authorised(cls, value: bool) -> bool:
        if not value:
            raise ValueError("Confirm that you are authorised to accept for your business.")
        return value


# --- Admin ------------------------------------------------------------------

class LegalVersionSummary(BaseModel):
    version: int
    published_at: datetime
    updated_at: datetime
    updated_by: Optional[str] = None

    model_config = {"from_attributes": True}


class LegalDocumentAdminOut(LegalDocumentOut):
    updated_by: Optional[str] = None
    versions: list[LegalVersionSummary] = []


class LegalDocumentSave(BaseModel):
    title: str = Field(..., min_length=3, max_length=200)
    body: str = Field(..., min_length=20, max_length=60000)
    highlights: list[str] = Field(default_factory=list, max_length=6)
    # True: publish a new version, which everyone must accept again. False:
    # correct the current one in place (typos only).
    new_version: bool = False

    @field_validator("highlights")
    @classmethod
    def clean_highlights(cls, value: list[str]) -> list[str]:
        lines = [line.strip() for line in value if line and line.strip()]
        if any(len(line) > 160 for line in lines):
            raise ValueError("Keep each highlight under 160 characters.")
        return lines


class VendorAgreementStatus(BaseModel):
    vendor_id: uuid.UUID
    vendor_name: str
    vendor_is_active: bool
    accepted_version: Optional[int] = None
    accepted_at: Optional[datetime] = None
    # app | portal | offline
    method: Optional[str] = None
    accepted_by: Optional[str] = None
    note: Optional[str] = None
    is_current: bool
    listed: bool


class VendorAgreementListResponse(BaseModel):
    current_version: int
    published_at: datetime
    grace_ends_at: datetime
    vendors: list[VendorAgreementStatus]


class OfflineAcceptanceCreate(BaseModel):
    accepted_on: date
    # What the record rests on, e.g. "Signed partner form, filed 16 Oct".
    note: str = Field(..., min_length=3, max_length=1000)
