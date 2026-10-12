import uuid
import secrets
from typing import List, Literal, Optional
from datetime import datetime, timezone, date, time, timedelta
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Depends, Header, HTTPException, status, Query, BackgroundTasks
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, text

from app.core.database import get_db
from app.core.config import settings
from app.core.security import create_access_token, decode_token
from app.services.user_service import UserService
from app.services.attraction_service import AttractionService
from app.services.settings_service import SettingsService
from app.services import excluded_keyword_service
from app.services.providers import config as provider_config
from app.schemas.user import UserResponse
from app.schemas.attraction import AttractionResponse, AttractionListResponse, AttractionCreate
from app.schemas.excluded_keyword import ExcludedKeywordResponse, ExcludedKeywordCreate
from app.models.user import User
from app.models.attraction import Attraction
from app.models.experience import ExperienceEnquiry
from app.models.telemetry import ApiAlert

router = APIRouter(prefix="/admin", tags=["Admin REST API"])

# The dashboard counts days and months in Sri Lanka time, like its chart labels.
DASHBOARD_TZ_NAME = "Asia/Colombo"
DASHBOARD_TZ = ZoneInfo(DASHBOARD_TZ_NAME)


# --- Request/Response Schemas ---

class AdminLoginRequest(BaseModel):
    username: str
    password: str

class AdminLoginResponse(BaseModel):
    token: str

class MonthlySignups(BaseModel):
    month: str  # YYYY-MM, Sri Lanka time
    signups: int

class AdminDashboardStats(BaseModel):
    explorers_count: int
    new_explorers_7d: int
    attractions_count: int
    new_attractions_7d: int
    pending_approvals_count: int
    open_api_alerts: int
    critical_api_alerts: int
    new_enquiries: int
    explorer_growth: List[MonthlySignups]
    recent_activity: List[dict]

class ApiOperationUsage(BaseModel):
    operation: str
    calls: int
    requests: int
    est_cost_usd: float

class ApiProviderUsage(BaseModel):
    provider: str
    calls: int          # requests that reached the provider (what it bills)
    requests: int       # calls plus the requests our caches answered
    prev_calls: int     # calls in the preceding window of the same length
    est_cost_usd: float
    daily_calls: List[int]
    operations: List[ApiOperationUsage]

class DashboardApiUsage(BaseModel):
    days: List[date]
    providers: List[ApiProviderUsage]
    generated_at: datetime

class AnnouncementRequest(BaseModel):
    title: str
    message: str
    target_plan: str

class SettingsResponse(BaseModel):
    platform_name: str
    contact_email: str
    google_maps_api_key: str
    mapbox_access_token: str
    gemini_api_key: str
    geoapify_api_key: str
    default_geofence_radius: str
    unsplash_api_key: str
    serpapi_key: str = ""
    # Travel-data providers (see app/services/providers/config.py).
    travelpayouts_api_token: str = ""
    travelpayouts_marker: str = ""
    travelpayouts_project_id: str = ""
    gettransfer_api_token: str = ""
    provider_mode_gettransfer: str = "off"
    provider_mode_airalo: str = "off"
    provider_mode_wegotrip: str = "off"
    provider_mode_aviasales: str = "off"
    provider_mode_klook: str = "off"
    provider_mode_gocity: str = "off"
    provider_mode_kiwi: str = "off"
    provider_mode_atlas: str = "off"
    atlas_key_id: str = ""
    atlas_signing_secret: str = ""

ProviderMode = Literal["off", "shadow", "live"]

