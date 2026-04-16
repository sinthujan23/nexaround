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

ai_service = AIService()
