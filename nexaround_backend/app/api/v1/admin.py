import uuid
import secrets
from typing import List, Literal, Optional
from datetime import datetime, timezone, date, time, timedelta
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status, Query, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, text, or_

from app.core.database import get_db
from app.core.config import settings
from app.core.rate_limiter import auth_rate_limiter
from app.core.security import create_access_token, decode_token
from app.services import audit, creator_auth, fx_service, neva_voice
from app.services.user_service import UserService
from app.services.settings_service import SettingsService
from app.services.experience_format import COUNTRY_MODE_KEY, parse_country_mode
from app.services.official_stories import OFFICIAL_USER_ID
from app.services import excluded_keyword_service
from app.services.providers import config as provider_config
from app.schemas.user import UserResponse
from app.schemas.excluded_keyword import ExcludedKeywordResponse, ExcludedKeywordCreate
from app.models.user import User
from app.models.attraction import Attraction
from app.models.experience import ExperienceEnquiry, ExperienceVendor
from app.models.telemetry import ApiAlert
from app.models.audit import AuditEvent, AuthSession
from app.schemas.audit import (
    AuditEventOut, AuditListResponse, AuditStats, SessionListResponse, SessionOut,
)
from app.services import partner_events

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
    # "admin", or "creator" for a City Tours writer (creator_auth), whose
    # panel shows City Tours only.
    role: str = "admin"

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

class ActivityBucket(BaseModel):
    start: date         # first Sri Lanka day of the day, week (Monday) or month
    active: int         # explorers active in it
    new: int            # of those, how many signed up in it
    sessions: int       # app sessions the app reported
    app_seconds: int    # time in the app across those sessions

class FrequentExplorer(BaseModel):
    id: uuid.UUID
    display_name: str
    email: str
    avatar_url: Optional[str] = None
    active_periods: int  # days, weeks or months active in the view's window
    sessions: int
    app_seconds: int
    last_active_at: datetime

class ActivityView(BaseModel):
    buckets: List[ActivityBucket]
    top: List[FrequentExplorer]

class ExplorerActivity(BaseModel):
    today: int
    yesterday: int
    last_7d: int
    prev_7d: int
    last_30d: int
    prev_30d: int
    avg_daily_30d: float
    regulars_30d: int    # active on `regular_days` or more of the last 30 days
    regular_days: int
    daily: ActivityView
    weekly: ActivityView
    monthly: ActivityView
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
    # True: Experiences are browsed by country. False: nearest first.
    experiences_country_mode: bool = True
    # ExchangeRate-API key for the daily currency rates (fx_service).
    exchangerate_api_key: str = ""
    # Neva's spoken replies (neva_voice).
    neva_voice_enabled: bool = True
    neva_voice_daily_seconds: int = neva_voice.DEFAULT_DAILY_SECONDS
    google_tts_api_key: str = ""

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
    experiences_country_mode: Optional[bool] = None
    exchangerate_api_key: Optional[str] = None
    neva_voice_enabled: Optional[bool] = None
    neva_voice_daily_seconds: Optional[int] = Field(None, ge=0, le=86400)
    google_tts_api_key: Optional[str] = None


# --- Dependency to protect admin routes ---

async def verify_admin_token(request: Request, authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header. Must be Bearer <token>"
        )
    token = authorization.split(" ")[1]
    payload = decode_token(token)
    denied = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Access Denied: Invalid or expired admin credentials."
    )
    if not payload or payload.get("role") != "admin":
        raise denied

    # The sign-in must still be live: signing a device out from Sessions works
    # by revoking this row, and a token with no `sid` is refused outright.
    username = payload.get("sub") or "admin"
    meta = audit.client_meta(request)
    if not await audit.session_is_live(
        payload.get("sid"), actor_type="admin", actor_id=username, ip=meta["ip"],
    ):
        raise denied
    audit.set_actor(
        request, actor_type="admin", actor_id=username, actor_label=username,
        session_id=payload["sid"],
    )
    return token


