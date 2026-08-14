from fastapi import APIRouter, UploadFile, File, HTTPException, Depends
from fastapi.responses import JSONResponse
from app.services.ai_service import ai_service
from app.services.google_lens_service import google_lens_service
from app.api.deps import get_current_user
from app.models.user import User
import logging

router = APIRouter()
logger = logging.getLogger(__name__)

@router.post("/identify")
async def identify_object(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user)
):
    """Analyze an uploaded image frame and identify objects. Requires authentication."""
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")
    
    try:
        content = await file.read()
        result = await ai_service.identify_object(content)
        return result
    except Exception as e:
        logger.error(f"Error identifying object: {e}")
        raise HTTPException(status_code=500, detail="Image identification failed. Please try again.")

@router.post("/test-lens")
async def test_lens(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user)
):
    """Test endpoint to verify Lens service is working with a specific image. Requires authentication."""
    try:
        content = await file.read()
        result = google_lens_service.identify(content)
        return JSONResponse(content=result)
    except Exception as e:
        logger.error(f"Lens Test Error: {e}")
        return JSONResponse(status_code=500, content={"error": "Lens identification failed. Please try again."})
