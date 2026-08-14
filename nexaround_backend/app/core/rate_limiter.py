"""Rate limiting dependency for authentication endpoints."""
import time
from typing import Dict, List, Optional
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


def get_client_ip(request: Request) -> str:
    """Extract real client IP address safely, preventing header spoofing bypasses."""
    # 1. Prefer X-Real-IP set by trusted reverse proxy (Nginx)
    real_ip = request.headers.get("X-Real-IP")
    if real_ip and real_ip.strip():
        return real_ip.strip()

    # 2. Extract from X-Forwarded-For:
    # Reverse proxies append real client IP to the END of the chain.
    # The first element split(",")[0] is client-controlled and easily spoofed.
    x_forwarded = request.headers.get("X-Forwarded-For")
    if x_forwarded:
        ips = [ip.strip() for ip in x_forwarded.split(",") if ip.strip()]
        if ips:
            # Use the last IP in the chain appended by the outer edge proxy
            return ips[-1]

    # 3. Direct socket connection IP
    if request.client and request.client.host:
        return request.client.host

    return "127.0.0.1"


class RateLimiter:
    """Sliding window rate limiter per client IP."""

    def __init__(self, requests_per_minute: int = 5, window_seconds: int = 60):
        self.max_requests = requests_per_minute
        self.window_seconds = window_seconds

    async def _check_rate_limit(self, key: str, redis) -> bool:
        """Check sliding window count for a given key. Returns True if limit exceeded."""
        now = time.time()
        window_start = now - self.window_seconds

        if redis:
            pipe = redis.pipeline()
            pipe.zremrangebyscore(key, 0, window_start)
            pipe.zadd(key, {str(now): now})
            pipe.zcard(key)
            pipe.expire(key, self.window_seconds)
            results = await pipe.execute()
            current_count = results[2]
            return current_count > self.max_requests

        # In-memory fallback
        history = _in_memory_store.get(key, [])
        history = [t for t in history if t > window_start]
        history.append(now)
        _in_memory_store[key] = history
        return len(history) > self.max_requests

    async def __call__(self, request: Request):
        client_ip = get_client_ip(request)
        ip_key = f"rate_limit:auth:ip:{client_ip}"

        redis = await get_redis_client()
        limit_exceeded = False

        try:
            limit_exceeded = await self._check_rate_limit(ip_key, redis)
        except Exception:
            # Fall back to in-memory store if Redis operation fails
            limit_exceeded = await self._check_rate_limit(ip_key, None)

        if limit_exceeded:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many login/registration attempts. Please wait a minute before trying again.",
                headers={"Retry-After": str(self.window_seconds)},
            )


# Default rate limiter for authentication endpoints: 5 attempts per minute
auth_rate_limiter = RateLimiter(requests_per_minute=5, window_seconds=60)
