from fastapi import APIRouter, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from app.services.ai_service import ai_service
from app.services.google_lens_service import google_lens_service
import logging

router = APIRouter()
logger = logging.getLogger(__name__)

@router.post("/identify")
async def identify_object(file: UploadFile = File(...)):
    """Analyze an uploaded image frame and identify objects."""
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")
    
    try:
        content = await file.read()
        result = await ai_service.identify_object(content)
        return result
    except Exception as e:
        logger.error(f"Error identifying object: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/test-lens")
async def test_lens(file: UploadFile = File(...)):
    """Test endpoint to verify Lens service is working with a specific image."""
    try:
        content = await file.read()
        result = google_lens_service.identify(content)
        return JSONResponse(content=result)
    except Exception as e:
        logger.error(f"Lens Test Error: {e}")
        return JSONResponse(status_code=500, content={"error": str(e)})
