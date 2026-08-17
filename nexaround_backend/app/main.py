from fastapi import FastAPI, UploadFile, File, Depends, Request
import asyncio
import logging
import uuid
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from app.core.config import settings
from app.api.v1.router import api_router
from app.services.google_lens_service import google_lens_service
from app.api.deps import get_current_user
from app.models.user import User

from app.core.database import engine, Base

app = FastAPI(
    title="NexAround API",
    description="AI-powered smart tourism companion backend",
    version="0.1.0",
    docs_url="/docs" if settings.ENABLE_DOCS else None,
    redoc_url="/redoc" if settings.ENABLE_DOCS else None,
    openapi_url="/openapi.json" if settings.ENABLE_DOCS else None,
)

# Strong references to the telemetry background loops. asyncio keeps only a
# weak reference to a running task, so without this they can be collected
# mid-flight and the pipeline stops silently.
_background_tasks: list = []


@app.on_event("startup")
async def startup():
    # Import every model module so all tables (incl. broadcasts/notifications/
    # analytics) are registered on Base.metadata before create_all runs.
    import app.models  # noqa: F401
    # Create tables if they don't exist.
    # api_events is excluded deliberately: it is RANGE-partitioned, and
    # create_all would emit a plain CREATE TABLE that then collides with the
    # migration. It is owned by alembic alone.
    # Every telemetry table is owned by alembic, not by create_all. api_events
    # is partitioned and create_all has no DDL for that, and the rest carry
    # seed data (SKU rates, guard settings) and CHECK constraints that only the
    # migration knows about. Letting create_all win the race just means the
    # migration then fails on DuplicateTable with a half-built schema.
    async with engine.begin() as conn:
        managed = [
            t for t in Base.metadata.sorted_tables
            if not t.name.startswith("api_") or t.name == "api_request_logs"
        ]
        await conn.run_sync(Base.metadata.create_all, tables=managed)

    # Telemetry: make sure this month's partition exists before anything tries
    # to write, then start the background loops.
    #
    # Task handles go in a module-level list, NOT on app.state: the
    # `import app.models` above binds the name `app` in this function's scope to
    # the *package*, shadowing the FastAPI instance, so `app.state` raises here.
    # Keeping a reference matters regardless — asyncio only holds a weak one and
    # will happily garbage-collect a running task.
    from app.services import telemetry, telemetry_rollup, telemetry_alerts
    await telemetry.ensure_partitions()
    _background_tasks.extend([
        asyncio.create_task(telemetry.flusher_loop()),
        asyncio.create_task(telemetry_rollup.rollup_loop()),
        asyncio.create_task(telemetry_rollup.maintenance_loop()),
        asyncio.create_task(telemetry_alerts.alert_loop()),
    ])

    # Seed default system settings
    from app.core.database import async_session
    from app.services.settings_service import SettingsService
    async with async_session() as db:
        service = SettingsService(db)
        # Check if keys are set, if not seed defaults (placeholder empty strings)
        google_maps_key = await service.get_setting("google_maps_api_key")
        if not google_maps_key:
            await service.set_setting(
                "google_maps_api_key",
                "",
                "Google Maps API Key for Geocoding, Places, and Directions"
            )
        
        mapbox_token = await service.get_setting("mapbox_access_token")
        if not mapbox_token:
            await service.set_setting(
                "mapbox_access_token",
                "",
                "Mapbox Public Access Token for SDK and Driving Directions"
            )
            
        gemini_key = await service.get_setting("gemini_api_key")
        if not gemini_key:
            await service.set_setting(
                "gemini_api_key",
                "",
                "Gemini Generative AI API Key for Chat and Vision Details"
            )

        geoapify_key = await service.get_setting("geoapify_api_key")
        if not geoapify_key:
            await service.set_setting(
                "geoapify_api_key",
                "",
                "Geoapify Geocoding API Key for Reverse Geocoding"
            )

        firebase_sa = await service.get_setting("firebase_service_account_json")
        if firebase_sa is None:
            await service.set_setting(
                "firebase_service_account_json",
                "",
                "Firebase service-account JSON (paste the whole file) for sending push notifications"
            )

# Static files
app.mount("/static", StaticFiles(directory="app/static"), name="static")

# CORS — use explicit trusted origins from environment config.
# When BACKEND_CORS_ORIGINS is configured, allow credentials only for those
# specific origins. When empty (local development), allow all origins but
# WITHOUT credentials to prevent CSRF attacks.
_cors_origins = [str(o) for o in settings.BACKEND_CORS_ORIGINS] if settings.BACKEND_CORS_ORIGINS else []
if _cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
# Request context — must run before anything that emits telemetry, so it is
# registered last (Starlette applies http middleware in reverse order).
@app.middleware("http")
async def bind_request_context(request: Request, call_next):
    from app.core import request_context
    from app.core.rate_limiter import get_client_ip

    request_context.request_id_var.set(uuid.uuid4())
    request_context.user_id_var.set(None)
    try:
        request_context.client_ip_var.set(get_client_ip(request))
    except Exception:
        request_context.client_ip_var.set(None)
    # Sent by the Flutter client so old and new builds are distinguishable in
    # telemetry. Absent for admin panel and server-side traffic.
    request_context.app_version_var.set(
        (request.headers.get("X-App-Version") or None) and
        request.headers["X-App-Version"][:32]
    )
    request_context.platform_var.set(
        (request.headers.get("X-Platform") or None) and
        request.headers["X-Platform"][:16]
    )
    return await call_next(request)


# Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response
# Include routes
app.include_router(api_router)


@app.get("/", tags=["Health"])
async def root():
    """Health check endpoint."""
    return {
        "app": "NexAround API",
        "version": "0.1.0",
        "status": "active",
    }


@app.get("/health", tags=["Health"])
async def health_check():
    """Detailed health check."""
    from app.services import telemetry
    return {
        "status": "healthy",
        "database": "connected",
        "services": {
            "auth": "active",
            "attractions": "active",
        },
        # Surfaced so a silently broken metrics pipeline is visible. Rising
        # dropped_* counters mean events are being lost.
        "telemetry": telemetry.get_stats(),
    }

@app.post("/api/lens/identify")
async def identify_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user)
):
    """Identify an image using Google Lens. Requires authentication."""
    try:
        image_bytes = await file.read()
        result = google_lens_service.identify(image_bytes)
        return JSONResponse(content=result)
    except Exception as e:
        logging.error(f"Lens identify error: {e}")
        return JSONResponse(status_code=500, content={"error": "Image identification failed. Please try again."})