async def require_admin(token: str = Depends(verify_admin_token)) -> str:
    """The signed-in admin's login name, for "reviewed by" trails. Admins are
    not rows in `users`, so the name is all there is."""
    return (decode_token(token) or {}).get("sub") or "admin"


# --- Endpoints ---

@router.post("/login", response_model=AdminLoginResponse)
async def admin_login(
    data: AdminLoginRequest, request: Request, _=Depends(auth_rate_limiter),
):
    """Log in as admin and return a signed JWT token."""
    username_valid = secrets.compare_digest(data.username, settings.ADMIN_USERNAME)
    password_valid = secrets.compare_digest(data.password, settings.ADMIN_PASSWORD)
    meta = audit.client_meta(request)

    if username_valid and password_valid:
        sid = await audit.start_session(
            actor_type="admin", actor_id=data.username, actor_label=data.username,
            request=request, ttl=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        )
        await audit.record(
            actor_type="admin", actor_id=data.username, actor_label=data.username,
            session_id=sid, category="auth", action="auth.login",
            summary=f"Signed in from {audit.describe_device(meta['browser'], meta['os'])}",
            method="POST", route="/api/v1/admin/login", status_code=200, meta=meta,
        )
        token = create_access_token(
            {"sub": data.username, "role": "admin", "sid": str(sid)}
        )
        return AdminLoginResponse(token=token)

    # Not the admin: a City Tours content creator signs in with their email.
    creator, reason = (None, "wrong password") if username_valid else await creator_auth.sign_in(
        data.username, data.password,
    )
    if creator is not None:
        label = creator.name
        sid = await audit.start_session(
            actor_type=creator_auth.ACTOR, actor_id=str(creator.id), actor_label=label,
            request=request, ttl=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        )
        await audit.record(
            actor_type=creator_auth.ACTOR, actor_id=str(creator.id), actor_label=label,
            session_id=sid, category="auth", action="auth.login",
            summary=f"Signed in from {audit.describe_device(meta['browser'], meta['os'])}",
            method="POST", route="/api/v1/admin/login", status_code=200, meta=meta,
        )
        token = create_access_token({
            "sub": str(creator.id), "role": creator_auth.ROLE, "sid": str(sid), "name": label,
        })
        return AdminLoginResponse(token=token, role=creator_auth.ROLE)

    # The attempted name is kept (it is the one thing that says whether someone
    # is guessing the real username); the password never is.
    await audit.record(
        actor_type="anonymous", actor_id=None, actor_label=data.username[:255],
        category="auth", action="auth.login_failed",
        summary="Failed admin sign-in",
        method="POST", route="/api/v1/admin/login", status_code=401,
        success=False, meta=meta,
        detail={"reason": reason},
    )
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Access Denied: Invalid credentials."
    )


