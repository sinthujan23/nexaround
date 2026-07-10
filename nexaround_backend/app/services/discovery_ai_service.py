import asyncio
import re
import logging
import httpx
from typing import Optional
from app.services import google_places_client

logger = logging.getLogger(__name__)

_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-flash-latest",
    "gemini-2.5-pro",
]


def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


def _haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    import math
    p = math.pi / 180
    a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lng2 - lng1) * p)) / 2
    return 12742000 * math.asin(math.sqrt(a)) # meters


def extract_place_names(text: str) -> list[str]:
    matches = re.findall(r'\[\[([^\]]+)\]\]', text)
    return list(dict.fromkeys(m.strip() for m in matches))


async def place_exists(
    place_name: str,
    location_context: str,
    center_lat: float,
    center_lng: float,
) -> bool:
    query_str = f"{place_name} {location_context}"
    logger.info(f"🔍 PlaceVerifier: Querying Google Places for '{query_str}'")
    try:
        results = await google_places_client.text_search(
            query=query_str,
            latitude=center_lat,
            longitude=center_lng,
        )
        if not results:
            logger.info(f"🔍 PlaceVerifier: '{place_name}' NOT found in Google Maps. Flagging as invalid.")
            return False

        for result in results:
            location = result.get("location") or {}
            lat = location.get("latitude")
            lng = location.get("longitude")
            if lat is not None and lng is not None:
                dist_m = _haversine_distance(center_lat, center_lng, lat, lng)
                logger.info(f"🔍 PlaceVerifier: Found '{place_name}' at ({lat}, {lng}). Distance: {dist_m/1000:.2f} km")
                if dist_m <= 25000: # 25km radius check
                    logger.info(f"🔍 PlaceVerifier: '{place_name}' is within 25km (valid).")
                    return True
        logger.info(f"🔍 PlaceVerifier: '{place_name}' found but was TOO FAR (>25km). Flagging as invalid.")
        return False
    except Exception as e:
        logger.error(f"🔍 PlaceVerifier: Error checking place '{place_name}': {e}")
        # Allow place through on error to avoid breaking display
        return True


async def find_hallucinated_places(
    text: str,
    location_context: str,
    center_lat: float,
    center_lng: float,
) -> set[str]:
    places = extract_place_names(text)
    if not places:
        return set()

    hallucinated = set()

    async def verify(place):
        valid = await place_exists(place, location_context, center_lat, center_lng)
        if not valid:
            hallucinated.add(place)

    await asyncio.gather(*(verify(p) for p in places))
    return hallucinated


def filter_hallucinated_stops(ai_response: str, hallucinated_places: set[str]) -> str:
    if not hallucinated_places:
        return ai_response

    result = ai_response
    for place in hallucinated_places:
        paragraphs = re.split(r'\n(?=[-*]|\d+\.|##|###|\*\*)', result)
        filtered = [
            p for p in paragraphs
            if f"[[{place}]]" not in p and f"**{place}**" not in p
        ]
        result = "\n".join(filtered)
    return result.strip()


def clean_raw_urls(text: str) -> str:
    lines = text.split("\n")
    cleaned_lines = []
    for line in lines:
        lower = line.lower()
        if (
            "google.com/maps" in lower
            or "maps.google" in lower
            or "http://" in lower
            or "https://" in lower
        ):
            continue
        cleaned_lines.append(line)
    return "\n".join(cleaned_lines)


