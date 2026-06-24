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
    pass

class TravelStoryResponse(TravelStoryBase):
    id: UUID
    user_id: UUID
    user_display_name: str
    user_avatar_url: Optional[str] = None
    likes_count: int
    is_liked: bool = False
    created_at: datetime
    comments: List[TravelStoryCommentResponse] = []

    class Config:
        from_attributes = True
