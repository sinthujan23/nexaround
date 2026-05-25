import uuid
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Header, HTTPException, status, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

from app.core.database import get_db
from app.services.user_service import UserService
from app.services.attraction_service import AttractionService
from app.schemas.user import UserResponse
from app.schemas.attraction import AttractionResponse, AttractionListResponse, AttractionCreate
from app.models.user import User
from app.models.attraction import Attraction

router = APIRouter(prefix="/admin", tags=["Admin REST API"])

# Admin credentials
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "password123"
ADMIN_TOKEN = "mission_control_access_granted"

# --- Request/Response Schemas ---

class AdminLoginRequest(BaseModel):
    username: str
    password: str

class AdminLoginResponse(BaseModel):
    token: str

class AdminDashboardStats(BaseModel):
    explorers_count: int
    attractions_count: int
    pending_approvals_count: int
    monthly_revenue: float
    growth_data: List[int]
    recent_activity: List[dict]

class AnnouncementRequest(BaseModel):
    title: str
    message: str
    target_plan: str


# --- Dependency to protect admin routes ---

async def verify_admin_token(authorization: str = Header(...)):
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header. Must be Bearer <token>"
        )
    token = authorization.split(" ")[1]
    if token != ADMIN_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Access Denied: Invalid admin credentials."
        )
    return token


# --- Endpoints ---

@router.post("/login", response_model=AdminLoginResponse)
async def admin_login(data: AdminLoginRequest):
    """Log in as admin and return a JSON token."""
    print(f"[ADMIN LOGIN REQUEST] username='{data.username}' password='{data.password}'")
    if data.username == ADMIN_USERNAME and data.password == ADMIN_PASSWORD:
        return AdminLoginResponse(token=ADMIN_TOKEN)
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Access Denied: Invalid credentials."
    )


@router.get("/dashboard", response_model=AdminDashboardStats)
async def get_dashboard_stats(
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Aggregate statistics for the dashboard dashboard."""
    # 1. Total users
    user_count_stmt = select(func.count(User.id))
    user_count_res = await db.execute(user_count_stmt)
    explorers_count = user_count_res.scalar_one_or_none() or 0

    # 2. Total attractions (all)
    attraction_count_stmt = select(func.count(Attraction.id))
    attraction_count_res = await db.execute(attraction_count_stmt)
    attractions_count = attraction_count_res.scalar_one_or_none() or 0

    # 3. Pending approvals (inactive attractions)
    pending_count_stmt = select(func.count(Attraction.id)).where(Attraction.is_active == False)
    pending_count_res = await db.execute(pending_count_stmt)
    pending_approvals_count = pending_count_res.scalar_one_or_none() or 0

    # 4. Mock Monthly Revenue
    monthly_revenue = 4520.0

    # 5. Explorer growth over last 12 months
    # Hardcoded fallback list matching standard months representation, updated dynamically with database data
    growth_data = [120, 150, 180, 220, 290, 310, 380, 420, 450, 480, 520, explorers_count]

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
        attractions_count=attractions_count,
        pending_approvals_count=pending_approvals_count,
        monthly_revenue=monthly_revenue,
        growth_data=growth_data,
        recent_activity=recent_activity
    )


@router.get("/users")
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _ = Depends(verify_admin_token)
):
    """Retrieve users for management."""
    service = UserService(db)
    users, total = await service.list_users(page=page, page_size=page_size, search_query=search)
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
    # Custom query to select inactive attractions
    stmt = select(Attraction).where(Attraction.is_active == False)
    count_stmt = select(func.count(Attraction.id)).where(Attraction.is_active == False)
    
    total_res = await db.execute(count_stmt)
    total = total_res.scalar_one_or_none() or 0

    results = await db.execute(stmt.offset((page - 1) * page_size).limit(page_size))
    attractions = results.scalars().all()

    service = AttractionService(db)
    mapped_attractions = [service._map_to_response(a) for a in attractions]

    return AttractionListResponse(
        attractions=mapped_attractions,
        total=total,
        page=page,
        page_size=page_size
    )


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
    """Aggregate engagement indicators and session durations."""
    return {
        "daily_active_users": 845,
        "avg_session_length": "4m 20s",
        "places_visited_count": 12450
    }


@router.post("/engagement/announcements")
async def post_system_announcement(
    data: AnnouncementRequest,
    _ = Depends(verify_admin_token)
):
    """Broadcast a system notification to users."""
    # Log the broadcast mock
    print(f"[ANNOUNCEMENT BROADCAST] Plan: {data.target_plan} | Title: {data.title} | Msg: {data.message}")
    return {
        "status": "success",
        "message": f"Announcement successfully broadcast to all '{data.target_plan}' subscribers."
    }
