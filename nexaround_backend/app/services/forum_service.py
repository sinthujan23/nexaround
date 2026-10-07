import uuid
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from sqlalchemy import select, func, or_, desc, update
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.forum import ForumCategory, ForumTopic, ForumPost, ForumLike, ForumBookmark
from app.models.user import User
from app.schemas.forum import (
    ForumCategoryResponse,
    ForumTopicCreate,
    ForumTopicResponse,
    ForumTopicDetailResponse,
    ForumPostCreate,
    ForumPostResponse,
    ForumHomeResponse,
)

logger = logging.getLogger(__name__)


# ── Seed Categories & Starter Data ──────────────────────────────────────────

DEFAULT_DESTINATIONS = [
    {
        "name": "Europe",
        "slug": "europe",
        "category_type": "region",
        "icon": "public",
        "image_url": "https://images.unsplash.com/photo-1467269204594-9661b134dd2b?w=800",
        "display_order": 1,
        "subcategories": [
            {
                "name": "Rome",
                "slug": "rome",
                "category_type": "destination",
                "country_code": "IT",
                "city_name": "Rome",
                "is_featured": True,
                "icon": "account_balance",
                "image_url": "https://images.unsplash.com/photo-1552832230-c0197dd311b5?w=800",
                "description": "The Eternal City: Colosseum, Trastevere, Vatican & Italian culinary secrets.",
            },
            {
                "name": "Paris",
                "slug": "paris",
                "category_type": "destination",
                "country_code": "FR",
                "city_name": "Paris",
                "is_featured": True,
                "icon": "attractions",
                "image_url": "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800",
                "description": "City of Lights: Eiffel Tower, Montmartre, Louvre & pastry crawl discussions.",
            },
            {
                "name": "London",
                "slug": "london",
                "category_type": "destination",
                "country_code": "GB",
                "city_name": "London",
                "is_featured": True,
                "icon": "museum",
                "image_url": "https://images.unsplash.com/photo-1513635269975-59663e0ac1ad?w=800",
                "description": "Historic charm: West End shows, free national museums, tube tips & day trips.",
            },
            {
                "name": "Barcelona",
                "slug": "barcelona",
                "category_type": "destination",
                "country_code": "ES",
                "city_name": "Barcelona",
                "is_featured": True,
                "icon": "beach_access",
                "image_url": "https://images.unsplash.com/photo-1583422409516-2895a77efded?w=800",
                "description": "Catalan culture: Gaudí masterpieces, Gothic Quarter tapas, and Mediterranean beaches.",
            },
        ],
    },
    {
        "name": "Asia",
        "slug": "asia",
        "category_type": "region",
        "icon": "travel_explore",
        "image_url": "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=800",
        "display_order": 2,
        "subcategories": [
            {
                "name": "Tokyo",
                "slug": "tokyo",
                "category_type": "destination",
                "country_code": "JP",
                "city_name": "Tokyo",
                "is_featured": True,
                "icon": "train",
                "image_url": "https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=800",
                "description": "Neon metropolis: Shibuya crossing, Shinkansen travel, ramen spots & etiquette.",
            },
            {
                "name": "Bali",
                "slug": "bali",
                "country_code": "ID",
                "city_name": "Bali",
                "is_featured": True,
                "category_type": "destination",
                "icon": "spa",
                "image_url": "https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=800",
                "description": "Island of the Gods: Ubud rice terraces, surf breaks, temples, and scooter advice.",
            },
            {
                "name": "Bangkok",
                "slug": "bangkok",
                "country_code": "TH",
                "city_name": "Bangkok",
                "is_featured": True,
                "category_type": "destination",
                "icon": "restaurant",
                "image_url": "https://images.unsplash.com/photo-1508009603885-50cf7c579365?w=800",
                "description": "Vibrant street food, Grand Palace, Chao Phraya river boats, and night markets.",
            },
        ],
    },
    {
        "name": "North America",
        "slug": "north-america",
        "category_type": "region",
        "icon": "explore",
        "image_url": "https://images.unsplash.com/photo-1485738422979-f5c462d49f74?w=800",
        "display_order": 3,
        "subcategories": [
            {
                "name": "New York City",
                "slug": "new-york-city",
                "category_type": "destination",
                "country_code": "US",
                "city_name": "New York",
                "is_featured": True,
                "icon": "apartment",
                "image_url": "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=800",
                "description": "Broadway tickets, Central Park walks, subway navigation & local food gems.",
            },
            {
                "name": "Cancun & Riviera Maya",
                "slug": "cancun",
                "category_type": "destination",
                "country_code": "MX",
                "city_name": "Cancun",
                "is_featured": True,
                "icon": "surfing",
                "image_url": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800",
                "description": "Cenotes exploration, Mayan ruins, all-inclusive resorts & ferry to Isla Mujeres.",
            },
        ],
    },
    {
        "name": "Middle East & Africa",
        "slug": "middle-east-africa",
        "category_type": "region",
        "icon": "terrain",
        "image_url": "https://images.unsplash.com/photo-1512453979798-5ea266f8880c?w=800",
        "display_order": 4,
        "subcategories": [
            {
                "name": "Dubai",
                "slug": "dubai",
                "category_type": "destination",
                "country_code": "AE",
                "city_name": "Dubai",
                "is_featured": True,
                "icon": "hotel_class",
                "image_url": "https://images.unsplash.com/photo-1518684079-3c830dcef090?w=800",
                "description": "Burj Khalifa, desert safaris, luxury marinas, and Old Dubai souks.",
            },
        ],
    },
]

