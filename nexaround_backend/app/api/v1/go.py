"""Partner buttons whose link can only be made when the traveller taps.

The app opens these in the browser, so they carry no auth: the URL itself is
signed by the backend that wrote it into the plan (see atlas.tap_url).
"""
import hashlib

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import RedirectResponse

from app.core.rate_limiter import RateLimiter, get_client_ip, get_redis_client
from app.services.providers import atlas

router = APIRouter(prefix="/go", tags=["Go"])

# Each tap can spend an Atlas quote and a link; a page reloaded in a loop must not.
_tap_limiter = RateLimiter(requests_per_minute=10, window_seconds=60)


async def _too_many(ip: str) -> bool:
    key = f"rate_limit:go_insurance:ip:{ip}"
    try:
        return await _tap_limiter._check_rate_limit(key, await get_redis_client())
    except Exception:
        return await _tap_limiter._check_rate_limit(key, None)


@router.get("/insurance", include_in_schema=False)
async def insurance(request: Request, t: str = ""):
    """The plan's "Get travel insurance" button: HelloSafe, with a tracked link
    made for this traveller. A tap past the rate limit still reaches HelloSafe,
    just untracked."""
    trip = atlas.trip_from_token(t)
    if trip is None:
        raise HTTPException(status_code=404, detail="Not found")
    ip = get_client_ip(request)
    if await _too_many(ip):
        url = atlas.funnel_url(trip)
    else:
        # The same person tapping again within a session's life gets the same link.
        traveller = hashlib.sha256(f"{t}|{ip}".encode("utf-8")).hexdigest()[:24]
        url = await atlas.tap_target(trip, traveller=traveller)
    return RedirectResponse(
        url, status_code=302,
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )
