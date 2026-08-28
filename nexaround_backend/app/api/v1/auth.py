import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Header, Form
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.services.auth_service import AuthService
from app.schemas.user import (
    UserRegister,
    UserLogin,
    GoogleLoginRequest,
    AppleLoginRequest,
    TokenResponse,
    TokenRefreshRequest,
    UserResponse,
    UserPreferencesUpdate,
    FcmTokenRequest,
    MessageResponse,
    VerifyOTPRequest,
    ResendOTPRequest,
    RegisterPendingResponse,
    ForgotPasswordRequest,
    VerifyResetOTPRequest,
    ResetPasswordRequest,
    ForgotPasswordResponse,
    VerifyResetOTPResponse,
)

from app.core.rate_limiter import auth_rate_limiter

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=RegisterPendingResponse, status_code=201, dependencies=[Depends(auth_rate_limiter)])
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)):
    """Register a new user account (dispatches OTP to email)."""
    service = AuthService(db)
    return await service.register(data)


@router.post("/verify-otp", response_model=TokenResponse, dependencies=[Depends(auth_rate_limiter)])
async def verify_otp(data: VerifyOTPRequest, db: AsyncSession = Depends(get_db)):
    """Verify 6-digit OTP code and complete user registration."""
    service = AuthService(db)
    return await service.verify_otp(data.email, data.otp)


@router.post("/resend-otp", response_model=RegisterPendingResponse, dependencies=[Depends(auth_rate_limiter)])
async def resend_otp(data: ResendOTPRequest, db: AsyncSession = Depends(get_db)):
    """Resend 6-digit verification OTP code to email."""
    service = AuthService(db)
    return await service.resend_otp(data.email)


@router.post("/login", response_model=TokenResponse, dependencies=[Depends(auth_rate_limiter)])
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)):
    """Login with email and password."""
    service = AuthService(db)
    return await service.login(data.email, data.password)


