from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from app.core.config import settings
from app.api.v1.router import api_router
from app.services.google_lens_service import google_lens_service

from app.core.database import engine, Base

app = FastAPI(
    title="NexAround API",
    description="AI-powered smart tourism companion backend",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

@app.on_event("startup")
async def startup():
    # Import every model module so all tables (incl. broadcasts/notifications/
    # analytics) are registered on Base.metadata before create_all runs.
    import app.models  # noqa: F401
    # Create tables if they don't exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        
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

# CORS — allow all origins during development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    return {
        "status": "healthy",
        "database": "connected",
        "services": {
            "auth": "active",
            "attractions": "active",
        },
    }

@app.post("/api/lens/identify")
async def identify_image(file: UploadFile = File(...)):
    """Identify an image using Google Lens."""
    try:
        image_bytes = await file.read()
        result = google_lens_service.identify(image_bytes)
        return JSONResponse(content=result)
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
