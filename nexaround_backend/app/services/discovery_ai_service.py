import asyncio
import re
import logging
import httpx
from typing import Optional
from app.services import google_places_client
from app.services import telemetry

logger = logging.getLogger(__name__)

_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
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

You are **NexAround**, an AI Discovery Companion. Help people discover what they should do next — like a local friend, travel concierge, and intelligent assistant combined.

## User Context
- Location: {location}
- Date: {date_str} | Time: {time_str}
- Weather: {weather} | Time Available: {time_available}
- Mood: {mood} | Mode: {mode}
- Budget: {budget} | Companions: {companions}
- Transportation: Auto-detect (walking/driving/public transport)

**CRITICAL:** ONLY recommend places within 15km of {location}. Do NOT recommend places in other cities.

## Discovery Modes
- Explore: Mix of popular + lesser-known
- Hidden Gems: Locals' favorites
- Food Quest: Authentic local food focus
- Photo Hunt: Scenic viewpoints, beautiful lighting
- Rainy Day: Rain-friendly experiences
- Scenic Drive: Beautiful routes and viewpoints
- Culture: Heritage, architecture, museums
- Family: All-ages friendly
- Romantic: Relaxed and memorable
- Surprise Me: Places most visitors never discover

## Build the Best Day
- 4-7 stops based on available time
- Minimize travel, group nearby places
- Include food/coffee breaks
- Consider weather and opening hours
- Choose places that fit TODAY, not just famous ones

## Output Format

🌟 Today's Discovery
[Engaging title + 2-3 sentence overview]

Your Journey

### **Stop N: [[Place Name]]**
* **Time:** [Arrival]
* **Time to Spend:** [Duration]
* **Menu / Highlights:** [Signature dish, specialty, or key highlight]
* **Website / Menu:** [Official website URL if known (e.g. [Official Website](https://...)), or [View Menu / Info](web:[[Place Name]])]
* **Travel Time from Previous Stop:** [Travel Time]
* **Why You'll Love It:** [Short explanation]
* **Don't Miss:** [Unique tip]
* **Nearby Food / Cafe:** [One recommendation]

Before You Go
- 🍽 Must-Try Food | ☕ Best Coffee | 📸 Best Photo Spot
- 🌅 Best Sunset | 🚗 Total Distance | ⏳ Total Travel Time

If rain/traffic/closure: suggest alternatives inline.

## Rules
- Use REAL places findable on Google Maps — do NOT invent places
- Wrap place names in [[double brackets]] for in-app map navigation
- Provide official website / menu link if known
- Do NOT mention estimated prices, currencies, or price tiers
- Write conversationally, not like a generic travel blog
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
            # Reasoning tokens bill as output; see proxy.py. An itinerary is a
            # formatting task, not one that needs the model to think first.
            "thinkingConfig": {"thinkingBudget": 0},
            "temperature": 0.7,
            "maxOutputTokens": 3072,
        },
    }
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}

    # Single pass through Flash models (3 attempts max). The previous _MODELS * 2
    # pattern could fire up to 6 Gemini requests, each billing full input tokens.
    attempts = _MODELS
    data = None
    async with httpx.AsyncClient(timeout=90.0) as client:
        for i, model in enumerate(attempts):
            # One row per model attempted — the fallback chain can fire several
            # requests for a single itinerary, each billing full input tokens.
            async with telemetry.track(
                "gemini", f"discovery_itinerary:{model}",
                sku="gemini_flash_generate",
            ) as t:
                resp = await client.post(_model_url(model), json=body, headers=headers)
                t.upstream(resp)
            if resp.status_code in (429, 500, 503) and i < len(attempts) - 1:
                logger.warning(
                    "Gemini %s for %s — falling through to next model",
                    resp.status_code, model,
                )
                await asyncio.sleep(1)  # brief backoff before trying next model
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
