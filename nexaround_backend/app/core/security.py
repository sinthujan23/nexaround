from datetime import datetime, timedelta, timezone
from typing import Optional
import uuid
from jose import jwt, JWTError
from passlib.context import CryptContext
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.JWT_ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS


def verify_password(plain_password: str, hashed_password: Optional[str]) -> bool:
    """Verify a plain password against a hashed password."""
    if not hashed_password or not plain_password:
        return False
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    """Hash a plain password."""
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a JWT access token with a unique jti for revocation support."""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({
        "exp": expire,
        "type": "access",
        "jti": uuid.uuid4().hex,
    })
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def create_refresh_token(data: dict) -> str:
    """Create a JWT refresh token with a unique jti for revocation support."""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({
        "exp": expire,
        "type": "refresh",
        "jti": uuid.uuid4().hex,
    })
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def is_token_blacklisted(jti: str) -> bool:
    """Check if a token's jti has been blacklisted in Redis."""
    try:
        from app.core.rate_limiter import get_redis_client
        redis = await get_redis_client()
        if redis:
            return await redis.exists(f"blacklist:{jti}") > 0
    except Exception:
        pass
    return False


async def blacklist_token(token: str) -> None:
    """Add a token to the Redis blacklist. TTL matches the token's remaining lifetime."""
    try:
        from app.core.rate_limiter import get_redis_client
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        jti = payload.get("jti")
        exp = payload.get("exp")
        if not jti or not exp:
            return
        # Calculate remaining TTL
        remaining = int(exp - datetime.now(timezone.utc).timestamp())
        if remaining > 0:
            redis = await get_redis_client()
            if redis:
                await redis.setex(f"blacklist:{jti}", remaining, "1")
    except Exception:
        pass


def decode_token(token: str) -> Optional[dict]:
    """Decode and verify a JWT token."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None


async def decode_token_with_blacklist_check(token: str) -> Optional[dict]:
    """Decode a JWT token and verify it hasn't been blacklisted."""
    payload = decode_token(token)
    if not payload:
        return None
    jti = payload.get("jti")
    if jti and await is_token_blacklisted(jti):
        return None
    return payload
