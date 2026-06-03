import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Header, Form
from fastapi.responses import RedirectResponse
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
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)):
    """Register a new user account."""
    service = AuthService(db)
    return await service.register(data)


@router.post("/login", response_model=TokenResponse)
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)):
    """Login with email and password."""
    service = AuthService(db)
    return await service.login(data.email, data.password)


@router.post("/google", response_model=TokenResponse)
async def google_login(data: GoogleLoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate with Google ID Token."""
    service = AuthService(db)
    return await service.google_login(data.id_token)


@router.post("/apple", response_model=TokenResponse)
async def apple_login(data: AppleLoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate with Apple ID Token."""
    service = AuthService(db)
    return await service.apple_login(
        data.id_token,
        data.authorization_code,
        data.given_name,
        data.familyName,
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
    # The intent scheme used by the sign_in_with_apple package
    redirect_url = f"intent://callback?code={code}&id_token={id_token}#Intent;package=com.nexaround.nexaround_app;scheme=signinwithapple;end"
    return RedirectResponse(url=redirect_url, status_code=303)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(data: TokenRefreshRequest, db: AsyncSession = Depends(get_db)):
    """Refresh access token using refresh token."""
    service = AuthService(db)
    return await service.refresh_tokens(data.refresh_token)


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
