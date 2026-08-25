import asyncio
import hashlib
import json
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
from app.services import telemetry, spend_guard, place_cache_service

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
        # A nearby-biased search and the app's own global (no-location)
        # fallback for the same text must NOT collide here: colliding meant a
        # biased search that legitimately found nothing near the user got
        # negative-cached, and the fallback — which exists precisely to catch
        # a destination far from the user — immediately reused that same
        # cached "nothing" instead of ever running its own unbiased query.
        loc = q.get("location", "")
        loc_part = f"{_snap_pair(loc)}|r{q.get('radius', '?')}" if loc else "global"
        return f"ac:{(q.get('input') or '').strip().lower()}|{loc_part}"
    if path.startswith("place/photo"):
        ref = q.get("photo_reference") or q.get("photoreference") or "?"
        return f"photo:{ref[:180]}:{q.get('maxwidth','?')}"
    return None


# Places API (New) stand-ins for two legacy endpoints. The legacy Places API is
# deprecated, and on this project it is quota-capped: every legacy
# `place/autocomplete` and `place/details` call comes back OVER_QUERY_LIMIT
# ("exceeded your daily request quota for this API") while Places API (New)
# answers the same questions on the same key without complaint — which is why
# /places/search and /places/nearby, already on New, kept working throughout.
#
# The proxy calls New upstream and reshapes the answer back into the legacy
# envelope the app already parses (`predictions[]`, `result{}`), so no client
# release is needed and the cache keys, SKUs and spend accounting are unchanged.
_PLACES_NEW_AUTOCOMPLETE = "https://places.googleapis.com/v1/places:autocomplete"
_PLACES_NEW_DETAILS = "https://places.googleapis.com/v1/places"

# What the app reads off a details result. Requested explicitly because New
# bills by field mask, so asking for everything would cost more than the legacy
# call it replaces.
_DETAILS_FIELD_MASK = (
    "id,displayName,formattedAddress,location,rating,userRatingCount,photos"
)


def _to_legacy_autocomplete(data: dict) -> dict:
    """Reshape a Places API (New) autocomplete answer into the legacy envelope."""
    predictions = []
    for suggestion in data.get("suggestions") or []:
        # `queryPrediction` entries carry no place_id, and the app's next step is
        # always a details lookup by id, so they are dropped rather than shown.
        pred = suggestion.get("placePrediction")
        if not pred:
            continue
        text = (pred.get("text") or {}).get("text") or ""
        fmt = pred.get("structuredFormat") or {}
        main = (fmt.get("mainText") or {}).get("text") or text
        secondary = (fmt.get("secondaryText") or {}).get("text") or ""
        predictions.append({
            "description": text,
            "place_id": pred.get("placeId")
                        or (pred.get("place") or "").replace("places/", ""),
            "structured_formatting": {
                "main_text": main,
                "secondary_text": secondary,
            },
            "types": pred.get("types") or [],
        })
    return {
        "status": "OK" if predictions else "ZERO_RESULTS",
        "predictions": predictions,
    }


def _to_legacy_details(data: dict) -> dict:
    """Reshape a Places API (New) place into the legacy `result` envelope."""
    loc = data.get("location") or {}
    # New names a photo `places/X/photos/Y`; that is exactly what
    # /places/photo already accepts and what google_places_client builds its
    # media URL from, so the reference passes through unchanged.
    photos = [
        {"photo_reference": ph["name"]}
        for ph in (data.get("photos") or [])
        if ph.get("name")
    ]
    return {
        "status": "OK",
        "result": {
            "place_id": data.get("id") or "",
            "name": (data.get("displayName") or {}).get("text") or "",
            "formatted_address": data.get("formattedAddress") or "",
            "geometry": {
                "location": {
                    "lat": loc.get("latitude"),
                    "lng": loc.get("longitude"),
                }
            },
            "rating": data.get("rating"),
            "user_ratings_total": data.get("userRatingCount"),
            "photos": photos,
        },
    }


def _legacy_error(data: dict) -> dict:
    """Carry a New-API error across in the legacy shape, so the app's existing
    "non-OK means show what you have" handling still applies."""
    err = data.get("error") or {}
    return {
        "status": err.get("status") or "UNKNOWN_ERROR",
        "error_message": err.get("message") or "",
        "predictions": [],
    }


async def _google_places_new(
    client: httpx.AsyncClient, path: str, params: dict, api_key: str
) -> tuple[httpx.Response, str]:
    """Serve a legacy Places path off Places API (New).

    Returns the upstream response — so telemetry still reads the real HTTP
    status and any provider-level error out of it — alongside the legacy-shaped
    body to cache and return.
    """
    headers = {"X-Goog-Api-Key": api_key, "Content-Type": "application/json"}

    if path.startswith("place/autocomplete"):
        body: dict = {"input": (params.get("input") or "").strip()}
        if params.get("language"):
            body["languageCode"] = params["language"]
        # A *bias*, never a restriction: the whole point of the app's two-phase
        # search is that a destination far from the user still has to match, so
        # narrowing the search area here would reintroduce the bug the
        # location-aware cache key was added to fix.
        lat, _, lng = (params.get("location") or "").partition(",")
        if lat and lng:
            try:
                body["locationBias"] = {"circle": {
                    "center": {"latitude": float(lat), "longitude": float(lng)},
                    "radius": min(float(params.get("radius") or 50000), 50000.0),
                }}
            except (TypeError, ValueError):
                pass
        resp = await client.post(
            _PLACES_NEW_AUTOCOMPLETE, json=body, headers=headers, timeout=30.0)
        data = resp.json()
        shaped = _legacy_error(data) if "error" in data else _to_legacy_autocomplete(data)
        return resp, json.dumps(shaped)

    place_id = (params.get("place_id") or params.get("placeid") or "").strip()
    place_id = place_id.replace("places/", "")
    resp = await client.get(
        f"{_PLACES_NEW_DETAILS}/{place_id}",
        headers={**headers, "X-Goog-FieldMask": _DETAILS_FIELD_MASK},
        params={"languageCode": params["language"]} if params.get("language") else None,
        timeout=30.0,
    )
    data = resp.json()
    if "error" in data:
        err = _legacy_error(data)
        err.pop("predictions", None)
        return resp, json.dumps(err)
    return resp, json.dumps(_to_legacy_details(data))


