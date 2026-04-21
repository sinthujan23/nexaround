import google.generativeai as genai
from app.core.config import settings

class AIService:
    def __init__(self):
        if settings.GOOGLE_API_KEY:
            genai.configure(api_key=settings.GOOGLE_API_KEY)
            self.model = genai.GenerativeModel('gemini-1.5-flash')
        else:
            self.model = None

    async def get_chat_response(self, message: str, context: str = "", preferences: dict = None):
        if not self.model:
            return "AI Guide is currently offline. Please configure your GOOGLE_API_KEY."
        
        pref_str = f"User Preferences: {preferences}" if preferences else ""
        
        prompt = f"""
        You are 'NexAround AI Guide', a helpful and enthusiastic local tourism expert.
        {pref_str}
        Context about the current area/POI: {context}
        
        User's question: {message}
        
        Provide a concise, engaging response that helps the traveler discover interesting facts or practical tips.
        If user preferences are provided, tailor your advice (e.g., if they like food, mention food facts).
        Keep the tone premium and professional.
        """
        
        try:
            response = self.model.generate_content(prompt)
            return response.text
        except Exception as e:
            return f"I encountered an error while processing your request: {str(e)}"

    async def generate_itinerary(self, location_name: str, attractions_data: str, days: int = 1, preferences: dict = None):
        if not self.model:
            return None
            
        pref_str = f"User Preferences: {preferences}" if preferences else ""
            
        prompt = f"""
        You are 'NexAround AI Trip Planner'. 
        {pref_str}
        Create a detailed {days}-day itinerary for {location_name} using these attractions:
        {attractions_data}
        
        Structure your response as a JSON array of objects, each representing a day.
        Each day should have a 'day' number, a 'theme', and an 'activities' list.
        Each activity should have 'time', 'attraction_name', and 'tip'.
        
        Tailor the itinerary to the user's interests (e.g., focus on food if they are a foodie).
        Return ONLY the valid JSON.
        """
        
        try:
            response = self.model.generate_content(prompt)
            # Basic cleanup in case of markdown formatting
            text = response.text.replace('```json', '').replace('```', '').strip()
            return text
        except Exception as e:
            print(f"AI Generation Error: {e}")
            return None

    async def get_ar_place_details(self, place_name: str, category: str = "", address: str = "", rating: float = 0.0, description: str = ""):
        """Generate structured AR overlay details for a place using AI."""
        if not self.model:
            return {
                "key_facts": [
                    {"icon": "star", "label": "Rating", "value": str(rating)},
                    {"icon": "category", "label": "Type", "value": category or "Attraction"},
                ],
                "short_description": description or f"Discover {place_name} — a remarkable destination.",
                "historical_significance": "Information currently unavailable.",
                "visitor_tips": ["Visit during early morning for the best experience."]
            }
        
        prompt = f"""
        You are 'NexAround AR Guide'. Generate structured details about this place for an AR overlay.
        
        Place: {place_name}
        Category: {category}
        Address: {address}
        Rating: {rating}/5
        Description: {description}
        
        Return a valid JSON object with:
        {{
            "key_facts": [
                {{"icon": "building", "label": "Built", "value": "year or N/A"}},
                {{"icon": "height", "label": "Height/Size", "value": "measurement or N/A"}},
                {{"icon": "visitors", "label": "Annual Visitors", "value": "number or N/A"}},
                {{"icon": "feature", "label": "Key Feature", "value": "brief text"}}
            ],
            "short_description": "2-3 sentence engaging description",
            "historical_significance": "1-2 sentences about history/cultural importance",
            "visitor_tips": ["tip 1", "tip 2", "tip 3"]
        }}
        
        Return ONLY valid JSON, no markdown.
        """
        
        try:
            response = self.model.generate_content(prompt)
            text = response.text.replace('```json', '').replace('```', '').strip()
            import json
            return json.loads(text)
        except Exception as e:
            print(f"AR AI Error: {e}")
            return {
                "key_facts": [
                    {"icon": "star", "label": "Rating", "value": str(rating)},
                    {"icon": "category", "label": "Type", "value": category or "Attraction"},
                ],
                "short_description": description or f"Discover {place_name}.",
                "historical_significance": "A notable destination worth exploring.",
                "visitor_tips": ["Visit during golden hour for the best photos."]
            }

    async def identify_object(self, image_bytes: bytes):
        """Identify an object from camera frame bytes using multimodal AI."""
        if not self.model:
            return "AI Vision is currently offline."
        
        try:
            # Prepare image part for Gemini
            image_parts = [
                {
                    "mime_type": "image/jpeg",
                    "data": image_bytes
                }
            ]
            
            prompt = """
            You are 'NexAround Vision AI'. Identify the primary landmark, building, monument, or object in this photo.
            
            Return a valid JSON object with:
            {
                "object_name": "Name of the object",
                "category": "Landmark/Monument/Nature/etc",
                "significance": "1-2 sentences about what makes this special",
                "interesting_fact": "One surprising/unique fact",
                "accuracy_confidence": 0.0-1.0
            }
            
            If you cannot identify anything specific, try to describe the general scene.
            Return ONLY valid JSON.
            """
            
            response = self.model.generate_content([prompt, image_parts[0]])
            text = response.text.replace('```json', '').replace('```', '').strip()
            import json
            return json.loads(text)
        except Exception as e:
            print(f"Vision AI Error: {e}")
            return {
                "object_name": "Unknown Discovery",
                "category": "Exploration",
                "significance": "We couldn't quite identify this. Try getting closer or improving the lighting.",
                "interesting_fact": "Every corner of the world has a story, continue exploring!",
                "accuracy_confidence": 0.0
            }

ai_service = AIService()