def _build_prompt(
    location: str,
    mode: str,
    date_str: str,
    time_str: str,
    weather: str,
    time_available: str,
    mood: str,
    budget: str,
    companions: str,
) -> str:
    return f"""# NexAround AI Discovery Engine

You are **NexAround**, an AI Discovery Companion.

Your purpose is simple:
Help people discover what they should do next.
Don't just recommend famous places. Create experiences that feel personal, timely, and worth remembering.
Think like a local friend, an experienced travel concierge, and an intelligent AI assistant.

# User Context

Current Location:
{location}

CRITICAL BOUNDARY REQUIREMENT:
You MUST ONLY recommend places, attractions, restaurants, and activities that are located in or extremely close to (strictly within a 15km radius of) {location}.
Do NOT recommend places in other cities, even if they are in the same country. For example, if the current location is Kinniya, you must NOT recommend places in Colombo or Trincomalee. Focus purely on local, nearby options. If there are few commercial attractions, suggest scenic views, local bridges, local beaches, local street food spots, nature walks, or community spaces in {location}.

Current Date:
{date_str}

Current Time:
{time_str}

Weather:
{weather}

Temperature:
Auto-detect

Time Available:
{time_available}

Mood:
{mood}

Discovery Mode:
{mode}

Budget:
{budget}

Travelling With:
{companions}

Transportation:
Determine automatically (walking, driving or public transport).

Also consider whenever available:
• Current traffic
• Opening hours
• Weather forecast
• Public holidays
• Local events
• Sunset time
• Seasonal experiences
• Temporary closures

# Discovery Modes

Adapt recommendations based on the selected mode.
• Explore – A balanced day with a mix of popular and lesser-known experiences.
• Hidden Gems – Focus on places locals love.
• Food Quest – Build the itinerary around authentic local food.
• Photo Hunt – Prioritize scenic viewpoints and beautiful lighting.
• Rainy Day – Suggest experiences that are better in the rain.
• Scenic Drive – Choose beautiful routes and viewpoints.
• Culture – Heritage, architecture, museums and local stories.
• Family – Comfortable for all ages.
• Romantic – Relaxed and memorable experiences.
• Surprise Me – Recommend places most visitors never discover.

# Build the Best Day

Create the most enjoyable itinerary by:
- Minimizing travel time
- Grouping nearby places together
- Avoiding unnecessary backtracking
- Keeping a relaxed pace
- Including natural breaks for food or coffee
- Considering the weather
- Making the day feel effortless

Recommend between 4 and 7 stops, depending on the available time.
Choose places because they are the best fit today, not because they are famous.

# Output Format

🌟 Today's Discovery
Give the itinerary an engaging title.
Then explain in 2–3 sentences why this plan is perfect for today.

Your Journey
For each stop, format it exactly like this example (using `###` for the stop title, and nested bullet points starting with `* **Field name:**`):

### **Stop 1: [[Place Name]]**
* **Time:** [Arrival Time]
* **Time to Spend:** [Duration]
* **Estimated Cost:** [Cost]
* **Travel Time from Previous Stop:** [Travel Time]
* **Why You'll Love It:** [Short, friendly explanation.]
* **Don't Miss:** [A unique experience or local tip.]
* **Nearby Food:** [One recommended café, restaurant or local specialty.]

Before You Go
Include:
- 🍽 Must-Try Food
- ☕ Best Coffee Stop
- 📸 Best Photo Spot
- 🌅 Best Sunset Location (if applicable)
- 💰 Estimated Budget
- 🚗 Total Travel Distance
- ⏳ Total Travel Time

If it starts raining:
Suggest the best indoor alternative.

If traffic becomes heavy:
Reorder the itinerary.

If a place is closed:
Recommend the next best nearby experience.

# Style

Write naturally and conversationally.
Avoid generic tourism language.
Keep descriptions short and engaging.
Use actual place names. Only recommend real, existing places that can be found on Google Maps. Do NOT invent or hallucinate places.
Do NOT include any raw Google Maps URLs or external HTTP/HTTPS links in your response. Instead, wrap the place names in double brackets like [[Place Name]] so the app can handle opening the map natively.
Make the itinerary feel like it was created by someone who truly knows the city.

# Goal

When the user finishes reading, they should feel:
"I wouldn't have found this on my own—and I can't wait to go."

# CRITICAL INSTRUCTION FOR PARSING:
If you recommend a specific local place, business, or attraction, you MUST wrap its name in double brackets, like [[Place Name]] (e.g. [[South Kitchen + Bar]] or [[Hotel Radhakrishna]]) when writing the "Place Name" section, so they are clickable in the app UI. Also, make sure to use standard Markdown for formatting headers, lists, and bold text. Do not wrap the whole response in a markdown code block.
"""


async def generate_discovery_itinerary(
    *,
    location: str,
    mode: str,
    date_str: str,
    time_str: str,
    weather: str,
    time_available: str,
    mood: str,
    budget: str,
    companions: str,
    api_key: str,
) -> str:
    prompt = _build_prompt(
        location=location,
        mode=mode,
        date_str=date_str,
        time_str=time_str,
        weather=weather,
        time_available=time_available,
        mood=mood,
        budget=budget,
        companions=companions,
    )

    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 4096,
        },
    }
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}

    attempts = _MODELS * 2
    data = None
    async with httpx.AsyncClient(timeout=90.0) as client:
        for i, model in enumerate(attempts):
            resp = await client.post(_model_url(model), json=body, headers=headers)
            if resp.status_code in (429, 500, 503) and i < len(attempts) - 1:
                logger.warning(
                    "Gemini %s for %s — falling through to next model",
                    resp.status_code, model,
                )
                if (i + 1) % len(_MODELS) == 0:
                    await asyncio.sleep(2)
                continue
            resp.raise_for_status()
            data = resp.json()
            break

    candidates = data.get("candidates") or []
    if not candidates:
        raise ValueError("Gemini returned no candidates")
    cand = candidates[0]
    parts = (cand.get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    if not text.strip():
        raise ValueError("Gemini returned no text")
    return text
