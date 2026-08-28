import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr, Field


# --- Request Schemas ---

class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=6, max_length=100)
    display_name: str = Field(..., min_length=1, max_length=100)
    language: str = Field(default="en", max_length=10)
    nationality: Optional[str] = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class GoogleLoginRequest(BaseModel):
    id_token: str


class AppleLoginRequest(BaseModel):
    id_token: str
    authorization_code: str
    given_name: Optional[str] = None
    familyName: Optional[str] = None


class VerifyOTPRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6, description="6-digit numeric OTP code")


class ResendOTPRequest(BaseModel):
    email: EmailStr


class RegisterPendingResponse(BaseModel):
    status: str = "pending_verification"
    email: str
    message: str = "Verification OTP sent to your email address."


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class VerifyResetOTPRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6, description="6-digit numeric OTP code")


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    reset_token: str = Field(..., description="Single-use reset token issued upon OTP verification")
    new_password: str = Field(..., min_length=6, max_length=100)


class ForgotPasswordResponse(BaseModel):
    status: str = "reset_otp_sent"
    email: str
    message: str = "Password reset code sent to your email address."


class VerifyResetOTPResponse(BaseModel):
    status: str = "otp_verified"
    email: str
    reset_token: str
    message: str = "Code verified. Please set a new password."




class UserPreferencesUpdate(BaseModel):
    interests: Optional[list[str]] = None
    travel_style: Optional[str] = None  # adventure, relaxed, cultural, foodie
    budget_range: Optional[str] = None  # budget, moderate, luxury
    accessibility_needs: Optional[list[str]] = None
    preferred_transport: Optional[str] = None
    currency: Optional[str] = None
    nationality: Optional[str] = None


class FcmTokenRequest(BaseModel):
    """Device push token, stored on the user for FCM delivery."""
    token: str


# --- Response Schemas ---

class UserResponse(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str
    avatar_url: Optional[str] = None
    preferences: dict = {}
    language: str = "en"
    is_active: bool = True
    is_verified: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserResponse


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class MessageResponse(BaseModel):
    message: str
