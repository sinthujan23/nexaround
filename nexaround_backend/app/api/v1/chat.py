from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from app.services.ai_service import ai_service
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter()

class ChatRequest(BaseModel):
    message: str
    context: Optional[str] = ""

class ChatResponse(BaseModel):
    response: str

@router.post("/message", response_model=ChatResponse)
async def send_message(
    request: ChatRequest,
    current_user: User = Depends(get_current_user)
):
    """
    Send a message to the AI Guide and get a response.
    """
    try:
        response_text = await ai_service.get_chat_response(
            message=request.message,
            context=request.context,
            preferences=current_user.preferences
        )
        return ChatResponse(response=response_text)
    except Exception as e:
        import logging
        logging.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail="Chat service temporarily unavailable. Please try again.")
