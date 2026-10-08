from pydantic import BaseModel, Field, model_validator
from typing import List, Optional, Dict, Any
from uuid import UUID
from datetime import datetime


# ── Category Schemas ──────────────────────────────────────────────────────────

class ForumCategoryBase(BaseModel):
    name: str = Field(..., max_length=100)
    slug: str = Field(..., max_length=120)
    category_type: str = Field("destination", description="destination or topic")
    parent_id: Optional[UUID] = None
    description: Optional[str] = Field(None, max_length=500)
    image_url: Optional[str] = Field(None, max_length=500)
    icon: Optional[str] = Field(None, max_length=50)
    country_code: Optional[str] = Field(None, max_length=10)
    city_name: Optional[str] = Field(None, max_length=100)
    is_featured: bool = False
    display_order: int = 0


class ForumCategoryCreate(ForumCategoryBase):
    pass


class ForumCategoryResponse(ForumCategoryBase):
    id: UUID
    topics_count: int = 0
    posts_count: int = 0
    created_at: datetime
    subcategories: List["ForumCategoryResponse"] = []

    @model_validator(mode="before")
    @classmethod
    def handle_orm(cls, data: Any) -> Any:
        if hasattr(data, "__dict__"):
            subcats = []
            if "subcategories" in data.__dict__ and data.__dict__["subcategories"]:
                subcats = data.__dict__["subcategories"]
            return {
                "id": getattr(data, "id", None),
                "name": getattr(data, "name", ""),
                "slug": getattr(data, "slug", ""),
                "category_type": getattr(data, "category_type", "destination"),
                "parent_id": getattr(data, "parent_id", None),
                "description": getattr(data, "description", None),
                "image_url": getattr(data, "image_url", None),
                "icon": getattr(data, "icon", None),
                "country_code": getattr(data, "country_code", None),
                "city_name": getattr(data, "city_name", None),
                "is_featured": getattr(data, "is_featured", False),
                "display_order": getattr(data, "display_order", 0),
                "topics_count": getattr(data, "topics_count", 0),
                "posts_count": getattr(data, "posts_count", 0),
                "created_at": getattr(data, "created_at", None),
                "subcategories": subcats,
            }
        return data

    class Config:
        from_attributes = True


# ── Post / Reply Schemas ──────────────────────────────────────────────────────

class ForumPostCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)
    image_urls: List[str] = Field(default_factory=list)
    parent_post_id: Optional[UUID] = None


class ForumPostResponse(BaseModel):
    id: UUID
    topic_id: UUID
    user_id: UUID
    user_display_name: str
    user_avatar_url: Optional[str] = None
    parent_post_id: Optional[UUID] = None
    content: str
    image_urls: List[str] = []
    likes_count: int = 0
    is_best_answer: bool = False
    is_ai_generated: bool = False
    is_liked: bool = False
    created_at: datetime
    replies: List["ForumPostResponse"] = []

    class Config:
        from_attributes = True


# ── Topic Schemas ─────────────────────────────────────────────────────────────

class ForumTopicCreate(BaseModel):
    category_id: UUID
    title: str = Field(..., min_length=3, max_length=255)
    content: str = Field(..., min_length=5, max_length=10000)
    tags: List[str] = Field(default_factory=list)
    image_urls: List[str] = Field(default_factory=list)


class ForumTopicResponse(BaseModel):
    id: UUID
    category_id: UUID
    category_name: str
    category_slug: str
    category_type: str = "destination"
    user_id: UUID
    user_display_name: str
    user_avatar_url: Optional[str] = None
    title: str
    content: str
    tags: List[str] = []
    image_urls: List[str] = []
    views_count: int = 0
    replies_count: int = 0
    likes_count: int = 0
    is_pinned: bool = False
    is_locked: bool = False
    best_answer_id: Optional[UUID] = None
    ai_summary: Optional[str] = None
    is_liked: bool = False
    is_bookmarked: bool = False
    created_at: datetime
    updated_at: datetime
    last_reply_at: Optional[datetime] = None
    last_reply_user_name: Optional[str] = None

    class Config:
        from_attributes = True


class ForumTopicDetailResponse(ForumTopicResponse):
    posts: List[ForumPostResponse] = []


# ── Forum Home Aggregated Schema ──────────────────────────────────────────────

class ForumHomeResponse(BaseModel):
    featured_destinations: List[ForumCategoryResponse] = []
    continent_regions: List[ForumCategoryResponse] = []
    travel_topics: List[ForumCategoryResponse] = []
    trending_topics: List[ForumTopicResponse] = []
    recent_topics: List[ForumTopicResponse] = []
    stats: Dict[str, Any] = {}
