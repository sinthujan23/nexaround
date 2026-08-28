import uuid
import asyncio
import httpx
from typing import Optional, Dict, Any
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from jose import jwt
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import User
from app.repositories.user_repository import UserRepository
import secrets
import redis.asyncio as aioredis
from app.schemas.user import (
    UserRegister,
    UserResponse,
    TokenResponse,
    RegisterPendingResponse,
    ForgotPasswordResponse,
    VerifyResetOTPResponse,
)
from app.services.email_service import send_otp_email, send_password_reset_email
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.core.config import settings
from app.core.exceptions import (
    ConflictException,
    UnauthorizedException,
    NotFoundException,
    BadRequestException,
)
from app.core.rate_limiter import get_redis_client


class AuthService:
    """Business logic for authentication and user management."""

    def __init__(self, db: AsyncSession):
        self.repo = UserRepository(db)

    async def register(self, data: UserRegister) -> RegisterPendingResponse:
        """Register a new user in unverified state and dispatch OTP email."""
        # Check if email already exists
        existing = await self.repo.get_by_email(data.email)
        if existing:
            if existing.is_verified:
                raise ConflictException(detail="Email already registered and verified")
            
            # If account exists but is unverified, check if valid OTP already exists in Redis
            redis = await get_redis_client()
            existing_otp = None
            if redis:
                existing_otp = await redis.get(f"otp:{data.email}")
            
            if existing_otp:
                # Valid OTP already sent; proceed straight to OTP page
                return RegisterPendingResponse(
                    email=data.email,
                    message="Verification OTP code was already sent to your email. Please enter the OTP to complete registration."
                )

            # If OTP expired, re-issue OTP
            return await self.resend_otp(data.email)

        # Create unverified user
        user = User(
            email=data.email,
            password_hash=get_password_hash(data.password),
            display_name=data.display_name,
            language=data.language,
            is_verified=False,
            preferences={"nationality": data.nationality} if data.nationality else {},
        )
        user = await self.repo.create(user)

        # Generate 6-digit numeric OTP
        otp_code = "".join(secrets.choice("0123456789") for _ in range(6))
        
        # Save OTP to Redis with 10-minute TTL (600s)
        redis = await get_redis_client()
        if redis:
            await redis.setex(f"otp:{data.email}", 600, otp_code)

        # Dispatch email
        await send_otp_email(data.email, otp_code)

        return RegisterPendingResponse(
            email=data.email,
            message="Verification OTP sent to your email address. Please complete OTP verification to log in."
        )

    async def verify_otp(self, email: str, otp: str) -> TokenResponse:
        """Verify 6-digit OTP code, mark user as verified, and return tokens."""
        redis = await get_redis_client()
        stored_otp = None
        if redis:
            stored_otp = await redis.get(f"otp:{email}")

        if not stored_otp or stored_otp != otp:
            raise BadRequestException(detail="Invalid or expired OTP code")

        user = await self.repo.get_by_email(email)
        if not user:
            raise NotFoundException(detail="User account not found")

        # Mark user as verified
        user.is_verified = True
        await self.repo.update(user)

        # Clean up OTP from Redis
        if redis:
            await redis.delete(f"otp:{email}")

        return await self._generate_auth_response(user)

    async def resend_otp(self, email: str) -> RegisterPendingResponse:
        """Resend 6-digit OTP code with 60-second cooldown."""
        user = await self.repo.get_by_email(email)
        if not user:
            raise NotFoundException(detail="User account not found")

        if user.is_verified:
            raise ConflictException(detail="Account is already verified. Please log in.")

        redis = await get_redis_client()
        if redis:
            cooldown_key = f"otp_resend:{email}"
            if await redis.get(cooldown_key):
                raise ConflictException(detail="Please wait 60 seconds before requesting a new OTP")
            await redis.setex(cooldown_key, 60, "1")

        # Generate new 6-digit numeric OTP
        otp_code = "".join(secrets.choice("0123456789") for _ in range(6))
        if redis:
            await redis.setex(f"otp:{email}", 600, otp_code)

        # Dispatch email
        await send_otp_email(email, otp_code)

        return RegisterPendingResponse(
            email=email,
            message="A new 6-digit OTP code has been sent to your email."
        )

    async def login(self, email: str, password: str) -> TokenResponse:
        """Authenticate user and return tokens."""
        user = await self.repo.get_by_email(email)
        if not user:
            raise UnauthorizedException(detail="Invalid email or password")

        if not verify_password(password, user.password_hash):
            raise UnauthorizedException(detail="Invalid email or password")

        if not user.is_active:
            raise UnauthorizedException(detail="Account is deactivated")

        if not user.is_verified:
            raise UnauthorizedException(
                detail="Email address not verified. Please complete 6-digit OTP verification to log in."
            )

        return await self._generate_auth_response(user)

    async def google_login(self, google_id_token: str) -> TokenResponse:
        """Verify Google ID token and login/register user."""
        try:
            id_info = id_token.verify_oauth2_token(
                google_id_token, google_requests.Request()
            )

            # Check issuer
            iss = id_info.get("iss")
            if iss not in ["accounts.google.com", "https://accounts.google.com"]:
                raise UnauthorizedException(detail="Invalid Google token: untrusted issuer")

            # Enforce audience validation — GOOGLE_CLIENT_IDS must be configured
            allowed_ids = settings.GOOGLE_CLIENT_IDS
            if not allowed_ids:
                raise UnauthorizedException(
                    detail="Google login is not configured. GOOGLE_CLIENT_IDS must be set."
                )
            aud = id_info.get("aud")
            azp = id_info.get("azp")
            aud_valid = (aud in allowed_ids) or (azp in allowed_ids)
            if not aud_valid:
                # Also check project number prefix for authorized clients under same project
                allowed_prefixes = {cid.split("-")[0] for cid in allowed_ids if "-" in cid}
                aud_prefix = aud.split("-")[0] if (aud and "-" in aud) else ""
                azp_prefix = azp.split("-")[0] if (azp and "-" in azp) else ""
                if not (aud_prefix in allowed_prefixes or azp_prefix in allowed_prefixes):
                    raise UnauthorizedException(
                        detail="Invalid Google token: audience not allowed for this app"
                    )

            email = id_info.get("email")
            if not email:
                raise UnauthorizedException(detail="Invalid Google token: no email")

            user = await self.repo.get_by_email(email)
            if not user:
                # Register new user from Google
                user = User(
                    email=email,
                    display_name=id_info.get("name", email.split("@")[0]),
                    avatar_url=id_info.get("picture"),
                    is_verified=True,  # Google verified email
                )
                user = await self.repo.create(user)

            if not user.is_active:
                raise UnauthorizedException(detail="Account is deactivated")

            return await self._generate_auth_response(user)
        except UnauthorizedException:
            raise
        except Exception as e:
            raise UnauthorizedException(detail=f"Google authentication failed: {str(e)}")

    async def apple_login(
        self,
        apple_id_token: str,
        authorization_code: str,
        given_name: Optional[str] = None,
        family_name: Optional[str] = None,
    ) -> TokenResponse:
        """Verify Apple ID token and login/register user."""
        try:
            payload = await self._verify_apple_token(apple_id_token)
            
            email = payload.get("email")
            sub = payload.get("sub")
            if not email and sub:
                email = f"{sub}@privaterelay.appleid.com"

            if not email:
                raise UnauthorizedException(detail="Invalid Apple token: no email or subject identifier")

            user = await self.repo.get_by_email(email)
            if not user:
                # Register new user from Apple
                display_name = "Explorer"
                if given_name:
                    display_name = f"{given_name} {family_name or ''}".strip()
                
                user = User(
                    email=email,
                    display_name=display_name,
                    is_verified=True,
                )
                user = await self.repo.create(user)

            if not user.is_active:
                raise UnauthorizedException(detail="Account is deactivated")

            return await self._generate_auth_response(user)
        except UnauthorizedException:
            raise
        except Exception as e:
            raise UnauthorizedException(detail=f"Apple authentication failed: {str(e)}")

    async def _verify_apple_token(self, apple_id_token: str) -> dict:
        """Fetch Apple's JWKS public keys and cryptographically verify the JWT signature."""
        import time
        headers = jwt.get_unverified_header(apple_id_token)
        kid = headers.get("kid")
        if not kid:
            raise UnauthorizedException(detail="Invalid Apple token: missing key ID (kid)")

        keys = await self._fetch_apple_jwks()
        matching_key = next((k for k in keys if k.get("kid") == kid), None)
        if not matching_key:
            # Force refresh cache once in case Apple rotated keys
            keys = await self._fetch_apple_jwks(force_refresh=True)
            matching_key = next((k for k in keys if k.get("kid") == kid), None)

        if not matching_key:
            raise UnauthorizedException(detail="Invalid Apple token: unrecognised key ID")

        allowed_auds = [a for a in settings.APPLE_CLIENT_IDS if a]
        try:
            payload = jwt.decode(
                apple_id_token,
                matching_key,
                algorithms=["RS256"],
                issuer="https://appleid.apple.com",
                options={"verify_aud": False},
            )

            # Manually validate audience against allowed Apple Client IDs
            if allowed_auds:
                token_aud = payload.get("aud")
                if isinstance(token_aud, list):
                    if not any(aud in allowed_auds for aud in token_aud):
                        raise UnauthorizedException(
                            detail=f"Invalid Apple token: audience {token_aud} not in allowed client IDs"
                        )
                else:
                    if token_aud not in allowed_auds:
                        raise UnauthorizedException(
                            detail=f"Invalid Apple token: audience '{token_aud}' not in allowed client IDs"
                        )

            return payload
        except UnauthorizedException:
            raise
        except Exception as err:
            raise UnauthorizedException(detail=f"Apple token signature verification failed: {err}")

    @staticmethod
    async def _fetch_apple_jwks(force_refresh: bool = False) -> list:
        import time
        if not hasattr(AuthService, "_apple_keys_cache"):
            AuthService._apple_keys_cache = {"keys": [], "expires_at": 0}
        
        now = time.time()
        cache = AuthService._apple_keys_cache
        if not force_refresh and cache["keys"] and now < cache["expires_at"]:
            return cache["keys"]

        async with httpx.AsyncClient() as client:
            resp = await client.get("https://appleid.apple.com/auth/keys", timeout=10.0)
            resp.raise_for_status()
            keys = resp.json().get("keys", [])
            cache["keys"] = keys
            cache["expires_at"] = now + 3600  # cache 1 hour
            return keys


    async def _generate_auth_response(self, user: User) -> TokenResponse:
        """Helper to generate TokenResponse for a user."""
        token_data = {"sub": str(user.id), "email": user.email}
        access_token = create_access_token(token_data)
        refresh_token = create_refresh_token(token_data)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user=UserResponse.model_validate(user),
        )

    async def refresh_tokens(self, refresh_token: str) -> TokenResponse:
        """Refresh access and refresh tokens."""
        payload = decode_token(refresh_token)
        if not payload or payload.get("type") != "refresh":
            raise UnauthorizedException(detail="Invalid refresh token")

        user_id = payload.get("sub")
        if not user_id:
            raise UnauthorizedException(detail="Invalid token payload")

        user = await self.repo.get_by_id(uuid.UUID(user_id))
        if not user or not user.is_active:
            raise UnauthorizedException(detail="User not found or inactive")

        return await self._generate_auth_response(user)

    async def get_current_user(self, token: str) -> UserResponse:
        """Get the current user from a JWT token."""
        payload = decode_token(token)
        if not payload or payload.get("type") != "access":
            raise UnauthorizedException(detail="Invalid access token")

        user_id = payload.get("sub")
        if not user_id:
            raise UnauthorizedException(detail="Invalid token payload")

        user = await self.repo.get_by_id(uuid.UUID(user_id))
        if not user or not user.is_active:
            raise NotFoundException(detail="User not found")

        return UserResponse.model_validate(user)

    async def update_preferences(
        self, user_id: uuid.UUID, preferences: dict
    ) -> UserResponse:
        """Update user preferences."""
        user = await self.repo.get_by_id(user_id)
        if not user:
            raise NotFoundException(detail="User not found")

        user.preferences = {**user.preferences, **preferences}
        user = await self.repo.update(user)
        return UserResponse.model_validate(user)

    async def forgot_password(self, email: str) -> ForgotPasswordResponse:
        """Validate user existence and send a 6-digit password reset OTP."""
        user = await self.repo.get_by_email(email)
        if not user:
            raise NotFoundException(detail="No account registered with this email address")

        if not user.is_active:
            raise UnauthorizedException(detail="Account is deactivated")

        redis = await get_redis_client()
        if redis:
            cooldown_key = f"reset_otp_cooldown:{email}"
            if await redis.get(cooldown_key):
                raise ConflictException(detail="Please wait 60 seconds before requesting a new reset code")
            await redis.setex(cooldown_key, 60, "1")

        # Generate 6-digit OTP code
        otp_code = "".join(secrets.choice("0123456789") for _ in range(6))
        if redis:
            await redis.setex(f"reset_otp:{email}", 600, otp_code)

        # Send email
        await send_password_reset_email(email, otp_code)

        return ForgotPasswordResponse(
            email=email,
            message="Password reset code sent to your email address."
        )

    async def verify_reset_otp(self, email: str, otp: str) -> VerifyResetOTPResponse:
        """Verify password reset OTP and generate a short-lived reset token."""
        redis = await get_redis_client()
        stored_otp = None
        if redis:
            stored_otp = await redis.get(f"reset_otp:{email}")

        if not stored_otp or stored_otp != otp:
            raise BadRequestException(detail="Invalid or expired verification code")

        user = await self.repo.get_by_email(email)
        if not user:
            raise NotFoundException(detail="User account not found")

        # Generate single-use reset token
        reset_token = uuid.uuid4().hex
        if redis:
            await redis.setex(f"reset_token:{reset_token}", 300, email)  # 5 min TTL
            await redis.delete(f"reset_otp:{email}")

        return VerifyResetOTPResponse(
            email=email,
            reset_token=reset_token,
            message="Code verified. Please set a new password."
        )

    async def reset_password(self, email: str, reset_token: str, new_password: str) -> dict:
        """Verify reset token and update user's password."""
        redis = await get_redis_client()
        stored_email = None
        if redis:
            stored_email = await redis.get(f"reset_token:{reset_token}")

        if not stored_email or stored_email != email:
            raise BadRequestException(detail="Invalid or expired reset session. Please request a new code.")

        user = await self.repo.get_by_email(email)
        if not user:
            raise NotFoundException(detail="User account not found")

        # Update password
        user.password_hash = get_password_hash(new_password)
        user.is_verified = True
        await self.repo.update(user)

        # Invalidate reset token
        if redis:
            await redis.delete(f"reset_token:{reset_token}")

        return {"message": "Password reset successfully. Please log in with your new password."}
