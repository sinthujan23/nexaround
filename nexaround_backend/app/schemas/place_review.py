"""Requests and answers for travellers' reviews of map places."""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class PlaceReviewIn(BaseModel):
    """Rate a place (a repeat send edits the first). The place's name and
    position are what the app showed; kept so the admin list can name it."""
    model_config = {"extra": "forbid"}

    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=1000)
    place_name: str = Field(..., min_length=1, max_length=255)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)


class PointsChange(BaseModel):
    """What an action did to the traveller's Explorer Points."""
    earned: int = 0
    total: int = 0
    level: int = 1
    level_name: str = ""
    levelled_up: bool = False


class PlaceReviewMine(BaseModel):
    """The traveller's own review. `status` is "hidden" when an admin took it
    down: the traveller is told, the public list no longer shows it."""
    id: uuid.UUID
    rating: int
    comment: Optional[str] = None
    status: str = "published"
    created_at: datetime
    edited_at: Optional[datetime] = None
    # Only on the answer to a send (PUT): the points it earned.
    points: Optional[PointsChange] = None


class PlaceReviewPublic(BaseModel):
    """A review as any traveller sees it: first name and last initial only."""
    id: uuid.UUID
    reviewer_name: str
    rating: int
    comment: Optional[str] = None
    created_at: datetime
    edited: bool = False
    # The reviewer's Explorer level (services/explorer_points.py).
    reviewer_level: Optional[int] = None
    reviewer_level_name: Optional[str] = None


class PlaceReviewSummary(BaseModel):
    average: Optional[float] = None
    count: int = 0
    # How many gave 5, 4, 3, 2 and 1 stars, in that order.
    breakdown: list[int] = [0, 0, 0, 0, 0]


class PlaceReviewList(BaseModel):
    summary: PlaceReviewSummary
    reviews: list[PlaceReviewPublic]
    total: int
    limit: int
    offset: int


class PlaceReviewAdmin(BaseModel):
    """A review as the admin panel sees it, hidden ones included."""
    id: uuid.UUID
    place_key: str
    place_name: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    user_id: uuid.UUID
    reviewer_name: str
    rating: int
    comment: Optional[str] = None
    status: str
    created_at: datetime
    edited_at: Optional[datetime] = None
    hidden_at: Optional[datetime] = None


class PlaceReviewAdminList(BaseModel):
    reviews: list[PlaceReviewAdmin]
    total: int
    page: int = 1
    page_size: int = 25


class PlaceReviewAdminUpdate(BaseModel):
    status: str = Field(..., max_length=12)
