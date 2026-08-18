import asyncio
import logging
import math
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.settings_service import SettingsService
from app.services import telemetry, spend_guard

router = APIRouter(tags=["Proxy API"])


# Maps a proxied path onto the operation name and billing SKU it corresponds
# to. Kept here rather than inside telemetry so the proxy owns its own routing
# knowledge; the SKU strings must match rows in api_sku_rates.
_GOOGLE_MAPS_SKUS = (
    ("place/findplacefromtext", "findplacefromtext", "find_place_atmosphere"),
    ("place/nearbysearch",      "nearby_search",     "nearby_search_legacy"),
    ("place/autocomplete",      "autocomplete",      "autocomplete_per_request"),
    ("place/details",           "place_details",     "place_details"),
    ("place/photo",             "place_photo",       "place_photo"),
    ("directions",              "directions",        "directions"),
    ("geocode",                 "geocode",           "geocoding"),
)


# Coordinates are snapped to ~500m before hashing, the same grid
# place_cache_service uses. Without this, two users standing metres apart
# asking for the same landmark produce different keys and the duplicate
# detector sees nothing — which is exactly how 45% of Find Place spend went
# unnoticed: `locationbias` embeds raw GPS, so no two requests ever matched.
_GRID = 0.005


def _snap(value: str) -> str:
    try:
        return f"{math.floor(float(value) / _GRID) * _GRID:.4f}"
    except (TypeError, ValueError):
        return "?"


def _snap_pair(latlng: str) -> str:
    parts = (latlng or "").split(",")
    if len(parts) != 2:
        return "?"
    return f"{_snap(parts[0])},{_snap(parts[1])}"


def _google_maps_cache_key(path: str, params: dict) -> str | None:
    """Normalised identity of a proxied Google Maps call.

    This is what the duplicates panel groups on, so it must ignore everything
    that does not change the answer — the API key, exact GPS, field ordering.
    """
    q = {k: v for k, v in params.items() if k != "key"}
    if path.startswith("place/findplacefromtext"):
        bias = q.get("locationbias", "")
        snapped = _snap_pair(bias.split("@")[-1]) if "@" in bias else ""
        return f"fpt:{(q.get('input') or '').strip().lower()}|{snapped}"
    if path.startswith("directions"):
        return (f"dir:{_snap_pair(q.get('origin',''))}>"
                f"{_snap_pair(q.get('destination',''))}|{q.get('mode','driving')}")
    if path.startswith("geocode"):
        return f"geo:{_snap_pair(q.get('latlng','')) if q.get('latlng') else (q.get('address') or '').strip().lower()}"
    if path.startswith("place/details"):
        return f"pd:{q.get('place_id') or q.get('placeid') or '?'}"
    if path.startswith("place/nearbysearch"):
        return (f"nbl:{_snap_pair(q.get('location',''))}|"
                f"{q.get('type','all')}|r{q.get('radius','?')}")
    if path.startswith("place/autocomplete"):
        return f"ac:{(q.get('input') or '').strip().lower()}"
    if path.startswith("place/photo"):
        ref = q.get("photo_reference") or q.get("photoreference") or "?"
        return f"photo:{ref[:180]}:{q.get('maxwidth','?')}"
    return None


def _classify_google_maps_path(path: str) -> tuple[str, str | None]:
    """Resolve a proxied Google Maps path to (operation, sku)."""
    for prefix, operation, sku in _GOOGLE_MAPS_SKUS:
        if path.startswith(prefix):
            return operation, sku
    # Unknown path: still recorded, but with no SKU so it cannot silently
    # invent a cost. Shows up in the dashboard as an unpriced operation.
    return path.split("/")[0] or "unknown", None

@router.get("/config/keys")
async def get_config_keys(
    db: AsyncSession = Depends(get_db),
):
    """Retrieve public client SDK keys (Mapbox token, Google Maps key).

    These are public-facing SDK keys that the mobile app needs at startup
    before the user has authenticated (e.g. to render map tiles). They are
    NOT secret server-side keys, so no Bearer token is required.
    """
    settings = SettingsService(db)
    mapbox_token = await settings.get_setting("mapbox_access_token")
    google_maps_key = await settings.get_setting("google_maps_api_key")
    return {
        "mapbox_access_token": mapbox_token,
        "google_maps_api_key": google_maps_key
    }

