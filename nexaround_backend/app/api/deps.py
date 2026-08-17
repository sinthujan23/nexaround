import uuid
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.core.security import decode_token_with_blacklist_check
from app.models.user import User
from app.repositories.user_repository import UserRepository

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")
# auto_error=False so a missing header yields None instead of a 401. Used by
# endpoints that are reachable without a Bearer token — notably image URLs,
# which browsers and Flutter's Image widget fetch without custom headers.
oauth2_scheme_optional = OAuth2PasswordBearer(
    tokenUrl="api/v1/auth/login", auto_error=False
)

async def get_current_user(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    payload = await decode_token_with_blacklist_check(token)
    if payload is None:
        raise credentials_exception
        
    user_id: str = payload.get("sub")
    if user_id is None:
        raise credentials_exception
        
    repo = UserRepository(db)
    user = await repo.get_by_id(uuid.UUID(user_id))
    
    if user is None:
        raise credentials_exception
        
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")

    # Attach the caller to the request context so telemetry rows emitted deeper
    # in the stack carry a user_id without every service signature growing one.
    from app.core.request_context import set_user_id
    set_user_id(user.id)

    return user


async def get_current_user_optional(
    db: AsyncSession = Depends(get_db),
    token: str = Depends(oauth2_scheme_optional),
):
    """Resolve the caller if a valid token is present, else None.

    Never raises. Endpoints using this must decide for themselves what an
    anonymous caller is allowed to do.
    """
    if not token:
        return None
    try:
        payload = await decode_token_with_blacklist_check(token)
        if payload is None:
            return None
        user_id = payload.get("sub")
        if user_id is None:
            return None
        user = await UserRepository(db).get_by_id(uuid.UUID(user_id))
        if user is None or not user.is_active:
            return None
        from app.core.request_context import set_user_id
        set_user_id(user.id)
        return user
    except Exception:
        return None