@router.post("/forgot-password", response_model=ForgotPasswordResponse, dependencies=[Depends(auth_rate_limiter)])
async def forgot_password(data: ForgotPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Validate user existence and send a 6-digit password reset OTP code to email."""
    service = AuthService(db)
    return await service.forgot_password(data.email)


@router.post("/verify-reset-otp", response_model=VerifyResetOTPResponse, dependencies=[Depends(auth_rate_limiter)])
async def verify_reset_otp(data: VerifyResetOTPRequest, db: AsyncSession = Depends(get_db)):
    """Verify password reset OTP and return a single-use reset token."""
    service = AuthService(db)
    return await service.verify_reset_otp(data.email, data.otp)


@router.post("/reset-password", response_model=MessageResponse, dependencies=[Depends(auth_rate_limiter)])
async def reset_password(data: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Reset user password using reset_token issued after OTP verification."""
    service = AuthService(db)
    return await service.reset_password(data.email, data.reset_token, data.new_password)


@router.post("/google", response_model=TokenResponse, dependencies=[Depends(auth_rate_limiter)])
async def google_login(data: GoogleLoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate with Google ID Token."""
    service = AuthService(db)
    return await service.google_login(data.id_token)


@router.post("/apple", response_model=TokenResponse, dependencies=[Depends(auth_rate_limiter)])
async def apple_login(data: AppleLoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate with Apple ID Token."""
    service = AuthService(db)
    return await service.apple_login(
        data.id_token,
        data.authorization_code,
        data.given_name,
        data.family_name,
    )



@router.post("/apple/callback")
async def apple_callback(
    code: str = Form(...),
    id_token: str = Form(...),
    state: Optional[str] = Form(None),
    user: Optional[str] = Form(None),
):
    """
    Callback endpoint for Apple Sign-In on Android.
    Redirects back to the app using a custom intent scheme.
    """
    import urllib.parse
    params = {"code": code, "id_token": id_token}
    if state:
        params["state"] = state
    query_str = urllib.parse.urlencode(params)
    redirect_url = f"intent://callback?{query_str}#Intent;package=com.nexaround.app;scheme=signinwithapple;end"
    return RedirectResponse(url=redirect_url, status_code=303)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(data: TokenRefreshRequest, db: AsyncSession = Depends(get_db)):
    """Refresh access token using refresh token."""
    service = AuthService(db)
    return await service.refresh_tokens(data.refresh_token)


@router.post("/logout", response_model=MessageResponse)
async def logout(authorization: str = Header(...)):
    """Log out by blacklisting the current access token. The token will be
    rejected on subsequent requests until it naturally expires."""
    from app.core.security import blacklist_token
    token = authorization.replace("Bearer ", "")
    await blacklist_token(token)
    return MessageResponse(message="Logged out successfully")


@router.get("/me", response_model=UserResponse)
async def get_current_user(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Get current authenticated user profile."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    return await service.get_current_user(token)


@router.put("/me/preferences", response_model=UserResponse)
async def update_preferences(
    data: UserPreferencesUpdate,
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Update user preferences for personalization."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    return await service.update_preferences(user.id, data.model_dump(exclude_none=True))


@router.post("/me/fcm-token", response_model=MessageResponse)
async def register_fcm_token(
    data: FcmTokenRequest,
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Register this device's FCM push token. A user can be signed in on several
    devices (Android + iOS), so tokens are kept as a list and pushes go to all.
    """
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    prefs = user.preferences or {}
    tokens = [t for t in (prefs.get("fcm_tokens") or []) if t and t != data.token]
    tokens.insert(0, data.token)  # newest first
    tokens = tokens[:8]           # keep the few most recent devices
    await service.update_preferences(user.id, {"fcm_tokens": tokens})
    return MessageResponse(message="Token registered")


class _SessionPing(BaseModel):
    duration_seconds: int = 0


@router.post("/me/session", response_model=MessageResponse)
async def record_session(
    data: _SessionPing,
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
):
    """Record a finished foreground session (seconds) — feeds the admin's real
    DAU and average-session-length metrics. The app posts this when it goes to
    the background. Auth is best-effort: an expired token still no-ops cleanly
    instead of erroring, so analytics never breaks the app."""
    from app.models.analytics import UserSession
    user_id = None
    try:
        token = (authorization or "").replace("Bearer ", "")
        if token:
            user = await AuthService(db).get_current_user(token)
            user_id = user.id
    except Exception:
        user_id = None
    secs = max(0, min(int(data.duration_seconds or 0), 24 * 3600))
    if secs > 0:
        db.add(UserSession(user_id=user_id, duration_seconds=secs))
        await db.commit()
    return MessageResponse(message="ok")


class RecentLocationItem(BaseModel):
    name: str
    place_id: Optional[str] = ""
    district: Optional[str] = "Nearby"
    address: Optional[str] = ""
    latitude: Optional[float] = 0.0
    longitude: Optional[float] = 0.0


@router.get("/me/recent-locations", response_model=list[dict])
async def get_recent_locations(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve user's recent location searches synced across devices."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    prefs = user.preferences or {}
    return prefs.get("recent_locations") or []


@router.post("/me/recent-locations", response_model=list[dict])
async def add_recent_location(
    data: RecentLocationItem,
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Save or move a location to the top of user's cross-device search history."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    prefs = user.preferences or {}
    locations = [dict(loc) for loc in (prefs.get("recent_locations") or []) if isinstance(loc, dict)]

    # Deduplicate
    name_lower = data.name.strip().lower()
    locations = [
        loc for loc in locations
        if loc.get("name", "").strip().lower() != name_lower
        and not (data.place_id and loc.get("place_id") and loc.get("place_id") == data.place_id)
    ]

    # Prepend new search
    locations.insert(0, data.model_dump())
    locations = locations[:10]  # keep max 10

    await service.update_preferences(user.id, {"recent_locations": locations})
    return locations


@router.delete("/me/recent-locations", response_model=list[dict])
async def remove_recent_location(
    name: Optional[str] = None,
    place_id: Optional[str] = None,
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Remove a specific search item or clear all recent locations."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    prefs = user.preferences or {}
    locations = [dict(loc) for loc in (prefs.get("recent_locations") or []) if isinstance(loc, dict)]

    if not name and not place_id:
        # Clear all
        locations = []
    else:
        name_lower = (name or "").strip().lower()
        locations = [
            loc for loc in locations
            if (not name or loc.get("name", "").strip().lower() != name_lower)
            and (not place_id or loc.get("place_id") != place_id)
        ]

    await service.update_preferences(user.id, {"recent_locations": locations})
    return locations


@router.delete("/me", response_model=MessageResponse)
async def delete_account(
    authorization: str = Header(...),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete user account and all associated personal data."""
    token = authorization.replace("Bearer ", "")
    service = AuthService(db)
    user = await service.get_current_user(token)
    res = await service.delete_account(user.id)
    return MessageResponse(message=res.get("message", "Account and all associated data permanently deleted."))

