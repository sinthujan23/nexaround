"""Rate limiting dependency for authentication endpoints."""
import ipaddress
import time
from typing import Dict, List, Optional
from fastapi import Request, HTTPException, status
import redis.asyncio as aioredis
from app.core.config import settings

_in_memory_store: Dict[str, List[float]] = {}
_redis_client = None

# Networks whose requests are allowed to set X-Real-IP / X-Forwarded-For.
# Only our own reverse proxy (Nginx, which reaches the app over the Docker
# bridge — gateway 172.22.0.1 — or loopback) sits in these ranges. A request
# arriving from any other peer has its forwarded headers IGNORED and is keyed
# on its real socket address instead, so a client cannot choose its own
# rate-limit bucket by sending a header. Defence in depth behind NA-03: the
# public port is already loopback-only, but the limiter must not rely on that
# single Nginx line to stay safe.
_TRUSTED_PROXY_NETS = [
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
]


def _is_trusted_proxy(host: Optional[str]) -> bool:
    if not host:
        return False
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return any(ip in net for net in _TRUSTED_PROXY_NETS)

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
    """Resolve the client IP used as the rate-limit key.

    Forwarded headers (X-Real-IP / X-Forwarded-For) are only honoured when the
    immediate peer is one of our trusted proxies (_TRUSTED_PROXY_NETS); anyone
    else is keyed on their real socket address, so a caller cannot spoof the
    header to rotate buckets and slip past the limiter (NA-04).
    """
    peer = request.client.host if request.client else None

    if _is_trusted_proxy(peer):
        # Set by Nginx to the true remote address — trusted only because the
        # request actually came from the proxy.
        real_ip = request.headers.get("X-Real-IP")
        if real_ip and real_ip.strip():
            return real_ip.strip()

        # Nginx appends the real client to the END of the chain.
        x_forwarded = request.headers.get("X-Forwarded-For")
        if x_forwarded:
            ips = [ip.strip() for ip in x_forwarded.split(",") if ip.strip()]
            if ips:
                return ips[-1]

    # Untrusted (or unknown) peer: never trust forwarded headers — use the
    # actual socket address.
    return peer or "127.0.0.1"


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


async def check_account_rate_limit(
    identifier: str,
    *,
    action: str,
    max_attempts: int,
    window_seconds: int,
) -> None:
    """Rate-limit by a stable identity (e.g. email) rather than by IP.

    Per-IP limits can be evaded by rotating the source address / proxy header;
    an identity limit cannot, because the identity (the account under attack)
    is part of the request body. This caps password and OTP guessing against
    any single account regardless of where the requests appear to come from
    (NA-04 / NA-05). Caps are deliberately generous so a real user typing a
    wrong code a few times is never affected, while brute-forcing a 6-digit
    code (10^6 guesses) stays infeasible.

    Fails open on any limiter error — availability of login must not depend on
    the limiter — and no-ops on an empty identifier.
    """
    ident = (identifier or "").strip().lower()
    if not ident:
        return
    key = f"rate_limit:acct:{action}:{ident}"
    limiter = RateLimiter(requests_per_minute=max_attempts, window_seconds=window_seconds)
    redis = await get_redis_client()
    try:
        exceeded = await limiter._check_rate_limit(key, redis)
    except Exception:
        try:
            exceeded = await limiter._check_rate_limit(key, None)
        except Exception:
            return
    if exceeded:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts for this account. Please wait a few minutes and try again.",
            headers={"Retry-After": str(window_seconds)},
        )
