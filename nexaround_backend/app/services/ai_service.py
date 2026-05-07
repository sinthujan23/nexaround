from app.core.config import settings
import json
import logging
from app.services.google_lens_service import google_lens_service

logger = logging.getLogger(__name__)

class AIService:
    def __init__(self):
        # We keep the client for Chat/Itinerary if needed, but remove Vision Fallbacks
        self.client = None
        # Note: If you want to remove Gemini Chat too, we can strip the class further.
        # For now, we only remove it from the identification flow as requested.

    async def identify_object(self, image_bytes: bytes):
        """Identify: Strictly using the optimized Google Lens service."""
        try:
            logger.info("[AI] Starting identification via Google Lens...")
            result = google_lens_service.identify(image_bytes)
            
            if result and result.get("success"):
                # Map the new Google Lens structure to the AR overlay format
                return {
                    "object_name": result["object_name"],
                    "category": "AI Verified",
                    "significance": result["ai_overview"],
                    "interesting_fact": f"Source: {result['source']}",
                    "real_time_info": "Real-time AI Vision",
                    "accuracy_confidence": 0.95
                }
            
            # Fallback for unknown objects
            return {
                "object_name": "Discovery",
                "category": "Scanning",
                "significance": "Scanning the area... Try focusing on a specific landmark or object.",
                "interesting_fact": "Google Lens is analyzing your view.",
                "real_time_info": "Processing...",
                "accuracy_confidence": 0.0
            }
        except Exception as e:
            logger.error(f"Identification Error: {e}")
            return {
                "object_name": "Error",
                "category": "System",
                "significance": f"Vision service error: {str(e)}",
                "interesting_fact": "Check your internet connection.",
                "real_time_info": "Offline",
                "accuracy_confidence": 0.0
            }

ai_service = AIService()
