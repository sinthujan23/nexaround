from fastapi import APIRouter, UploadFile, File, HTTPException
from app.services.ai_service import ai_service
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