DEFAULT_TRAVEL_TOPICS = [
    {
        "name": "Air Travel & Flights",
        "slug": "air-travel",
        "category_type": "topic",
        "icon": "flight_takeoff",
        "image_url": "https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=800",
        "description": "Airlines, carry-on rules, airport lounges, layover hacks, and flight deals.",
        "display_order": 1,
    },
    {
        "name": "Solo Travel",
        "slug": "solo-travel",
        "category_type": "topic",
        "icon": "person",
        "image_url": "https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=800",
        "description": "Safety advice, meeting fellow travelers, single supplement tips & confidence.",
        "display_order": 2,
    },
    {
        "name": "Budget & Backpacking",
        "slug": "budget-backpacking",
        "category_type": "topic",
        "icon": "account_balance_wallet",
        "image_url": "https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?w=800",
        "description": "Hostel reviews, rail passes, free city activities, and stretching your travel fund.",
        "display_order": 3,
    },
    {
        "name": "Family Travel with Kids",
        "slug": "family-travel",
        "category_type": "topic",
        "icon": "family_restroom",
        "image_url": "https://images.unsplash.com/photo-1511895426328-dc8714191300?w=800",
        "description": "Kid-friendly attractions, stroller accessibility, long flights with toddlers.",
        "display_order": 4,
    },
    {
        "name": "Food, Wine & Culinary",
        "slug": "food-and-dining",
        "category_type": "topic",
        "icon": "restaurant",
        "image_url": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800",
        "description": "Authentic street eats, reservation hacks, dietary needs abroad & market tours.",
        "display_order": 5,
    },
    {
        "name": "Honeymoons & Romance",
        "slug": "honeymoons-romance",
        "category_type": "topic",
        "icon": "favorite",
        "image_url": "https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=800",
        "description": "Overwater bungalows, scenic hideaways, sunset dining, and special getaways.",
        "display_order": 6,
    },
]


