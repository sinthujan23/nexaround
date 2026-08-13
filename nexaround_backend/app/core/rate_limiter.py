"""Rate limiting dependency for authentication endpoints."""
import time
from typing import Dict, List
from fastapi import Request, HTTPException, status
import redis.asyncio as aioredis
from app.core.config import settings

_in_memory_store: Dict[str, List[float]] = {}
_redis_client = None

async def get_redis_client():
    global _redis_client
    if _redis_client is None:
        try:
            _redis_client = aioredis.from_url(
                settings.REDIS_URL,
                encoding="utf-8",
                decode_responses=True,
            )
        except Exception:
            _redis_client = False
    return _redis_client if _redis_client is not False else None


class RateLimiter:
    """Sliding window rate limiter per client IP."""

    def __init__(self, requests_per_minute: int = 5, window_seconds: int = 60):
        self.max_requests = requests_per_minute
        self.window_seconds = window_seconds

    async def __call__(self, request: Request):
        client_ip = (
            request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
            or request.headers.get("X-Real-IP")
            or (request.client.host if request.client else "127.0.0.1")
        )
        key = f"rate_limit:auth:{client_ip}"
        now = time.time()
        window_start = now - self.window_seconds

        redis = await get_redis_client()
        if redis:
            try:
                pipe = redis.pipeline()
                pipe.zremrangebyscore(key, 0, window_start)
                pipe.zadd(key, {str(now): now})
                pipe.zcard(key)
                pipe.expire(key, self.window_seconds)
                results = await pipe.execute()
                current_count = results[2]

                if current_count > self.max_requests:
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="Too many login/registration attempts. Please wait a minute before trying again.",
                        headers={"Retry-After": str(self.window_seconds)},
                    )
                return
            except HTTPException:
                raise
            except Exception:
                pass  # Fall back to in-memory store if Redis operation fails

        # In-memory fallback
        history = _in_memory_store.get(client_ip, [])
        history = [t for t in history if t > window_start]
        history.append(now)
        _in_memory_store[client_ip] = history

        if len(history) > self.max_requests:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many login/registration attempts. Please wait a minute before trying again.",
                headers={"Retry-After": str(self.window_seconds)},
            )


# Default rate limiter for authentication endpoints: 5 attempts per minute
auth_rate_limiter = RateLimiter(requests_per_minute=5, window_seconds=60)