# How long a cached answer stays good, per operation. These are properties of
# the data, not guesses: a place's identity and its coordinates do not change,
# a route does when traffic does.
_CACHE_TTL = {
    "findplacefromtext": 14 * 24 * 3600,   # place identity is stable
    "place_details":      7 * 24 * 3600,
    "nearby_search":      7 * 24 * 3600,
    "geocode":           30 * 24 * 3600,   # a coordinate's address does not move
    "autocomplete":           24 * 3600,
    "directions":              1 * 3600,   # traffic-sensitive, keep it short
}
# A provider error is cached only long enough to stop a retry storm. Any longer
# and a restored API key would appear broken until the entry aged out.
_NEGATIVE_TTL = 60


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
        "gemini-2.5-flash-lite",
        "gemini-2.5-pro",
    ]
    # gemini-2.5-flash reasons by default, and reasoning tokens bill at the
    # OUTPUT rate. Across four months this path produced 22.8M output tokens
    # against 977k input — a 23:1 ratio — and was 100% of the platform's bill,
    # while every Google Maps call was covered by the free tier. The equivalent
    # non-thinking SKU shows 115x fewer tokens for the same work.
    #
    # The client controls this payload, so the budget is imposed here rather
    # than trusted to arrive. An explicit thinkingConfig from the caller is
    # respected; absence of one is not treated as consent to reason freely.
    gen_config = payload.setdefault("generationConfig", {})
    if isinstance(gen_config, dict):
        gen_config.setdefault("thinkingConfig", {"thinkingBudget": 0})
        gen_config.setdefault("maxOutputTokens", 2048)
        if payload.get("tools") and "responseMimeType" in gen_config:
            gen_config.pop("responseMimeType", None)

    # Opening the app fires roughly sixteen of these before the user touches
    # anything, and the prompts repeat — the same district asks the same
    # question every launch. Identical prompt in, identical answer out, for six
    # hours. Generation is sampled rather than deterministic, so this trades a
    # little variety for most of the bill; trending copy does not need to be
    # different every time the app is reopened.
    cache_key = None
    try:
        digest = hashlib.sha256(
            json.dumps(payload, sort_keys=True, default=str).encode()
        ).hexdigest()
        cache_key = f"proxy:gemini:v1:{digest}"
    except (TypeError, ValueError):
        pass

    if cache_key:
        cached = await place_cache_service.get_raw(cache_key)
        if cached is not None:
            async with telemetry.track(
                "gemini", "generate_content", sku="gemini_flash_generate",
                cache_key=digest[:32],
            ) as t:
                t.hit("redis")
            return Response(content=cached.encode(), status_code=200,
                            media_type="application/json")

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

            if cache_key and resp is not None and resp.status_code == 200:
                await place_cache_service.set_raw(
                    cache_key, resp.text, ttl=6 * 3600)
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
                cache_key = _google_maps_cache_key(path, params)
                ttl = _CACHE_TTL.get(operation)
                redis_key = f"proxy:gmaps:v1:{cache_key}" if (cache_key and ttl) else None

                async with telemetry.track(
                    "google_maps", operation, sku=sku, params=params,
                    cache_key=cache_key,
                ) as t:
                    if redis_key:
                        hit = await place_cache_service.get_raw(redis_key)
                        if hit is not None:
                            # Served without paying. In the last half hour this
                            # path bought the same six lookups 19-29 times each.
                            t.hit("redis")
                            return Response(content=hit,
                                            status_code=200,
                                            media_type="application/json")

                    # Autocomplete and details are answered by Places API (New)
                    # and translated back; everything else still goes to the
                    # legacy endpoint it was written against.
                    if path.startswith(("place/autocomplete", "place/details")):
                        resp, body = await _google_places_new(
                            client, path, params, api_key)
                    else:
                        resp = await client.get(url, params=params, timeout=30.0)
                        body = resp.text
                    t.upstream(resp)

                    if redis_key and resp.status_code == 200:
                        # For the translated paths the verdict lives in the
                        # reshaped body: Places API (New) reports "found
                        # nothing" as an empty result set with no status field
                        # at all, which read off the raw response would look
                        # like success and get cached for the full day instead
                        # of the minute a negative answer is worth.
                        if path.startswith(("place/autocomplete", "place/details")):
                            status = json.loads(body).get("status")
                        else:
                            status = telemetry._extract_provider_status(resp)
                        if status in (None, "OK"):
                            await place_cache_service.set_raw(redis_key, body, ttl=ttl)
                        elif status == "ZERO_RESULTS":
                            # Worth remembering briefly: a query that matches
                            # nothing is still billed, and the app retries it.
                            await place_cache_service.set_raw(
                                redis_key, body, ttl=_NEGATIVE_TTL)
                    return Response(content=body, status_code=resp.status_code, media_type="application/json")
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

