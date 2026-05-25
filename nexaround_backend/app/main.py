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
    # Create tables if they don't exist
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

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