async def seed_forum_data(db: AsyncSession) -> None:
    """Pre-seed TripAdvisor-style categories and starter discussions if table is empty."""
    res = await db.execute(select(func.count(ForumCategory.id)))
    count = res.scalar() or 0
    if count > 0:
        return

    logger.info("🌱 Seeding NexAround Forum categories and starter topics...")

    # 1. Seed Continents & Top Destinations
    category_map = {}
    for region_data in DEFAULT_DESTINATIONS:
        subcats = region_data.get("subcategories", [])
        region = ForumCategory(
            name=region_data["name"],
            slug=region_data["slug"],
            category_type=region_data["category_type"],
            icon=region_data.get("icon"),
            image_url=region_data.get("image_url"),
            display_order=region_data.get("display_order", 0),
        )
        db.add(region)
        await db.flush()
        category_map[region.slug] = region

        for sub in subcats:
            cat = ForumCategory(
                name=sub["name"],
                slug=sub["slug"],
                category_type=sub["category_type"],
                parent_id=region.id,
                country_code=sub.get("country_code"),
                city_name=sub.get("city_name"),
                is_featured=sub.get("is_featured", False),
                icon=sub.get("icon"),
                image_url=sub.get("image_url"),
                description=sub.get("description"),
            )
            db.add(cat)
            await db.flush()
            category_map[cat.slug] = cat

    # 2. Seed Travel Topics
    for topic_data in DEFAULT_TRAVEL_TOPICS:
        cat = ForumCategory(
            name=topic_data["name"],
            slug=topic_data["slug"],
            category_type=topic_data["category_type"],
            icon=topic_data.get("icon"),
            image_url=topic_data.get("image_url"),
            description=topic_data.get("description"),
            display_order=topic_data.get("display_order", 0),
        )
        db.add(cat)
        await db.flush()
        category_map[cat.slug] = cat

    # 3. Find or use a system user for starter discussions
    user_res = await db.execute(select(User).limit(1))
    sys_user = user_res.scalars().first()

    if sys_user and "rome" in category_map:
        rome_cat = category_map["rome"]
        # Seed realistic Rome starter discussion
        topic1 = ForumTopic(
            category_id=rome_cat.id,
            user_id=sys_user.id,
            title="Colosseum & Roman Forum: Best time of day and ticket advice for first-timers?",
            content=(
                "Visiting Rome for the first time in May! I want to know if it's better to book "
                "the Colosseum first thing in the morning (8:30 AM) or late afternoon around sunset. "
                "Also, does the standard ticket include the Arena Floor, and is the Roma Pass worth it?"
            ),
            tags=["Colosseum", "Tickets", "Itinerary", "First-time"],
            views_count=184,
            replies_count=2,
            likes_count=18,
            is_pinned=True,
        )
        db.add(topic1)
        await db.flush()
        rome_cat.topics_count += 1

        # Seed replies
        p1 = ForumPost(
            topic_id=topic1.id,
            user_id=sys_user.id,
            content=(
                "Definitely aim for 8:30 AM or 4:30 PM! Midday heat and crowds on the Roman Forum "
                "can be intense as there is very little shade. Standard tickets cover the Roman Forum "
                "and Palatine Hill within 24 hours. The Full Experience ticket is required for the Arena and Underground."
            ),
            likes_count=12,
            is_best_answer=True,
        )
        db.add(p1)
        await db.flush()
        topic1.best_answer_id = p1.id

        p2 = ForumPost(
            topic_id=topic1.id,
            user_id=sys_user.id,
            content=(
                "Pro tip: Enter via the Palatine Hill entrance on Via di San Gregorio rather than "
                "the main Colosseum gate — the security line is usually much shorter!"
            ),
            likes_count=7,
        )
        db.add(p2)

    if sys_user and "tokyo" in category_map:
        tokyo_cat = category_map["tokyo"]
        topic2 = ForumTopic(
            category_id=tokyo_cat.id,
            user_id=sys_user.id,
            title="Digital Welcome Suica vs Physical IC Card in 2026: What's working best?",
            content=(
                "Planning 10 days across Tokyo and Kyoto. Is it currently easier to load a digital "
                "Suica on Apple Wallet / Google Wallet with a Visa or Mastercard, or should I pick up "
                "a physical tourist IC card at Haneda Airport upon arrival?"
            ),
            tags=["Transport", "Suica", "Tokyo", "Payment"],
            views_count=240,
            replies_count=1,
            likes_count=24,
        )
        db.add(topic2)
        await db.flush()
        tokyo_cat.topics_count += 1

        p3 = ForumPost(
            topic_id=topic2.id,
            user_id=sys_user.id,
            content=(
                "If you have an iPhone, Apple Wallet digital Suica is instantaneous! Mastercard and Amex "
                "work smoothly for top-ups. Visa sometimes has 3D-Secure blocks, so Amex or Mastercard is best. "
                "For Android devices without Osaifu-Keitai, grab the Welcome Suica at Haneda or Narita."
            ),
            likes_count=15,
            is_best_answer=True,
        )
        db.add(p3)

    if sys_user and "solo-travel" in category_map:
        solo_cat = category_map["solo-travel"]
        topic3 = ForumTopic(
            category_id=solo_cat.id,
            user_id=sys_user.id,
            title="First solo trip to Europe: How do you handle dinner alone without feeling awkward?",
            content=(
                "I am doing my first solo trip next month. Daytime sightseeing feels great, but I get "
                "slightly nervous about dining alone in sit-down restaurants in the evening. "
                "Any mindset tips or recommendations for dining spots that feel welcoming?"
            ),
            tags=["Solo", "Dining", "Tips", "Beginners"],
            views_count=310,
            replies_count=1,
            likes_count=39,
        )
        db.add(topic3)
        await db.flush()
        solo_cat.topics_count += 1

        p4 = ForumPost(
            topic_id=topic3.id,
            user_id=sys_user.id,
            content=(
                "Sit at the bar or communal tables! Tapas bars in Spain and trattorias with outdoor terraces "
                "are amazing for people-watching. Bring a journal or book, or chat with the bartender. "
                "Remember: nobody is watching you or judging — solo dining is totally normal everywhere!"
            ),
            likes_count=21,
            is_best_answer=True,
        )
        db.add(p4)

    await db.commit()
    logger.info("✅ Forum categories and starter topics successfully seeded.")


