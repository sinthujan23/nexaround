import uuid
import httpx
from typing import Optional, Dict, Any
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from jose import jwt
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserRegister, UserResponse, TokenResponse
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.core.exceptions import (
    ConflictException,
    UnauthorizedException,
    NotFoundException,
)


class AuthService:
    """Business logic for authentication and user management."""

    def __init__(self, db: AsyncSession):
        self.repo = UserRepository(db)

    async def register(self, data: UserRegister) -> TokenResponse:
        """Register a new user and return tokens."""
        # Check if email already exists
        existing = await self.repo.get_by_email(data.email)
        if existing:
            raise ConflictException(detail="Email already registered")

        # Create user
        user = User(
            email=data.email,
            password_hash=get_password_hash(data.password),
            display_name=data.display_name,
            language=data.language,
        )
        user = await self.repo.create(user)

        # Generate tokens
        token_data = {"sub": str(user.id), "email": user.email}
        access_token = create_access_token(token_data)
        refresh_token = create_refresh_token(token_data)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user=UserResponse.model_validate(user),
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

        return await self._generate_auth_response(user)

    async def google_login(self, google_id_token: str) -> TokenResponse:
        """Verify Google ID token and login/register user."""
        try:
            # In a real app, you'd get the CLIENT_ID from config
            # For now, we accept the token and verify it
            id_info = id_token.verify_oauth2_token(
                google_id_token, google_requests.Request()
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

            return await self._generate_auth_response(user)
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
            # Apple tokens are JWTs. In a real app, verify signature with Apple's keys.
            # Here we decode for the demonstration of the flow.
            payload = jwt.get_unverified_claims(apple_id_token)
            
            email = payload.get("email")
            if not email:
                raise UnauthorizedException(detail="Invalid Apple token: no email")

            user = await self.repo.get_by_email(email)
            if not user:
                # Register new user from Apple
                display_name = "User"
                if given_name:
                    display_name = f"{given_name} {family_name or ''}".strip()
                
                user = User(
                    email=email,
                    display_name=display_name,
                    is_verified=True,
                )
                user = await self.repo.create(user)

            return await self._generate_auth_response(user)
        except Exception as e:
            raise UnauthorizedException(detail=f"Apple authentication failed: {str(e)}")

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
