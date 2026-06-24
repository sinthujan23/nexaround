import asyncio
import httpx
import sys
import os

# Set Python path to find app module
sys.path.append(os.path.abspath(os.path.dirname(__file__)))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Import backend db session and models
try:
    from app.core.config import settings
    from app.models.system_setting import SystemSetting
except ImportError:
    print("❌ Could not import app models! Make sure to run this script from the nexaround_backend directory.")
    sys.exit(1)

async def test_gemini(api_key, category, prompt):
    print(f"\n--- Testing Gemini for {category} ---")
    models = [
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-flash-latest",
        "gemini-2.5-pro",
    ]
    
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ]
    }
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        for model in models:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            try:
                resp = await client.post(url, json=payload, headers={"Content-Type": "application/json"})
                print(f"Model {model} - status: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    text = data['candidates'][0]['content']['parts'][0]['text']
                    print("✅ Success!")
                    print(text[:500] + "\n..." if len(text) > 500 else text)
                    return text
                else:
                    print(f"❌ Failed: {resp.text}")
            except Exception as e:
                print(f"❌ Exception with model {model}: {e}")
    return None

async def test_find_place(api_key, name, lat, lng):
    print(f"\n--- Testing Google Maps Find Place for '{name}' ---")
    url = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
    params = {
        "input": name,
        "inputtype": "textquery",
        "fields": "place_id,name,geometry,rating,user_ratings_total,formatted_address",
        "locationbias": f"circle:50000@{lat},{lng}",
        "key": api_key
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(url, params=params)
            print(f"Status: {resp.status_code}")
            if resp.status_code == 200:
                data = resp.json()
                candidates = data.get("candidates", [])
                print(f"Found {len(candidates)} candidates:")
                for c in candidates:
                    print(f" - ID: {c.get('place_id')} | Name: {c.get('name')} | Address: {c.get('formatted_address')}")
            else:
                print(f"❌ Failed: {resp.text}")
        except Exception as e:
            print(f"❌ Exception: {e}")

async def main():
    # Database connection URL inside docker or local
    db_url = "postgresql+asyncpg://nexaround:nexaround@db:5432/nexaround"
    if len(sys.argv) > 1:
        db_url = sys.argv[1]
        
    print(f"Connecting to database at: {db_url}")
    
    try:
        engine = create_async_engine(db_url)
        async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    except Exception as e:
        print(f"❌ Database Engine initialization failed: {e}")
        return

    google_maps_key = None
    gemini_key = None

    try:
        async with async_session() as session:
            res = await session.execute(select(SystemSetting))
            settings_objs = res.scalars().all()
            print("\nRetrieved Settings:")
            for s in settings_objs:
                val_print = s.value[:20] + "..." if s.value else "None"
                print(f"  {s.key} = {val_print}")
                if s.key == "google_maps_api_key":
                    google_maps_key = s.value
                if s.key == "gemini_api_key":
                    gemini_key = s.value
    except Exception as e:
        print(f"❌ Database query failed: {e}")
        return

    if not google_maps_key:
        print("❌ google_maps_api_key is empty or missing!")
    if not gemini_key:
        print("❌ gemini_api_key is empty or missing!")
        
    if not google_maps_key or not gemini_key:
        print("⚠️ Exiting due to missing configuration keys.")
        return

    # Coordinates near Kinniya
    lat, lng = 8.5204, 81.1897
    
    # 1. Test Attractions Prompt
    attractions_prompt = f"""
Analyse and provide a list for the following categories upto 15 most important places within a radius of 50 kms from ({lat}, {lng}) near Kinniya with distance and direction. 

tourist_attraction, historical_landmark, beach, museum, park, zoo, aquarium, art_gallery, amusement_park, religious_places, casino, movie_theater, bowling_alley, campground, national_park, botanical_garden



Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {{
    "name": "Attraction Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }}
]
"""
    attractions_resp = await test_gemini(gemini_key, "Attractions", attractions_prompt)

    # 2. Test Food Prompt
    food_prompt = f"""
Analyse and provide a list for the following categories upto 15 most important places within a radius of 15 kms from ({lat}, {lng}) near Kinniya with distance and direction. 

restaurant, cafe, bakery, meal_takeaway, meal_delivery, food_shop, bar, night_club, ice_cream_shop, coffee_shop, juice_bar


Respond ONLY with a JSON array containing objects with these fields (do NOT wrap in markdown format, do NOT include conversational text):
[
  {{
    "name": "Food_Name",
    "distance_km": 15.0,
    "direction": "North-East"
  }}
]
"""
    food_resp = await test_gemini(gemini_key, "Food", food_prompt)

    # 3. Test Find Place resolving for a few candidate names
    # (Using Trincomalee district suffix to verify resolving works)
    await test_find_place(google_maps_key, "Koneswaram Temple, Trincomalee", lat, lng)
    await test_find_place(google_maps_key, "Pigeon Island, Trincomalee", lat, lng)
    await test_find_place(google_maps_key, "Dutch Bank Cafe, Trincomalee", lat, lng)

if __name__ == "__main__":
    asyncio.run(main())