@router.post("/proxy/gemini/generate")
async def proxy_gemini_generate(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Proxy Gemini generative AI requests securely."""
    settings = SettingsService(db)
    raw_key = await settings.get_setting("gemini_api_key")
    api_key = (raw_key or "").strip().strip('"').strip("'")
    if not api_key:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")

    # Gemini Flash models rotate through transient 503 "high demand" — which one
    # is overloaded changes minute to minute. Try a chain of Flash models so a 503
    # on one model falls through to another that's currently healthy without incurring Pro costs.
    models = [
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-1.5-flash",
    ]
    async with httpx.AsyncClient() as client:
        try:
            resp = None
            for i, model in enumerate(models):
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
                # One row per model attempted, so the fallback chain is visible:
                # a 2.5-flash overload that silently lands on 1.5-flash is a
                # quality change worth being able to see.
                async with telemetry.track(
                    "gemini", f"generate_content:{model}",
                    sku="gemini_flash_generate",
                ) as t:
                    resp = await client.post(
                        url,
                        json=payload,
                        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                        timeout=120.0
                    )
                    t.upstream(resp)
                if resp.status_code != 200 and i < len(models) - 1:
                    # Do not retry on key invalidity (400/401/403) or quota exhaustion (429)
                    if resp.status_code in [400, 401, 403, 429]:
                        break
                    logging.warning(f"Model {model} returned status {resp.status_code}. Retrying next model...")
                    continue
                break
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except Exception as e:
            raise HTTPException(status_code=500, detail="Proxy request failed. Please try again.")

@router.get("/proxy/mapbox/directions/{path:path}")
async def proxy_mapbox_directions(
    path: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Proxy Mapbox Directions requests securely."""
    settings = SettingsService(db)
    token = await settings.get_setting("mapbox_access_token")
    if not token:
        raise HTTPException(status_code=500, detail="Mapbox Access Token not configured")

    params = dict(request.query_params)
    profile = params.pop("profile", "driving")
    if profile not in ["driving", "walking", "cycling", "driving-traffic"]:
        profile = "driving"
    params["access_token"] = token

    url = f"https://api.mapbox.com/directions/v5/mapbox/{profile}/{path}"

    async with httpx.AsyncClient() as client:
        try:
            async with telemetry.track(
                "mapbox", f"directions:{profile}",
                sku="mapbox_directions",
                cache_key=f"mbdir:{profile}:{path}",
            ) as t:
                resp = await client.get(url, params=params, timeout=30.0)
                t.upstream(resp)
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail="Proxy request failed. Please try again.")

