from pydantic import BaseModel, Field
from typing import List, Optional
from uuid import UUID
from datetime import datetime

class TravelStoryCommentBase(BaseModel):
    comment_text: str = Field(..., max_length=1000)
    image_index: int = Field(0, description="Index of the image this comment belongs to")

class TravelStoryCommentCreate(TravelStoryCommentBase):
    pass

class TravelStoryCommentResponse(TravelStoryCommentBase):
    id: UUID
    story_id: UUID
    user_id: UUID
    user_display_name: str
    user_avatar_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class TravelStoryBase(BaseModel):
    location_name: str = Field(..., max_length=255)
    category: str = Field(..., max_length=100)
    description: str = Field(..., max_length=1000)
    image_url: str = Field(..., max_length=500) # Kept for backwards compatibility
    image_urls: List[str] = Field(default_factory=list)
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    is_public: bool = True
    
    # Journal Features
    is_journal: bool = False
    journal_date: Optional[datetime] = None
    total_spend: float = 0.0
    spend_currency: str = "USD"
    cloud_provider: Optional[str] = None
    cloud_folder_url: Optional[str] = None
    travel_date: Optional[datetime] = None
    country: Optional[str] = None

class TravelStoryCreate(TravelStoryBase):
    # How the app set latitude/longitude: "place" (a picked suggestion), "here"
    # (the poster's GPS, by choice) or "saved" (unchanged on edit). Older builds
    # send nothing, and their coordinates are checked against the place name.
    location_source: Optional[str] = Field(None, max_length=16)

class TravelStoryResponse(TravelStoryBase):
    id: UUID
    user_id: UUID
    user_display_name: str
    user_avatar_url: Optional[str] = None
    likes_count: int
    is_liked: bool = False
    created_at: datetime
    comments: List[TravelStoryCommentResponse] = []
    # Metres from the location the feed was asked for; only set when the
    # request sent lat/lng and the story has a position.
    distance_m: Optional[float] = None
    # Posted by the team as the verified TravelByte account; `article_md` is
    # the long read opened from the story (light Markdown).
    is_official: bool = False
    title: Optional[str] = None
    article_md: Optional[str] = None

    class Config:
        from_attributes = True


class OfficialStoryIn(BaseModel):
    """An official story as the admin panel writes it."""
    title: str = Field(..., min_length=1, max_length=200)
    # The short intro on the story card.
    description: str = Field(..., min_length=1, max_length=1000)
    article_md: str = Field("", max_length=30000)
    location_name: str = Field(..., min_length=1, max_length=255)
    country: str = Field(..., min_length=1, max_length=100)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    category: str = Field(..., min_length=1, max_length=100)
    # The first photo is the cover.
    image_urls: List[str] = Field(..., min_length=1, max_length=20)
    is_public: bool = True


class OfficialStoryAdminOut(OfficialStoryIn):
    id: UUID
    likes_count: int
    comments_count: int
    created_at: datetime
