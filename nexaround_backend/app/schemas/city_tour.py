"""City Tours request and response shapes. The guide itself travels as a plain
dict: its shape and checks are app/services/city_tours.py's."""
import uuid
from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field


class CityTourSaveIn(BaseModel):
    content: dict
    # The version the editor opened; a save over a newer one is refused (409)
    # rather than silently undoing someone else's edit. Omitted on create.
    version: Optional[int] = None


class CityTourTripStartIn(BaseModel):
    # The day to follow; the guide's first day when left out.
    day_id: Optional[str] = Field(None, max_length=36)


class CityTourVersionIn(BaseModel):
    version: int


class CityTourReviewIn(BaseModel):
    decision: Literal["approve", "request_changes"]
    note: str = Field("", max_length=2000)
    # The version the admin read in the preview.
    version: int


class CityTourVisibilityIn(BaseModel):
    hidden: bool


class CityTourTripDoneIn(BaseModel):
    step_id: str = Field(..., max_length=36)
    # When the traveller tapped "Mark done"; a retry sends the same time.
    at: Optional[datetime] = None


class CityTourListItem(BaseModel):
    id: uuid.UUID
    title: str
    city: str
    country: str
    cover_url: str
    stop_count: int
    day_count: int = 1
    review_status: str
    review_note: Optional[str] = None
    is_live: bool
    is_hidden: bool
    # Live, and the working copy has moved on since.
    has_changes: bool
    author_name: str
    is_mine: bool
    updated_at: datetime
    submitted_at: Optional[datetime] = None
    published_at: Optional[datetime] = None
    # Partner taps, all time. Admins only.
    taps: Optional[int] = None
    # Travellers who started the guide in the app, and who finished it. Admins only.
    trips_started: Optional[int] = None
    trips_finished: Optional[int] = None


class CityTourDetail(CityTourListItem):
    content: dict
    version: int
    live_version: Optional[int] = None
    reviewed_at: Optional[datetime] = None
    reviewed_by: Optional[str] = None
    # What it still needs before review; empty when it can go.
    problems: list[str]
    can_delete: bool
    # link id → taps, all time. Admins only.
    link_taps: Optional[dict[str, int]] = None


class ContentCreatorIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(..., min_length=10, max_length=128)


class ContentCreatorPatch(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    is_active: Optional[bool] = None
    password: Optional[str] = Field(None, min_length=10, max_length=128)


class ContentCreatorOut(BaseModel):
    id: uuid.UUID
    name: str
    email: str
    is_active: bool
    created_at: datetime
    last_login_at: Optional[datetime] = None
    tour_count: int = 0
    live_count: int = 0