@router.post("/logout")
async def admin_logout(request: Request, authorization: str = Header(...)):
    """End this device's session, so the token stops working immediately.

    Content creators sign out here too: same panel, their own session rows.
    """
    token = authorization.split(" ")[1] if authorization.startswith("Bearer ") else ""
    payload = decode_token(token) or {}
    creator = await creator_auth.from_token(payload, request)
    if creator is not None:
        actor_type, actor_id, label = creator_auth.ACTOR, str(creator.id), creator.name
    else:
        await verify_admin_token(request, authorization)
        actor_type = "admin"
        actor_id = label = payload.get("sub") or "admin"
    row = await audit.revoke_session(
        payload.get("sid"), reason="user", by=label,
        actor_type=actor_type, actor_id=actor_id,
    )
    if row is not None:
        await audit.record(
            actor_type=actor_type, actor_id=actor_id, actor_label=label,
            session_id=row.id, category="auth", action="auth.logout",
            summary="Signed out", method="POST", route="/api/v1/admin/logout",
            status_code=200, meta=audit.client_meta(request),
        )
    return {"status": "signed_out"}


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

    # 1. Explorers, and how many joined this week. The nexARound account that
    # owns official stories is not an explorer.
    explorers_count = (await db.execute(
        select(func.count(User.id)).where(User.id != OFFICIAL_USER_ID)
    )).scalar_one()
    new_explorers_7d = (await db.execute(
        select(func.count(User.id)).where(User.created_at >= week_ago, User.id != OFFICIAL_USER_ID)
    )).scalar_one()

    # 2. Live places, and how many were added this week
    attractions_count = (await db.execute(
        select(func.count(Attraction.id)).where(Attraction.status == "live")
    )).scalar_one()
    new_attractions_7d = (await db.execute(
        select(func.count(Attraction.id)).where(
            Attraction.status == "live", Attraction.created_at >= week_ago
        )
    )).scalar_one()

    # 3. Places waiting in the Review queue
    pending_approvals_count = (await db.execute(
        select(func.count(Attraction.id)).where(Attraction.status == "pending")
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
        WHERE created_at >= :start AND id != :official
        GROUP BY 1
    """), {"tz": DASHBOARD_TZ_NAME, "start": first_month, "official": OFFICIAL_USER_ID})
    signups_by_month = {row.month: row.signups for row in signup_rows}
    explorer_growth = [
        MonthlySignups(month=m, signups=signups_by_month.get(m, 0)) for m in months
    ]

    # 6. Recent Activity list
    # Query last 5 users
    recent_users_stmt = (
        select(User).where(User.id != OFFICIAL_USER_ID).order_by(desc(User.created_at)).limit(5)
    )
    recent_users_res = await db.execute(recent_users_stmt)
    recent_users = recent_users_res.scalars().all()

    # Places people did something with: the latest suggestions from the app and
    # the latest admin decisions. Google seeding adds rows all day and is not
    # activity anyone needs to see here.
    recent_suggestions = (await db.execute(
        select(Attraction, User.display_name)
        .outerjoin(User, User.id == Attraction.submitted_by_user_id)
        .where(Attraction.source == "user")
        .order_by(desc(Attraction.created_at))
        .limit(5)
    )).all()
    recent_decisions = (await db.execute(
        select(Attraction)
        .where(Attraction.reviewed_at.is_not(None))
        .order_by(desc(Attraction.reviewed_at))
        .limit(5)
    )).scalars().all()

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

    for attr, submitter in recent_suggestions:
        activity_items.append({
            "color": "#f59e0b",
            "text": f"'{attr.name}' suggested by {submitter or 'a deleted account'}.",
            "time": attr.created_at.isoformat() if attr.created_at else datetime.now(timezone.utc).isoformat(),
            "timestamp": attr.created_at.timestamp() if attr.created_at else 0.0
        })

    decision_words = {
        "live": ("#10b981", "is live"),
        "hidden": ("#94a3b8", "was hidden"),
        "rejected": ("#ef4444", "was rejected"),
        "pending": ("#f59e0b", "went back to the Review queue"),
    }
    for attr in recent_decisions:
        color, words = decision_words.get(attr.status, ("#6c63ff", attr.status))
        reason = f" ({attr.status_reason.replace('_', ' ')})" if attr.status_reason and attr.status != "live" else ""
        activity_items.append({
            "color": color,
            "text": f"'{attr.name}' {words}{reason} by {attr.reviewed_by}.",
            "time": attr.reviewed_at.isoformat(),
            "timestamp": attr.reviewed_at.timestamp(),
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


# Active on this many of the last 30 days, about once a week, makes a regular.
REGULAR_DAYS = 4
FREQUENT_LIMIT = 10


def _activity_view(starts: List[date], bucket_of, days: dict, people: dict) -> ActivityView:
    """Active explorers per bucket in `starts`, and who was active in the most
    of them. `bucket_of` maps a day to the start of its bucket."""
    index = {s: i for i, s in enumerate(starts)}
    buckets = [{"users": set(), "sessions": 0, "seconds": 0} for _ in starts]
    per_user: dict = {}  # user_id -> [bucket indexes, sessions, seconds]
    for day, users in days.items():
        i = index.get(bucket_of(day))
        if i is None:
            continue
        b = buckets[i]
        for uid, (sessions, seconds) in users.items():
            b["users"].add(uid)
            b["sessions"] += sessions
            b["seconds"] += seconds
            u = per_user.setdefault(uid, [set(), 0, 0])
            u[0].add(i)
            u[1] += sessions
            u[2] += seconds

    ranked = sorted(
        per_user.items(),
        key=lambda kv: (len(kv[1][0]), kv[1][1], people[kv[0]]["last"]),
        reverse=True,
    )[:FREQUENT_LIMIT]
    return ActivityView(
        buckets=[
            ActivityBucket(
                start=start,
                active=len(b["users"]),
                new=sum(1 for uid in b["users"] if bucket_of(people[uid]["joined"]) == start),
                sessions=b["sessions"],
                app_seconds=b["seconds"],
            )
            for start, b in zip(starts, buckets)
        ],
        top=[
            FrequentExplorer(
                id=uid,
                display_name=people[uid]["display_name"],
                email=people[uid]["email"],
                avatar_url=people[uid]["avatar_url"],
                active_periods=len(periods),
                sessions=sessions,
                app_seconds=seconds,
                last_active_at=people[uid]["last"],
            )
            for uid, (periods, sessions, seconds) in ranked
        ],
    )


@router.get("/users/activity", response_model=ExplorerActivity)
async def get_explorer_activity(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Active explorers per Sri Lanka day, week and month, and who comes back most.

    An explorer is active on a day when the app reported a session for them
    (user_sessions) or they used a feature that shows up in our API telemetry
    (api_events). Sessions and time in the app come from user_sessions only.
    """
    today = datetime.now(DASHBOARD_TZ).date()
    day_starts = [today - timedelta(days=i) for i in range(29, -1, -1)]
    this_week = today - timedelta(days=today.weekday())
    week_starts = [this_week - timedelta(weeks=i) for i in range(11, -1, -1)]
    month_starts = []
    year, month = today.year, today.month
    for _i in range(12):
        month_starts.append(date(year, month, 1))
        year, month = (year, month - 1) if month > 1 else (year - 1, 12)
    month_starts.reverse()
    # 60 days back covers the 30 days before the last 30, for the change figure.
    since_day = min(month_starts[0], today - timedelta(days=59))

    rows = (await db.execute(text("""
        WITH activity AS (
            SELECT user_id, (created_at AT TIME ZONE :tz)::date AS day, created_at AS at,
                   1 AS sessions, duration_seconds AS seconds
            FROM user_sessions
            WHERE created_at >= :since AND user_id IS NOT NULL
            UNION ALL
            SELECT user_id, (ts AT TIME ZONE :tz)::date, max(ts), 0, 0
            FROM api_events
            WHERE ts >= :since AND user_id IS NOT NULL
            GROUP BY 1, 2
        )
        SELECT u.id AS user_id, a.day, sum(a.sessions) AS sessions, sum(a.seconds) AS seconds,
               max(a.at) AS last_at, u.display_name, u.email, u.avatar_url,
               (u.created_at AT TIME ZONE :tz)::date AS joined
        FROM activity a JOIN users u ON u.id = a.user_id
        WHERE u.id != :official
        GROUP BY u.id, a.day
    """), {
        "tz": DASHBOARD_TZ_NAME,
        "since": datetime.combine(since_day, time.min, tzinfo=DASHBOARD_TZ),
        "official": OFFICIAL_USER_ID,
    })).mappings().all()

    people: dict = {}  # user_id -> profile and latest activity
    days: dict = {}    # day -> {user_id: (sessions, seconds)}
    for r in rows:
        p = people.setdefault(r["user_id"], {
            "display_name": r["display_name"], "email": r["email"],
            "avatar_url": r["avatar_url"], "joined": r["joined"], "last": r["last_at"],
        })
        p["last"] = max(p["last"], r["last_at"])
        days.setdefault(r["day"], {})[r["user_id"]] = (int(r["sessions"]), int(r["seconds"] or 0))

    def active_between(first: date, last: date) -> set:
        users = set()
        for i in range((last - first).days + 1):
            users.update(days.get(first + timedelta(days=i), {}))
        return users

    days_active_30d: dict = {}
    for d in day_starts:
        for uid in days.get(d, {}):
            days_active_30d[uid] = days_active_30d.get(uid, 0) + 1

    return ExplorerActivity(
        today=len(days.get(today, {})),
        yesterday=len(days.get(today - timedelta(days=1), {})),
        last_7d=len(active_between(today - timedelta(days=6), today)),
        prev_7d=len(active_between(today - timedelta(days=13), today - timedelta(days=7))),
        last_30d=len(days_active_30d),
        prev_30d=len(active_between(today - timedelta(days=59), today - timedelta(days=30))),
        avg_daily_30d=round(sum(len(days.get(d, {})) for d in day_starts) / len(day_starts), 1),
        regulars_30d=sum(1 for n in days_active_30d.values() if n >= REGULAR_DAYS),
        regular_days=REGULAR_DAYS,
        daily=_activity_view(day_starts, lambda d: d, days, people),
        weekly=_activity_view(week_starts, lambda d: d - timedelta(days=d.weekday()), days, people),
        monthly=_activity_view(month_starts, lambda d: d.replace(day=1), days, people),
        generated_at=datetime.now(timezone.utc),
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


async def _voice_settings(service: SettingsService) -> dict:
    enabled = await service.get_setting_fresh(neva_voice.K_ENABLED, "true")
    daily = await service.get_setting_fresh(
        neva_voice.K_DAILY_SECONDS, str(neva_voice.DEFAULT_DAILY_SECONDS))
    return {
        "neva_voice_enabled": enabled.strip().lower() not in ("0", "false", "no", "off"),
        "neva_voice_daily_seconds": neva_voice._as_int(daily, neva_voice.DEFAULT_DAILY_SECONDS),
        "google_tts_api_key": await service.get_setting_fresh(neva_voice.K_TTS_KEY, ""),
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
        experiences_country_mode=parse_country_mode(
            await service.get_setting_fresh(COUNTRY_MODE_KEY, "")
        ),
        exchangerate_api_key=await service.get_setting_fresh(fx_service.KEY_SETTING, ""),
        **await _provider_settings(service),
        **await _voice_settings(service),
    )


@router.put("/settings", response_model=SettingsResponse)
async def update_admin_settings(
    data: SettingsUpdateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Update platform settings and API keys."""
    # Which settings, never their values: several are API keys.
    request.state.audit_detail = {
        "fields": sorted(k for k, v in data.model_dump().items() if v is not None)
    }
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
    if data.experiences_country_mode is not None:
        await service.set_setting(
            COUNTRY_MODE_KEY,
            "true" if data.experiences_country_mode else "false",
            "Experiences browsed by country (true) or nearest first (false)",
        )
    fx_key_changed = False
    if data.exchangerate_api_key is not None:
        new_key = data.exchangerate_api_key.strip()
        if new_key != (await service.get_setting_fresh(fx_service.KEY_SETTING, "")).strip():
            await service.set_setting(
                fx_service.KEY_SETTING, new_key, "ExchangeRate-API key (daily currency rates)"
            )
            fx_key_changed = True
    voice_changed = False
    if data.neva_voice_enabled is not None:
        await service.set_setting(
            neva_voice.K_ENABLED,
            "true" if data.neva_voice_enabled else "false",
            "Neva reads her replies aloud (true) or answers in text only (false)",
        )
        voice_changed = True
    if data.neva_voice_daily_seconds is not None:
        await service.set_setting(
            neva_voice.K_DAILY_SECONDS, str(data.neva_voice_daily_seconds),
            "Seconds of Neva speech per user per day (0 = no limit)",
        )
        voice_changed = True
    if data.google_tts_api_key is not None:
        await service.set_setting(
            neva_voice.K_TTS_KEY, data.google_tts_api_key.strip(),
            "Google Cloud Text-to-Speech API key (Neva's voice)",
        )
        voice_changed = True
    if voice_changed:
        await neva_voice.refresh_config()
    provider_changed = False
    for key, description in _PROVIDER_SETTINGS.items():
        value = getattr(data, key)
        if value is not None:
            await service.set_setting(key, value.strip(), description)
            provider_changed = True
    if provider_changed:
        # This process sees it now; the Odyssey worker within a minute.
        await provider_config.refresh()
    if fx_key_changed:
        # Fetch with the new key now, so the Currency card shows at once
        # whether it works (one request from the monthly allowance).
        await fx_service.refresh(db)

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
        experiences_country_mode=parse_country_mode(
            await service.get_setting_fresh(COUNTRY_MODE_KEY, "")
        ),
        exchangerate_api_key=await service.get_setting_fresh(fx_service.KEY_SETTING, ""),
        **await _provider_settings(service),
        **await _voice_settings(service),
    )


# --- Audit trail & signed-in devices ---

def _like(text_: str) -> str:
    """A LIKE pattern for user text, with the wildcards neutralised."""
    return "%" + text_.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _event_out(e, vendor_names: dict) -> AuditEventOut:
    return AuditEventOut(
        id=e.id, occurred_at=e.occurred_at, actor_type=e.actor_type,
        actor_id=e.actor_id, actor_label=e.actor_label, vendor_id=e.vendor_id,
        vendor_name=vendor_names.get(e.vendor_id), session_id=e.session_id,
        category=e.category, action=e.action, summary=e.summary, method=e.method,
        route=e.route, path=e.path, target_id=e.target_id,
        status_code=e.status_code, success=e.success, ip=e.ip,
        browser=e.browser, os=e.os, device_type=e.device_type, detail=e.detail,
    )


async def _vendor_names(db: AsyncSession, ids) -> dict:
    ids = {i for i in ids if i}
    if not ids:
        return {}
    rows = await db.execute(
        select(ExperienceVendor.id, ExperienceVendor.name)
        .where(ExperienceVendor.id.in_(ids))
    )
    return {r.id: r.name for r in rows}


@router.get("/audit", response_model=AuditListResponse)
async def list_audit_events(
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    actor_type: Optional[Literal["admin", "vendor", "creator", "anonymous"]] = None,
    category: Optional[Literal["auth", "change", "access"]] = None,
    outcome: Optional[Literal["success", "failed"]] = None,
    vendor_id: Optional[uuid.UUID] = None,
    q: Optional[str] = Query(None, max_length=100),
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(verify_admin_token),
):
    """The audit trail, newest first. Read-only; nothing here can edit it."""
    conds = []
    if actor_type:
        conds.append(AuditEvent.actor_type == actor_type)
    if category:
        conds.append(AuditEvent.category == category)
    if outcome:
        conds.append(AuditEvent.success.is_(outcome == "success"))
    if vendor_id:
        conds.append(AuditEvent.vendor_id == vendor_id)
    if date_from:
        conds.append(AuditEvent.occurred_at >= datetime.combine(date_from, time.min, DASHBOARD_TZ))
    if date_to:
        conds.append(AuditEvent.occurred_at < datetime.combine(date_to + timedelta(days=1), time.min, DASHBOARD_TZ))
    if q and q.strip():
        pat = _like(q.strip())
        conds.append(or_(
            AuditEvent.summary.ilike(pat, escape="\\"),
            AuditEvent.actor_label.ilike(pat, escape="\\"),
            AuditEvent.ip.ilike(pat, escape="\\"),
            AuditEvent.path.ilike(pat, escape="\\"),
            AuditEvent.target_id.ilike(pat, escape="\\"),
        ))

    total = (await db.execute(
        select(func.count()).select_from(AuditEvent).where(*conds)
    )).scalar_one()
    rows = (await db.execute(
        select(AuditEvent).where(*conds)
        .order_by(AuditEvent.occurred_at.desc(), AuditEvent.id)
        .offset((page - 1) * page_size).limit(page_size)
    )).scalars().all()
    names = await _vendor_names(db, [r.vendor_id for r in rows])

    stats = None
    if page == 1:
        since = datetime.now(timezone.utc) - timedelta(hours=24)
        counts = (await db.execute(
            select(
                func.count(),
                func.count().filter(AuditEvent.action == "auth.login_failed"),
                func.count().filter(AuditEvent.category == "change"),
            ).where(AuditEvent.occurred_at >= since)
        )).one()
        active = (await db.execute(
            select(func.count()).select_from(AuthSession).where(
                AuthSession.revoked_at.is_(None),
                AuthSession.expires_at > datetime.now(timezone.utc),
            )
        )).scalar_one()
        stats = AuditStats(
            events_24h=counts[0], failed_sign_ins_24h=counts[1],
            changes_24h=counts[2], active_sessions=active,
        )
    return AuditListResponse(
        items=[_event_out(r, names) for r in rows],
        total=total, page=page, page_size=page_size, stats=stats,
    )


@router.get("/sessions", response_model=SessionListResponse)
async def list_sessions(
    page: int = Query(1, ge=1),
    page_size: int = Query(25, ge=1, le=100),
    actor_type: Optional[Literal["admin", "vendor", "creator"]] = None,
    state: Literal["active", "all"] = "active",
    token: str = Depends(verify_admin_token),
    db: AsyncSession = Depends(get_db),
):
    """Every signed-in device of the admin and the partner portal."""
    current = audit.parse_sid((decode_token(token) or {}).get("sid"))
    now = datetime.now(timezone.utc)
    conds = []
    if actor_type:
        conds.append(AuthSession.actor_type == actor_type)
    if state == "active":
        conds += [AuthSession.revoked_at.is_(None), AuthSession.expires_at > now]

    total = (await db.execute(
        select(func.count()).select_from(AuthSession).where(*conds)
    )).scalar_one()
    rows = (await db.execute(
        select(AuthSession).where(*conds)
        .order_by(AuthSession.last_seen_at.desc(), AuthSession.id)
        .offset((page - 1) * page_size).limit(page_size)
    )).scalars().all()
    names = await _vendor_names(db, [r.vendor_id for r in rows])
    return SessionListResponse(
        items=[
            SessionOut(
                id=r.id, actor_type=r.actor_type, actor_label=r.actor_label,
                vendor_id=r.vendor_id, vendor_name=names.get(r.vendor_id),
                ip=r.ip, last_ip=r.last_ip, browser=r.browser, os=r.os,
                device_type=r.device_type, created_at=r.created_at,
                last_seen_at=r.last_seen_at, expires_at=r.expires_at,
                status=audit.session_status(r, now), revoked_at=r.revoked_at,
                revoked_reason=r.revoked_reason, revoked_by=r.revoked_by,
                is_current=(r.id == current),
            )
            for r in rows
        ],
        total=total, page=page, page_size=page_size,
    )


@router.post("/sessions/{session_id}/revoke")
async def revoke_session_endpoint(
    session_id: uuid.UUID,
    request: Request,
    token: str = Depends(verify_admin_token),
):
    """Sign one device out. Its next request is refused."""
    payload = decode_token(token) or {}
    admin_name = payload.get("sub") or "admin"
    if audit.parse_sid(payload.get("sid")) == session_id:
        raise HTTPException(
            status_code=400,
            detail="That is the device you are using. Sign out instead.",
        )
    row = await audit.revoke_session(session_id, reason="admin", by=admin_name)
    if row is None:
        raise HTTPException(status_code=404, detail="Session not found or already ended.")
    if row.vendor_id:
        await partner_events.publish(row.vendor_id, partner_events.ACCOUNT_CHANGED)
    await audit.record(
        actor_type="admin", actor_id=admin_name, actor_label=admin_name,
        vendor_id=row.vendor_id, session_id=payload.get("sid"),
        category="auth", action="auth.session_revoked",
        summary=(
            f"Signed out {row.actor_label} on "
            f"{audit.describe_device(row.browser, row.os)} ({row.ip or 'unknown IP'})"
        ),
        method="POST", route="/api/v1/admin/sessions/{session_id}/revoke",
        path=request.url.path, target_id=str(row.id), status_code=200,
        meta=audit.client_meta(request),
        detail={"revoked_actor_type": row.actor_type},
    )
    return {"status": "revoked"}
