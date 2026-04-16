from pydantic import BaseModel, Field
from typing import List, Optional
from uuid import UUID
from datetime import datetime

class ReviewBase(BaseModel):
    attraction_id: UUID
    rating: int = Field(ge=1, le=5)
    comment: Optional[str] = None

class ReviewCreate(ReviewBase):
    pass

class ReviewResponse(ReviewBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    user_display_name: Optional[str] = None

    class Config:
        from_attributes = True
        
class AttractionRatingSummary(BaseModel):
    average_rating: float
    total_reviews: int