# ── Forum Service Queries ───────────────────────────────────────────────────

class ForumService:

    @staticmethod
    async def get_forum_home(
        db: AsyncSession, current_user_id: Optional[uuid.UUID] = None
    ) -> ForumHomeResponse:
        """Fetch all data required to render the TripAdvisor ForumHome."""
        # Ensure categories exist
        await seed_forum_data(db)

        # 1. Top Featured Destinations
        featured_dest_res = await db.execute(
            select(ForumCategory)
            .where(ForumCategory.is_featured == True)
            .order_by(ForumCategory.display_order.asc(), ForumCategory.topics_count.desc())
        )
        featured_destinations = [
            ForumCategoryResponse.model_validate(c) for c in featured_dest_res.scalars().all()
        ]

        # 2. Continent Regions with subcategories
        regions_res = await db.execute(
            select(ForumCategory)
            .where(ForumCategory.parent_id == None, ForumCategory.category_type == "region")
            .options(selectinload(ForumCategory.subcategories))
            .order_by(ForumCategory.display_order.asc())
        )
        continent_regions = [
            ForumCategoryResponse.model_validate(c) for c in regions_res.scalars().all()
        ]

        # 3. General Travel Topics
        topics_cats_res = await db.execute(
            select(ForumCategory)
            .where(ForumCategory.category_type == "topic")
            .order_by(ForumCategory.display_order.asc())
        )
        travel_topics = [
            ForumCategoryResponse.model_validate(c) for c in topics_cats_res.scalars().all()
        ]

        # 4. Trending Topics (highest views + likes)
        trending_stmt = (
            select(ForumTopic)
            .options(selectinload(ForumTopic.category), selectinload(ForumTopic.user))
            .order_by(desc(ForumTopic.views_count + (ForumTopic.likes_count * 5)), desc(ForumTopic.created_at))
            .limit(10)
        )
        trending_res = await db.execute(trending_stmt)
        trending_topics_raw = trending_res.scalars().all()

        # 5. Recent Discussions
        recent_stmt = (
            select(ForumTopic)
            .options(selectinload(ForumTopic.category), selectinload(ForumTopic.user))
            .order_by(desc(ForumTopic.created_at))
            .limit(10)
        )
        recent_res = await db.execute(recent_stmt)
        recent_topics_raw = recent_res.scalars().all()

        # User likes & bookmarks lookup
        user_liked_topics = set()
        user_bookmarked_topics = set()
        if current_user_id:
            likes_res = await db.execute(
                select(ForumLike.topic_id).where(
                    ForumLike.user_id == current_user_id, ForumLike.topic_id != None
                )
            )
            user_liked_topics = set(likes_res.scalars().all())

            bm_res = await db.execute(
                select(ForumBookmark.topic_id).where(ForumBookmark.user_id == current_user_id)
            )
            user_bookmarked_topics = set(bm_res.scalars().all())

        def map_topic(t: ForumTopic) -> ForumTopicResponse:
            return ForumTopicResponse(
                id=t.id,
                category_id=t.category_id,
                category_name=t.category.name if t.category else "",
                category_slug=t.category.slug if t.category else "",
                category_type=t.category.category_type if t.category else "destination",
                user_id=t.user_id,
                user_display_name=t.user.display_name if t.user else "Traveler",
                user_avatar_url=t.user.avatar_url if t.user else None,
                title=t.title,
                content=t.content,
                tags=t.tags or [],
                image_urls=t.image_urls or [],
                views_count=t.views_count,
                replies_count=t.replies_count,
                likes_count=t.likes_count,
                is_pinned=t.is_pinned,
                is_locked=t.is_locked,
                best_answer_id=t.best_answer_id,
                ai_summary=t.ai_summary,
                is_liked=t.id in user_liked_topics,
                is_bookmarked=t.id in user_bookmarked_topics,
                created_at=t.created_at,
                updated_at=t.updated_at,
            )

        # Stats
        total_topics = (await db.execute(select(func.count(ForumTopic.id)))).scalar() or 0
        total_posts = (await db.execute(select(func.count(ForumPost.id)))).scalar() or 0

        return ForumHomeResponse(
            featured_destinations=featured_destinations,
            continent_regions=continent_regions,
            travel_topics=travel_topics,
            trending_topics=[map_topic(t) for t in trending_topics_raw],
            recent_topics=[map_topic(t) for t in recent_topics_raw],
            stats={"total_topics": total_topics, "total_posts": total_posts},
        )

    @staticmethod
    async def get_categories(
        db: AsyncSession,
        category_type: Optional[str] = None,
        parent_id: Optional[uuid.UUID] = None,
    ) -> List[ForumCategoryResponse]:
        """Fetch categories filtered by type or parent."""
        stmt = select(ForumCategory).options(selectinload(ForumCategory.subcategories))
        if category_type:
            stmt = stmt.where(ForumCategory.category_type == category_type)
        if parent_id:
            stmt = stmt.where(ForumCategory.parent_id == parent_id)
        stmt = stmt.order_by(ForumCategory.display_order.asc(), ForumCategory.name.asc())
        res = await db.execute(stmt)
        return [ForumCategoryResponse.model_validate(c) for c in res.scalars().all()]

    @staticmethod
    async def get_category(
        db: AsyncSession, category_id_or_slug: str
    ) -> Optional[ForumCategory]:
        """Lookup category by UUID or slug."""
        try:
            val_uuid = uuid.UUID(category_id_or_slug)
            stmt = select(ForumCategory).where(ForumCategory.id == val_uuid)
        except ValueError:
            stmt = select(ForumCategory).where(ForumCategory.slug == category_id_or_slug)
        stmt = stmt.options(selectinload(ForumCategory.subcategories))
        res = await db.execute(stmt)
        return res.scalars().first()

    @staticmethod
    async def get_topics(
        db: AsyncSession,
        category_id: Optional[uuid.UUID] = None,
        category_slug: Optional[str] = None,
        query: Optional[str] = None,
        sort_by: str = "recent",  # "recent", "trending", "unanswered"
        tag: Optional[str] = None,
        skip: int = 0,
        limit: int = 20,
        current_user_id: Optional[uuid.UUID] = None,
    ) -> List[ForumTopicResponse]:
        """Search and list topics with sorting & category filtering."""
        stmt = select(ForumTopic).options(
            selectinload(ForumTopic.category), selectinload(ForumTopic.user)
        )

        if category_id:
            stmt = stmt.where(ForumTopic.category_id == category_id)
        elif category_slug:
            stmt = stmt.join(ForumCategory).where(ForumCategory.slug == category_slug)

        if query:
            q_pattern = f"%{query.strip()}%"
            stmt = stmt.where(
                or_(ForumTopic.title.ilike(q_pattern), ForumTopic.content.ilike(q_pattern))
            )

        if sort_by == "trending":
            stmt = stmt.order_by(
                ForumTopic.is_pinned.desc(),
                desc(ForumTopic.views_count + (ForumTopic.likes_count * 5)),
                desc(ForumTopic.created_at),
            )
        elif sort_by == "unanswered":
            stmt = stmt.where(ForumTopic.replies_count == 0).order_by(
                ForumTopic.is_pinned.desc(), desc(ForumTopic.created_at)
            )
        else:  # recent
            stmt = stmt.order_by(ForumTopic.is_pinned.desc(), desc(ForumTopic.created_at))

        stmt = stmt.offset(skip).limit(limit)
        res = await db.execute(stmt)
        topics = res.scalars().all()

        user_liked_topics = set()
        user_bookmarked_topics = set()
        if current_user_id and topics:
            t_ids = [t.id for t in topics]
            likes_res = await db.execute(
                select(ForumLike.topic_id).where(
                    ForumLike.user_id == current_user_id, ForumLike.topic_id.in_(t_ids)
                )
            )
            user_liked_topics = set(likes_res.scalars().all())

            bm_res = await db.execute(
                select(ForumBookmark.topic_id).where(
                    ForumBookmark.user_id == current_user_id, ForumBookmark.topic_id.in_(t_ids)
                )
            )
            user_bookmarked_topics = set(bm_res.scalars().all())

        return [
            ForumTopicResponse(
                id=t.id,
                category_id=t.category_id,
                category_name=t.category.name if t.category else "",
                category_slug=t.category.slug if t.category else "",
                category_type=t.category.category_type if t.category else "destination",
                user_id=t.user_id,
                user_display_name=t.user.display_name if t.user else "Traveler",
                user_avatar_url=t.user.avatar_url if t.user else None,
                title=t.title,
                content=t.content,
                tags=t.tags or [],
                image_urls=t.image_urls or [],
                views_count=t.views_count,
                replies_count=t.replies_count,
                likes_count=t.likes_count,
                is_pinned=t.is_pinned,
                is_locked=t.is_locked,
                best_answer_id=t.best_answer_id,
                ai_summary=t.ai_summary,
                is_liked=t.id in user_liked_topics,
                is_bookmarked=t.id in user_bookmarked_topics,
                created_at=t.created_at,
                updated_at=t.updated_at,
            )
            for t in topics
        ]

    @staticmethod
    async def get_topic_detail(
        db: AsyncSession,
        topic_id: uuid.UUID,
        current_user_id: Optional[uuid.UUID] = None,
        increment_views: bool = True,
    ) -> Optional[ForumTopicDetailResponse]:
        """Fetch full topic with its responses stream."""
        stmt = (
            select(ForumTopic)
            .where(ForumTopic.id == topic_id)
            .options(
                selectinload(ForumTopic.category),
                selectinload(ForumTopic.user),
                selectinload(ForumTopic.posts).selectinload(ForumPost.user),
                selectinload(ForumTopic.posts).selectinload(ForumPost.replies).selectinload(ForumPost.user),
            )
        )
        res = await db.execute(stmt)
        topic = res.scalars().first()
        if not topic:
            return None

        if increment_views:
            topic.views_count += 1
            await db.commit()

        # User interactions
        is_liked = False
        is_bookmarked = False
        user_liked_posts = set()
        if current_user_id:
            like_res = await db.execute(
                select(ForumLike).where(
                    ForumLike.user_id == current_user_id, ForumLike.topic_id == topic.id
                )
            )
            is_liked = like_res.scalars().first() is not None

            bm_res = await db.execute(
                select(ForumBookmark).where(
                    ForumBookmark.user_id == current_user_id, ForumBookmark.topic_id == topic.id
                )
            )
            is_bookmarked = bm_res.scalars().first() is not None

            post_likes_res = await db.execute(
                select(ForumLike.post_id).where(
                    ForumLike.user_id == current_user_id, ForumLike.post_id != None
                )
            )
            user_liked_posts = set(post_likes_res.scalars().all())

        # Sort posts: best answer first, then chronological
        posts_sorted = sorted(
            [p for p in topic.posts if p.parent_post_id is None],
            key=lambda p: (not p.is_best_answer, p.created_at),
        )

        def map_post(p: ForumPost) -> ForumPostResponse:
            child_replies = [
                ForumPostResponse(
                    id=c.id,
                    topic_id=c.topic_id,
                    user_id=c.user_id,
                    user_display_name=c.user.display_name if c.user else "Traveler",
                    user_avatar_url=c.user.avatar_url if c.user else None,
                    parent_post_id=c.parent_post_id,
                    content=c.content,
                    image_urls=c.image_urls or [],
                    likes_count=c.likes_count,
                    is_best_answer=c.is_best_answer,
                    is_ai_generated=c.is_ai_generated,
                    is_liked=c.id in user_liked_posts,
                    created_at=c.created_at,
                    replies=[],
                )
                for c in (p.replies or [])
            ]
            return ForumPostResponse(
                id=p.id,
                topic_id=p.topic_id,
                user_id=p.user_id,
                user_display_name=p.user.display_name if p.user else "Traveler",
                user_avatar_url=p.user.avatar_url if p.user else None,
                parent_post_id=p.parent_post_id,
                content=p.content,
                image_urls=p.image_urls or [],
                likes_count=p.likes_count,
                is_best_answer=p.is_best_answer,
                is_ai_generated=p.is_ai_generated,
                is_liked=p.id in user_liked_posts,
                created_at=p.created_at,
                replies=child_replies,
            )

        return ForumTopicDetailResponse(
            id=topic.id,
            category_id=topic.category_id,
            category_name=topic.category.name if topic.category else "",
            category_slug=topic.category.slug if topic.category else "",
            category_type=topic.category.category_type if topic.category else "destination",
            user_id=topic.user_id,
            user_display_name=topic.user.display_name if topic.user else "Traveler",
            user_avatar_url=topic.user.avatar_url if topic.user else None,
            title=topic.title,
            content=topic.content,
            tags=topic.tags or [],
            image_urls=topic.image_urls or [],
            views_count=topic.views_count,
            replies_count=topic.replies_count,
            likes_count=topic.likes_count,
            is_pinned=topic.is_pinned,
            is_locked=topic.is_locked,
            best_answer_id=topic.best_answer_id,
            ai_summary=topic.ai_summary,
            is_liked=is_liked,
            is_bookmarked=is_bookmarked,
            created_at=topic.created_at,
            updated_at=topic.updated_at,
            posts=[map_post(p) for p in posts_sorted],
        )

    @staticmethod
    async def create_topic(
        db: AsyncSession, user: User, data: ForumTopicCreate
    ) -> ForumTopicResponse:
        """Create a new topic / question."""
        cat = await db.get(ForumCategory, data.category_id)
        if not cat:
            raise ValueError("Category not found")

        topic = ForumTopic(
            category_id=data.category_id,
            user_id=user.id,
            title=data.title.strip(),
            content=data.content.strip(),
            tags=data.tags,
            image_urls=data.image_urls,
        )
        db.add(topic)
        cat.topics_count += 1
        await db.commit()
        await db.refresh(topic)

        return ForumTopicResponse(
            id=topic.id,
            category_id=topic.category_id,
            category_name=cat.name,
            category_slug=cat.slug,
            category_type=cat.category_type,
            user_id=user.id,
            user_display_name=user.display_name,
            user_avatar_url=user.avatar_url,
            title=topic.title,
            content=topic.content,
            tags=topic.tags or [],
            image_urls=topic.image_urls or [],
            views_count=topic.views_count,
            replies_count=topic.replies_count,
            likes_count=topic.likes_count,
            is_pinned=topic.is_pinned,
            is_locked=topic.is_locked,
            best_answer_id=topic.best_answer_id,
            ai_summary=topic.ai_summary,
            is_liked=False,
            is_bookmarked=False,
            created_at=topic.created_at,
            updated_at=topic.updated_at,
        )

    @staticmethod
    async def create_post(
        db: AsyncSession, user: User, topic_id: uuid.UUID, data: ForumPostCreate
    ) -> ForumPostResponse:
        """Post a response or nested reply."""
        topic = await db.get(ForumTopic, topic_id)
        if not topic:
            raise ValueError("Topic not found")
        if topic.is_locked:
            raise ValueError("Topic is locked for replies")

        post = ForumPost(
            topic_id=topic_id,
            user_id=user.id,
            parent_post_id=data.parent_post_id,
            content=data.content.strip(),
            image_urls=data.image_urls,
        )
        db.add(post)
        topic.replies_count += 1
        topic.updated_at = datetime.now(timezone.utc)

        # Update category count
        cat = await db.get(ForumCategory, topic.category_id)
        if cat:
            cat.posts_count += 1

        await db.commit()
        await db.refresh(post)

        return ForumPostResponse(
            id=post.id,
            topic_id=post.topic_id,
            user_id=user.id,
            user_display_name=user.display_name,
            user_avatar_url=user.avatar_url,
            parent_post_id=post.parent_post_id,
            content=post.content,
            image_urls=post.image_urls or [],
            likes_count=0,
            is_best_answer=False,
            is_ai_generated=False,
            is_liked=False,
            created_at=post.created_at,
            replies=[],
        )

    @staticmethod
    async def toggle_topic_like(
        db: AsyncSession, user: User, topic_id: uuid.UUID
    ) -> Dict[str, Any]:
        """Upvote or remove upvote on a topic."""
        topic = await db.get(ForumTopic, topic_id)
        if not topic:
            raise ValueError("Topic not found")

        stmt = select(ForumLike).where(
            ForumLike.user_id == user.id, ForumLike.topic_id == topic_id
        )
        res = await db.execute(stmt)
        existing = res.scalars().first()

        if existing:
            await db.delete(existing)
            topic.likes_count = max(0, topic.likes_count - 1)
            is_liked = False
        else:
            db.add(ForumLike(user_id=user.id, topic_id=topic_id))
            topic.likes_count += 1
            is_liked = True

        await db.commit()
        return {"is_liked": is_liked, "likes_count": topic.likes_count}

    @staticmethod
    async def toggle_post_like(
        db: AsyncSession, user: User, post_id: uuid.UUID
    ) -> Dict[str, Any]:
        """Upvote or remove upvote on a reply."""
        post = await db.get(ForumPost, post_id)
        if not post:
            raise ValueError("Post not found")

        stmt = select(ForumLike).where(
            ForumLike.user_id == user.id, ForumLike.post_id == post_id
        )
        res = await db.execute(stmt)
        existing = res.scalars().first()

        if existing:
            await db.delete(existing)
            post.likes_count = max(0, post.likes_count - 1)
            is_liked = False
        else:
            db.add(ForumLike(user_id=user.id, post_id=post_id))
            post.likes_count += 1
            is_liked = True

        await db.commit()
        return {"is_liked": is_liked, "likes_count": post.likes_count}

    @staticmethod
    async def toggle_bookmark(
        db: AsyncSession, user: User, topic_id: uuid.UUID
    ) -> Dict[str, Any]:
        """Save or unsave topic to bookmarks."""
        stmt = select(ForumBookmark).where(
            ForumBookmark.user_id == user.id, ForumBookmark.topic_id == topic_id
        )
        res = await db.execute(stmt)
        existing = res.scalars().first()

        if existing:
            await db.delete(existing)
            is_bookmarked = False
        else:
            db.add(ForumBookmark(user_id=user.id, topic_id=topic_id))
            is_bookmarked = True

        await db.commit()
        return {"is_bookmarked": is_bookmarked}

    @staticmethod
    async def set_best_answer(
        db: AsyncSession, user: User, topic_id: uuid.UUID, post_id: uuid.UUID
    ) -> Dict[str, Any]:
        """Mark post as best answer (only topic author or admin)."""
        topic = await db.get(ForumTopic, topic_id)
        if not topic:
            raise ValueError("Topic not found")
        if topic.user_id != user.id:
            raise PermissionError("Only the topic author can select the best answer")

        # Reset any previous best answer
        await db.execute(
            update(ForumPost)
            .where(ForumPost.topic_id == topic_id)
            .values(is_best_answer=False)
        )

        post = await db.get(ForumPost, post_id)
        if not post or post.topic_id != topic_id:
            raise ValueError("Post not found in this topic")

        post.is_best_answer = True
        topic.best_answer_id = post_id
        await db.commit()
        return {"success": True, "best_answer_id": str(post_id)}