@router.get("/proxy/google-maps/{path:path}")
async def proxy_google_maps(
    path: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Proxy Google Maps, Places, and Directions requests securely."""
    settings = SettingsService(db)
    api_key = await settings.get_setting("google_maps_api_key")
    if not api_key:
        raise HTTPException(status_code=500, detail="Google Maps API Key not configured")

    params = dict(request.query_params)
    params["key"] = api_key

    url = f"https://maps.googleapis.com/maps/api/{path}"

    operation, sku = _classify_google_maps_path(path)

    # Degrade rather than spend. Past the budget or the caller's daily cap we
    # return 429 with an explanation instead of buying another call — the app
    # already treats a non-200 here as "show what you have".
    try:
        await spend_guard.check(current_user.id)
    except spend_guard.SpendBlocked as blocked:
        raise HTTPException(
            status_code=429,
            detail=blocked.detail,
            headers={"X-Spend-Blocked": blocked.reason},
        )

    async with httpx.AsyncClient() as client:
        try:
            if "place/photo" in path:
                async with telemetry.track(
                    "google_maps", operation, sku=sku, params=params,
                    cache_key=_google_maps_cache_key(path, params),
                ) as t:
                    # Stream image bytes to avoid loading entire binary in memory
                    req = client.build_request("GET", url, params=params)
                    resp = await client.send(req, stream=True)
                    t.upstream(resp)
                    return StreamingResponse(
                        resp.aiter_bytes(),
                        status_code=resp.status_code,
                        headers={
                            "Content-Type": resp.headers.get("Content-Type", "image/jpeg"),
                            "Cache-Control": resp.headers.get("Cache-Control", "public, max-age=86400")
                        }
                    )
            else:
                async with telemetry.track(
                    "google_maps", operation, sku=sku, params=params,
                    cache_key=_google_maps_cache_key(path, params),
                ) as t:
                    resp = await client.get(url, params=params, timeout=30.0)
                    t.upstream(resp)
                    return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail="Proxy request failed. Please try again.")


@router.get("/proxy/geoapify/reverse")
async def proxy_geoapify_reverse(
    lat: float,
    lng: float,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Reverse-geocode lat/lng via Geoapify (with fallback to Mapbox/Google) and return a human-readable location name and district."""
    settings = SettingsService(db)
    api_key = await settings.get_setting("geoapify_api_key")

    # Snapped to the same ~500m grid the place cache uses, so the dashboard can
    # tell repeated reverse-geocodes of one neighbourhood from genuine movement.
    geo_key = f"rev:{lat:.3f}:{lng:.3f}"

    if api_key:
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                async with telemetry.track(
                    "geoapify", "geocode_reverse",
                    sku="geoapify_reverse", cache_key=geo_key,
                ) as t:
                    resp = await client.get(
                        "https://api.geoapify.com/v1/geocode/reverse",
                        params={"lat": lat, "lon": lng, "apiKey": api_key, "format": "json", "lang": "en"}
                    )
                    t.upstream(resp)
                resp.raise_for_status()
                data = resp.json()

                results = data.get("results", [])
                if results:
                    props = results[0]
                    name = (
                        props.get("suburb")
                        or props.get("quarter")
                        or props.get("neighbourhood")
                        or props.get("city_district")
                        or props.get("city")
                        or props.get("county")
                        or props.get("state")
                        or props.get("country")
                        or "Nearby"
                    )
                    district = (
                        props.get("county")
                        or props.get("city_district")
                        or props.get("state_district")
                        or props.get("state")
                        or props.get("city")
                        or "Nearby"
                    )
                    country = props.get("country") or "Nearby"
                    return {"location_name": name, "district": district, "country": country}
            except Exception as e:
                # If Geoapify request fails, fall back to Mapbox
                pass

    # Fallback 1: Mapbox Geocoding
    mapbox_token = await settings.get_setting("mapbox_access_token")
    if mapbox_token:
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                # Fallback tier 1 — reached only when Geoapify failed. A rising
                # count here means the primary provider is degrading.
                async with telemetry.track(
                    "mapbox", "geocode_reverse_fallback",
                    sku="mapbox_geocoding", cache_key=geo_key,
                ) as t:
                    resp = await client.get(
                        f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json",
                        params={
                            "access_token": mapbox_token,
                            "types": "neighborhood,locality,place,address",
                            "limit": 1
                        }
                    )
                    t.upstream(resp)
                resp.raise_for_status()
                data = resp.json()
                features = data.get("features", [])
                if features:
                    feature = features[0]
                    name = feature.get("text") or feature.get("place_name", "").split(",")[0] or "Nearby"
                    context = feature.get("context", [])
                    district = "Nearby"
                    country = "Nearby"
                    for item in context:
                        id_str = item.get("id", "")
                        if "district" in id_str or "region" in id_str or "place" in id_str:
                            district = item.get("text")
                        if "country" in id_str:
                            country = item.get("text", "Nearby")
                    if district == "Nearby":
                        district = name
                    return {"location_name": name, "district": district, "country": country}
            except Exception as e:
                pass

    # Fallback 2: Google Geocoding
    google_maps_key = await settings.get_setting("google_maps_api_key")
    if google_maps_key:
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                # Fallback tier 2 — the only paid step in this chain, so it is
                # the one that matters if the chain starts falling through.
                async with telemetry.track(
                    "google_maps", "geocode_reverse_fallback",
                    sku="geocoding", cache_key=geo_key,
                ) as t:
                    resp = await client.get(
                        "https://maps.googleapis.com/maps/api/geocode/json",
                        params={
                            "latlng": f"{lat},{lng}",
                            "key": google_maps_key
                        }
                    )
                    t.upstream(resp)
                resp.raise_for_status()
                data = resp.json()
                results = data.get("results", [])
                if results:
                    result = results[0]
                    name = "Nearby"
                    district = "Nearby"
                    country = "Nearby"
                    for component in result.get("address_components", []):
                        types = component.get("types", [])
                        if "locality" in types or "sublocality" in types:
                            name = component.get("long_name")
                        if "administrative_area_level_2" in types:
                            district = component.get("long_name")
                        if "country" in types:
                            country = component.get("long_name")
                    if name == "Nearby" and result.get("formatted_address"):
                        name = result.get("formatted_address").split(",")[0]
                    if district == "Nearby":
                        district = name
                    return {"location_name": name, "district": district, "country": country}
            except Exception as e:
                pass

    return {"location_name": "Nearby", "district": "Nearby", "country": "Nearby"}