class SettingsUpdateRequest(BaseModel):
    platform_name: Optional[str] = None
    contact_email: Optional[str] = None
    google_maps_api_key: Optional[str] = None
    mapbox_access_token: Optional[str] = None
    gemini_api_key: Optional[str] = None
    geoapify_api_key: Optional[str] = None
    default_geofence_radius: Optional[str] = None
    unsplash_api_key: Optional[str] = None
    serpapi_key: Optional[str] = None
    travelpayouts_api_token: Optional[str] = None
    travelpayouts_marker: Optional[str] = None
    travelpayouts_project_id: Optional[str] = None
    gettransfer_api_token: Optional[str] = None
    atlas_key_id: Optional[str] = None
    atlas_signing_secret: Optional[str] = None
    provider_mode_gettransfer: Optional[ProviderMode] = None
    provider_mode_airalo: Optional[ProviderMode] = None
    provider_mode_wegotrip: Optional[ProviderMode] = None
    provider_mode_aviasales: Optional[ProviderMode] = None
    provider_mode_klook: Optional[ProviderMode] = None
    provider_mode_gocity: Optional[ProviderMode] = None
    provider_mode_kiwi: Optional[ProviderMode] = None
    provider_mode_atlas: Optional[ProviderMode] = None


# --- Dependency to protect admin routes ---

async def verify_admin_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header. Must be Bearer <token>"
        )
    token = authorization.split(" ")[1]
    payload = decode_token(token)
    if not payload or payload.get("role") != "admin":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Access Denied: Invalid or expired admin credentials."
        )
    return token


# --- Endpoints ---

@router.post("/login", response_model=AdminLoginResponse)
async def admin_login(data: AdminLoginRequest):
    """Log in as admin and return a signed JWT token."""
    username_valid = secrets.compare_digest(data.username, settings.ADMIN_USERNAME)
    password_valid = secrets.compare_digest(data.password, settings.ADMIN_PASSWORD)

    if username_valid and password_valid:
        token = create_access_token({"sub": data.username, "role": "admin"})
        return AdminLoginResponse(token=token)

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Access Denied: Invalid credentials."
    )


@router.get("/dashboard", response_model=AdminDashboardStats)
async def get_dashboard_stats(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Headline counts, monthly signups and recent activity for the dashboard.

    API usage has its own endpoint (/dashboard/api-usage) so that card can
    refresh on its own.
    """
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)

    # 1. Explorers, and how many joined this week
    explorers_count = (await db.execute(select(func.count(User.id)))).scalar_one()
    new_explorers_7d = (await db.execute(
        select(func.count(User.id)).where(User.created_at >= week_ago)
    )).scalar_one()

    # 2. Attractions (all), and how many were added this week
    attractions_count = (await db.execute(select(func.count(Attraction.id)))).scalar_one()
    new_attractions_7d = (await db.execute(
        select(func.count(Attraction.id)).where(Attraction.created_at >= week_ago)
    )).scalar_one()

    # 3. Pending approvals (inactive attractions), the same set /approvals lists
    pending_approvals_count = (await db.execute(
        select(func.count(Attraction.id)).where(Attraction.is_active == False)
    )).scalar_one()

    # 4. What needs a person: unacknowledged API alerts and unanswered enquiries
    alerts = (await db.execute(
        select(func.count(ApiAlert.id), func.count(ApiAlert.id).filter(ApiAlert.severity == "critical"))
        .where(ApiAlert.acknowledged_at.is_(None))
    )).one()
    new_enquiries = (await db.execute(
        select(func.count(ExperienceEnquiry.id)).where(ExperienceEnquiry.status == "new")
    )).scalar_one()

    # 5. Signups per month for the last 12 months, in Sri Lanka time
    now_local = datetime.now(DASHBOARD_TZ)
    months = []
    year, month = now_local.year, now_local.month
    for _i in range(12):
        months.append(f"{year:04d}-{month:02d}")
        year, month = (year, month - 1) if month > 1 else (year - 1, 12)
    months.reverse()
    first_month = datetime(int(months[0][:4]), int(months[0][5:]), 1, tzinfo=DASHBOARD_TZ)
    signup_rows = await db.execute(text("""
        SELECT to_char(created_at AT TIME ZONE :tz, 'YYYY-MM') AS month, count(*) AS signups
        FROM users
        WHERE created_at >= :start
        GROUP BY 1
    """), {"tz": DASHBOARD_TZ_NAME, "start": first_month})
    signups_by_month = {row.month: row.signups for row in signup_rows}
    explorer_growth = [
        MonthlySignups(month=m, signups=signups_by_month.get(m, 0)) for m in months
    ]

    # 6. Recent Activity list
    # Query last 5 users
    recent_users_stmt = select(User).order_by(desc(User.created_at)).limit(5)
    recent_users_res = await db.execute(recent_users_stmt)
    recent_users = recent_users_res.scalars().all()

    # Query last 5 attractions
    recent_attractions_stmt = select(Attraction).order_by(desc(Attraction.created_at)).limit(5)
    recent_attractions_res = await db.execute(recent_attractions_stmt)
    recent_attractions = recent_attractions_res.scalars().all()

    # Merge and format activity items
    activity_items = []
    
    # Process users activity
    for user in recent_users:
        activity_items.append({
            "color": "#10b981" if user.is_verified else "#f59e0b",
            "text": f"{user.display_name} ({user.email}) registered as an explorer.",
            "time": user.created_at.isoformat() if user.created_at else datetime.now(timezone.utc).isoformat(),
            "timestamp": user.created_at.timestamp() if user.created_at else 0.0
        })

    # Process attractions activity
    for attr in recent_attractions:
        activity_items.append({
            "color": "#6c63ff" if attr.is_active else "#ef4444",
            "text": f"New attraction suggested: '{attr.name}' at {attr.address or 'unknown address'}.",
            "time": attr.created_at.isoformat() if attr.created_at else datetime.now(timezone.utc).isoformat(),
            "timestamp": attr.created_at.timestamp() if attr.created_at else 0.0
        })

    # Sort consolidated activity by timestamp descending
    activity_items.sort(key=lambda x: x["timestamp"], reverse=True)
    recent_activity = activity_items[:6]  # Top 6 latest activities

    return AdminDashboardStats(
        explorers_count=explorers_count,
        new_explorers_7d=new_explorers_7d,
        attractions_count=attractions_count,
        new_attractions_7d=new_attractions_7d,
        pending_approvals_count=pending_approvals_count,
        open_api_alerts=alerts[0],
        critical_api_alerts=alerts[1],
        new_enquiries=new_enquiries,
        explorer_growth=explorer_growth,
        recent_activity=recent_activity,
    )


@router.get("/dashboard/api-usage", response_model=DashboardApiUsage)
async def get_dashboard_api_usage(
    days: int = Query(7, ge=1, le=31),
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Third-party API calls per provider per Sri Lanka day, from api_events.

    Covers the last `days` days including today, plus the window before it for
    the change figure. `internal` events are Google Places requests our own
    caches answered (photos, nearby, search, details), so they count as Google
    Maps requests that never became calls.
    """
    today = datetime.now(DASHBOARD_TZ).date()
    day_list = [today - timedelta(days=i) for i in range(days - 1, -1, -1)]
    start = datetime.combine(day_list[0], time.min, tzinfo=DASHBOARD_TZ)
    prev_start = start - timedelta(days=days)

    rows = (await db.execute(text("""
        SELECT CASE WHEN provider = 'internal' THEN 'google_maps' ELSE provider END AS provider,
               operation,
               (ts AT TIME ZONE :tz)::date AS day,
               count(*) FILTER (WHERE served_from = 'upstream') AS calls,
               count(*) AS requests,
               COALESCE(sum(est_cost_usd), 0) AS cost
        FROM api_events
        WHERE ts >= :prev_start
        GROUP BY 1, 2, 3
    """), {"tz": DASHBOARD_TZ_NAME, "prev_start": prev_start})).mappings().all()

    day_index = {d: i for i, d in enumerate(day_list)}
    by_provider: dict = {}
    for row in rows:
        p = by_provider.setdefault(row["provider"], {
            "calls": 0, "requests": 0, "prev_calls": 0, "cost": 0.0,
            "daily": [0] * days, "ops": {},
        })
        i = day_index.get(row["day"])
        if i is None:  # the preceding window
            p["prev_calls"] += row["calls"]
            continue
        cost = float(row["cost"])
        p["calls"] += row["calls"]
        p["requests"] += row["requests"]
        p["cost"] += cost
        p["daily"][i] += row["calls"]
        op = p["ops"].setdefault(row["operation"], {"calls": 0, "requests": 0, "cost": 0.0})
        op["calls"] += row["calls"]
        op["requests"] += row["requests"]
        op["cost"] += cost

    providers = [
        ApiProviderUsage(
            provider=name,
            calls=p["calls"],
            requests=p["requests"],
            prev_calls=p["prev_calls"],
            est_cost_usd=round(p["cost"], 4),
            daily_calls=p["daily"],
            operations=sorted(
                (ApiOperationUsage(operation=op_name, calls=op["calls"], requests=op["requests"],
                                   est_cost_usd=round(op["cost"], 4))
                 for op_name, op in p["ops"].items()),
                key=lambda o: (o.calls, o.requests), reverse=True,
            ),
        )
        for name, p in by_provider.items()
    ]
    providers.sort(key=lambda p: (p.calls, p.requests), reverse=True)

    return DashboardApiUsage(
        days=day_list, providers=providers, generated_at=datetime.now(timezone.utc)
    )


@router.get("/users")
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    status: Optional[str] = Query(None, description="Filter by account status: active, suspended, or all"),
    verification: Optional[str] = Query(None, description="Filter by verification: verified, unverified, or all"),
    date_filter: Optional[str] = Query(None, description="Filter by join date: today, this_week, this_month, custom, or all"),
    start_from: Optional[str] = Query(None, description="Start date from (YYYY-MM-DD)"),
    end_to: Optional[str] = Query(None, description="End date to (YYYY-MM-DD)"),
    sort_order: Optional[str] = Query("desc", description="Sort order: desc (newest first) or asc (oldest first)"),
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Retrieve users for management with optional filters."""
    service = UserService(db)
    users, total = await service.list_users(
        page=page, 
        page_size=page_size, 
        search_query=search,
        status=status,
        verification=verification,
        date_filter=date_filter,
        start_from=start_from,
        end_to=end_to,
        sort_order=sort_order
    )
    return {
        "users": [UserResponse.model_validate(u) for u in users],
        "total": total,
        "page": page,
        "page_size": page_size
    }


@router.post("/users/{user_id}/verify", response_model=UserResponse)
async def verify_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Verify an explorer user."""
    service = UserService(db)
    return await service.verify_user(user_id)


@router.post("/users/{user_id}/toggle-active", response_model=UserResponse)
async def toggle_user_active(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Toggle a user's active/suspended status."""
    service = UserService(db)
    return await service.toggle_active_status(user_id)


@router.get("/approvals", response_model=AttractionListResponse)
async def get_pending_approvals(
    page: int = Query(1, ge=1),
    page_size: int = Query(100, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Get all attractions awaiting approval."""
    service = AttractionService(db)
    return await service.list_attractions(
        page=page,
        page_size=page_size,
        is_active=False
    )


@router.get("/attractions", response_model=AttractionListResponse)
async def list_admin_attractions(
    page: int = Query(1, ge=1),
    page_size: int = Query(1000, ge=1, le=1000),
    search: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Retrieve all attractions for admin management (includes inactive/active ones)."""
    service = AttractionService(db)
    return await service.list_attractions(page=page, page_size=page_size, search_query=search)


@router.post("/attractions", response_model=AttractionResponse, status_code=status.HTTP_201_CREATED)
async def create_admin_attraction(
    data: AttractionCreate,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Create a new attraction as admin."""
    service = AttractionService(db)
    return await service.create_attraction(data)


@router.delete("/attractions/{attraction_id}")
async def delete_admin_attraction(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Delete an attraction as admin."""
    service = AttractionService(db)
    success = await service.delete_attraction(attraction_id)
    return {"status": "success" if success else "failed"}


@router.put("/attractions/{attraction_id}", response_model=AttractionResponse)
async def update_attraction_details(
    attraction_id: uuid.UUID,
    data: AttractionCreate,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Update attraction details like coordinates, name, category, and address."""
    service = AttractionService(db)
    update_data = data.model_dump(exclude_unset=True)
    return await service.update_attraction(attraction_id, update_data)


@router.post("/attractions/{attraction_id}/approve", response_model=AttractionResponse)
async def approve_attraction(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Approve a submitted attraction by turning on is_active."""
    service = AttractionService(db)
    return await service.update_attraction(attraction_id, {"is_active": True})


@router.delete("/attractions/{attraction_id}/reject")
async def reject_attraction(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Reject and delete a submitted attraction."""
    service = AttractionService(db)
    success = await service.delete_attraction(attraction_id)
    return {"status": "success" if success else "failed"}


@router.get("/excluded-keywords", response_model=List[ExcludedKeywordResponse])
async def list_excluded_keywords(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Keywords that hide a matching place from the Around You cards."""
    return await excluded_keyword_service.list_all(db)


@router.post("/excluded-keywords", response_model=ExcludedKeywordResponse, status_code=status.HTTP_201_CREATED)
async def create_excluded_keyword(
    data: ExcludedKeywordCreate,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Add a keyword. Matches whole-word, case-insensitive, against a place's name."""
    try:
        return await excluded_keyword_service.create(db, data)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.delete("/excluded-keywords/{keyword_id}")
async def delete_excluded_keyword(
    keyword_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Remove a keyword, so matching places show in Around You again."""
    success = await excluded_keyword_service.delete(db, keyword_id)
    return {"status": "success" if success else "failed"}


@router.get("/payments")
async def get_payments_data(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Mock/Real dashboard data for payment plans."""
    # Query total users to split plans proportionally
    user_count_stmt = select(func.count(User.id))
    user_count_res = await db.execute(user_count_stmt)
    explorers_count = user_count_res.scalar_one_or_none() or 0

    pro_count = int(explorers_count * 0.3)
    annual_count = int(explorers_count * 0.1)
    free_count = explorers_count - pro_count - annual_count

    mock_transactions = [
        {"id": "TRX-98234", "user": "Alex Smith", "plan": "Pro Explorer", "amount": 9.99, "status": "Completed", "date": "Oct 24, 2024"},
        {"id": "TRX-98233", "user": "Sarah Jones", "plan": "Pro Explorer", "amount": 9.99, "status": "Completed", "date": "Oct 24, 2024"},
        {"id": "TRX-98232", "user": "Mike Brown", "plan": "Annual Pass", "amount": 89.99, "status": "Completed", "date": "Oct 23, 2024"},
        {"id": "TRX-98231", "user": "Emma Davis", "plan": "Pro Explorer", "amount": 9.99, "status": "Failed", "date": "Oct 23, 2024"},
        {"id": "TRX-98230", "user": "James Wilson", "plan": "Pro Explorer", "amount": 9.99, "status": "Completed", "date": "Oct 22, 2024"},
        {"id": "TRX-98229", "user": "Olivia Lee", "plan": "Annual Pass", "amount": 89.99, "status": "Refunded", "date": "Oct 22, 2024"},
    ]

    plans = [
        {"name": "Free", "users": free_count, "price": "$0", "color": "#94a3b8"},
        {"name": "Pro Explorer", "users": pro_count, "price": "$9.99/mo", "color": "#6c63ff"},
        {"name": "Annual Pass", "users": annual_count, "price": "$89.99/yr", "color": "#10b981"},
    ]

    return {
        "mrr": 4520.00,
        "subscribers_count": pro_count + annual_count,
        "churn_rate": "2.4%",
        "arpu": "$8.56",
        "plans": plans,
        "transactions": mock_transactions
    }


@router.get("/engagement")
async def get_engagement_data(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Real engagement indicators (DAU, avg session length, places visited),
    computed from tracked activity — see engagement_service."""
    from app.services import engagement_service
    return await engagement_service.get_engagement_stats(db)


@router.post("/engagement/announcements")
async def post_system_announcement(
    data: AnnouncementRequest,
    background: BackgroundTasks,
    _ = Depends(verify_admin_token)
):
    """Send a real broadcast: a push notification (FCM) AND an in-app bell-icon
    message to every targeted user. Delivery runs in the background so the admin
    gets an instant response; final delivery counts show in Broadcast History."""
    if not (data.title or "").strip() or not (data.message or "").strip():
        raise HTTPException(status_code=400, detail="Title and message are required")
    from app.services import broadcast_service
    background.add_task(
        broadcast_service.send_broadcast,
        title=data.title.strip(),
        body=data.message.strip(),
        target_audience=data.target_plan or "all",
    )
    return {
        "status": "queued",
        "message": "Broadcast is being delivered to your audience.",
    }


@router.get("/engagement/broadcasts")
async def list_broadcasts(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Broadcast History — past sends with their real delivery counts."""
    from app.models.notification import Broadcast
    res = await db.execute(
        select(Broadcast).order_by(desc(Broadcast.created_at)).limit(50)
    )
    return [
        {
            "id": str(b.id),
            "title": b.title,
            "body": b.body,
            "target_audience": b.target_audience,
            "recipients_count": b.recipients_count,
            "devices_sent": b.devices_sent,
            "devices_failed": b.devices_failed,
            "status": b.status,
            "created_at": b.created_at.isoformat(),
        }
        for b in res.scalars().all()
    ]


@router.get("/engagement/broadcasts/{broadcast_id}/recipients")
async def broadcast_recipients(
    broadcast_id: str,
    search: Optional[str] = Query(None, description="Filter by user name or email"),
    status_filter: Optional[str] = Query(None, alias="status", description="sent|failed|no_token"),
    limit: int = Query(200, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Per-recipient delivery breakdown for one broadcast, with user search.

    Powers the admin's broadcast-detail popup: who received the push, who
    failed, and who had no device registered."""
    from app.models.notification import Notification

    try:
        bid = uuid.UUID(broadcast_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid broadcast id")

    # Summary counts by push_status over ALL recipients (ignores the search box).
    summary_rows = await db.execute(
        select(Notification.push_status, func.count(Notification.id))
        .where(Notification.broadcast_id == bid)
        .group_by(Notification.push_status)
    )
    counts = {"sent": 0, "failed": 0, "no_token": 0, "pending": 0}
    for st, n in summary_rows.all():
        counts[st or "pending"] = n
    total = sum(counts.values())

    # Recipient list = notifications joined to users, with optional filters.
    q = (
        select(
            User.id, User.display_name, User.email,
            Notification.push_status, Notification.is_read,
        )
        .join(Notification, Notification.user_id == User.id)
        .where(Notification.broadcast_id == bid)
    )
    if status_filter in ("sent", "failed", "no_token", "pending"):
        q = q.where(Notification.push_status == status_filter)
    if search and search.strip():
        like = f"%{search.strip()}%"
        q = q.where(User.display_name.ilike(like) | User.email.ilike(like))
    q = q.order_by(Notification.push_status, User.email).limit(limit)

    rows = await db.execute(q)
    recipients = [
        {
            "user_id": str(uid),
            "name": name or "—",
            "email": email,
            "push_status": st or "pending",
            "is_read": bool(is_read),
        }
        for uid, name, email, st, is_read in rows.all()
    ]

    return {
        "broadcast_id": str(bid),
        "total_recipients": total,
        "summary": counts,
        "recipients": recipients,
    }


# Travel-data provider settings, with the description stored beside each.
_PROVIDER_SETTINGS = {
    provider_config.TRAVELPAYOUTS_API_TOKEN: "Travelpayouts API token (Aviasales flight data)",
    provider_config.TRAVELPAYOUTS_MARKER: "Travelpayouts partner ID stamped on affiliate links",
    provider_config.TRAVELPAYOUTS_PROJECT_ID: "Travelpayouts Project ID (trs) that affiliate links are credited to",
    provider_config.GETTRANSFER_API_TOKEN: "GetTransfer API token (issued by Travelpayouts support)",
    provider_config.ATLAS_KEY_ID: "HelloSafe Atlas key ID (ak_test_... or ak_live_...)",
    provider_config.ATLAS_SIGNING_SECRET: "HelloSafe Atlas signing secret (server-side only)",
    **{
        provider_config.mode_key(p): f"{p} data in Odyssey plans: off | shadow | live"
        for p in provider_config.PROVIDERS
    },
}


async def _provider_settings(service: SettingsService) -> dict:
    values = {key: await service.get_setting(key, "") for key in _PROVIDER_SETTINGS}
    for key in provider_config.MODE_KEYS:
        if values[key] not in provider_config.MODES:
            values[key] = provider_config.OFF
    return values


@router.get("/settings", response_model=SettingsResponse)
async def get_admin_settings(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Retrieve current platform settings and API keys."""
    service = SettingsService(db)
    return SettingsResponse(
        platform_name=await service.get_setting("platform_name", "NexARound"),
        contact_email=await service.get_setting("contact_email", "support@nexaround.com"),
        google_maps_api_key=await service.get_setting("google_maps_api_key", ""),
        mapbox_access_token=await service.get_setting("mapbox_access_token", ""),
        gemini_api_key=await service.get_setting("gemini_api_key", ""),
        geoapify_api_key=await service.get_setting("geoapify_api_key", ""),
        default_geofence_radius=await service.get_setting("default_geofence_radius", "100"),
        unsplash_api_key=await service.get_setting("unsplash_api_key", ""),
        serpapi_key=await service.get_setting("serpapi_key", ""),
        **await _provider_settings(service),
    )


@router.put("/settings", response_model=SettingsResponse)
async def update_admin_settings(
    data: SettingsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Update platform settings and API keys."""
    service = SettingsService(db)
    if data.platform_name is not None:
        await service.set_setting("platform_name", data.platform_name, "Platform display name")
    if data.contact_email is not None:
        await service.set_setting("contact_email", data.contact_email, "Support contact email")
    if data.google_maps_api_key is not None:
        await service.set_setting("google_maps_api_key", data.google_maps_api_key, "Google Maps API Key")
    if data.mapbox_access_token is not None:
        await service.set_setting("mapbox_access_token", data.mapbox_access_token, "Mapbox Public Access Token")
    if data.gemini_api_key is not None:
        await service.set_setting("gemini_api_key", data.gemini_api_key, "Gemini Generative AI Key")
    if data.geoapify_api_key is not None:
        await service.set_setting("geoapify_api_key", data.geoapify_api_key, "Geoapify Geocoding API Key")
    if data.default_geofence_radius is not None:
        await service.set_setting("default_geofence_radius", data.default_geofence_radius, "Default Geofence Radius in meters")
    if data.unsplash_api_key is not None:
        await service.set_setting("unsplash_api_key", data.unsplash_api_key, "Unsplash API Access Key")
    if data.serpapi_key is not None:
        await service.set_setting("serpapi_key", data.serpapi_key, "SerpApi Key for Live Google Flight & Hotel Search")
    provider_changed = False
    for key, description in _PROVIDER_SETTINGS.items():
        value = getattr(data, key)
        if value is not None:
            await service.set_setting(key, value.strip(), description)
            provider_changed = True
    if provider_changed:
        # This process sees it now; the Odyssey worker within a minute.
        await provider_config.refresh()

    return SettingsResponse(
        platform_name=await service.get_setting("platform_name", "NexARound"),
        contact_email=await service.get_setting("contact_email", "support@nexaround.com"),
        google_maps_api_key=await service.get_setting("google_maps_api_key", ""),
        mapbox_access_token=await service.get_setting("mapbox_access_token", ""),
        gemini_api_key=await service.get_setting("gemini_api_key", ""),
        geoapify_api_key=await service.get_setting("geoapify_api_key", ""),
        default_geofence_radius=await service.get_setting("default_geofence_radius", "100"),
        unsplash_api_key=await service.get_setting("unsplash_api_key", ""),
        serpapi_key=await service.get_setting("serpapi_key", ""),
        **await _provider_settings(service),
    )
