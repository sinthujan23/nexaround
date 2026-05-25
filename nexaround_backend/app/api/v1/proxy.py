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

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    
    await settings.log_api_request("gemini", "/v1beta/models/gemini-2.5-flash:generateContent", current_user.id)
    
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                url,
                json=payload,
                headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                timeout=60.0
            )
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
    """Proxy Mapbox Driving Directions requests securely."""
    settings = SettingsService(db)
    token = await settings.get_setting("mapbox_access_token")
    if not token:
        raise HTTPException(status_code=500, detail="Mapbox Access Token not configured")

    params = dict(request.query_params)
    params["access_token"] = token

    url = f"https://api.mapbox.com/directions/v5/mapbox/driving/{path}"
    
    # Extract only the first coordinate part of the path for logging summary
    log_endpoint = f"/directions/v5/mapbox/driving/{path.split('/')[0]}"
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
