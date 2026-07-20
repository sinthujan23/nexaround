import asyncio
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.settings_service import SettingsService

router = APIRouter(tags=["Proxy API"])

@router.get("/config/keys")
async def get_config_keys(
    db: AsyncSession = Depends(get_db)
):
    """Retrieve public configuration keys (e.g., Mapbox token)."""
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
    api_key = await settings.get_setting("gemini_api_key")
    if not api_key:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")

    # Gemini Flash models rotate through transient 503 "high demand" — which one
    # is overloaded changes minute to minute. Try a chain so a 503 on one model
    # falls through to another that's currently healthy, keeping Neva responsive.
    models = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
    ]
    await settings.log_api_request("gemini", "/v1beta/models/gemini-2.5-flash:generateContent", current_user.id)

    async with httpx.AsyncClient() as client:
        try:
            resp = None
            for i, model in enumerate(models):
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
                resp = await client.post(
                    url,
                    json=payload,
                    headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                    timeout=120.0
                )
                if resp.status_code != 200 and i < len(models) - 1:
                    # Do not retry on key invalidity (400/401/403) or quota exhaustion (429)
                    if resp.status_code in [400, 401, 403, 429]:
                        break
                    print(f"⚠️ Model {model} returned status {resp.status_code}. Retrying next model...")
                    continue
                break
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Proxy error: {str(e)}")

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
    
    # Extract only the first coordinate part of the path for logging summary
    log_endpoint = f"/directions/v5/mapbox/{profile}/{path.split('/')[0]}"
    await settings.log_api_request("mapbox", log_endpoint, current_user.id)

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(url, params=params, timeout=30.0)
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Proxy error: {str(e)}")

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
    
    await settings.log_api_request("google_maps", f"/maps/api/{path}", current_user.id)

    async with httpx.AsyncClient() as client:
        try:
            if "place/photo" in path:
                # Stream image bytes to avoid loading entire binary in memory
                req = client.build_request("GET", url, params=params)
                resp = await client.send(req, stream=True)
                return StreamingResponse(
                    resp.aiter_bytes(),
                    status_code=resp.status_code,
                    headers={
                        "Content-Type": resp.headers.get("Content-Type", "image/jpeg"),
                        "Cache-Control": resp.headers.get("Cache-Control", "public, max-age=86400")
                    }
                )
            else:
                resp = await client.get(url, params=params, timeout=30.0)
                return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Proxy error: {str(e)}")


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

    if api_key:
        await settings.log_api_request("geoapify", "/v1/geocode/reverse", current_user.id)
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    "https://api.geoapify.com/v1/geocode/reverse",
                    params={"lat": lat, "lon": lng, "apiKey": api_key, "format": "json"}
                )
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
        await settings.log_api_request("mapbox", "/geocoding/v5/mapbox.places", current_user.id)
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    f"https://api.mapbox.com/geocoding/v5/mapbox.places/{lng},{lat}.json",
                    params={
                        "access_token": mapbox_token,
                        "types": "neighborhood,locality,place,address",
                        "limit": 1
                    }
                )
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
        await settings.log_api_request("google_maps", "/maps/api/geocode", current_user.id)
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    "https://maps.googleapis.com/maps/api/geocode/json",
                    params={
                        "latlng": f"{lat},{lng}",
                        "key": google_maps_key
                    }
                )
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

