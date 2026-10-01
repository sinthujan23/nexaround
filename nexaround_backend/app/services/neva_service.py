"""Neva, the in-app travel companion, with real places for "where is…" questions.

The app used to send every Neva message straight through the generic Gemini
proxy, so "is there a money exchange near me?" was answered from the model's
memory: two chain names, "you'll find one conveniently located in your area",
and no address or distance. One of the two names was not among Google's
results near the user at all. The client asked for a map with the answer
(2026-10-01).

Here Neva has one tool, `find_places`. When she decides the user wants to find
a kind of place near them, the backend runs the same Google Places search the
app's search bar uses, around the user's coordinates, and she writes her reply
from those results. The places go back to the app alongside the text, which
pins them on a map under the message. Every other question is answered exactly
as before, in one model call.
"""
from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

from app.services import places_service, spend_guard, telemetry

logger = logging.getLogger(__name__)

# The proxy's chain minus Pro: Pro cannot switch thinking off, and a thinking
# model must echo signed thoughts back with a function result.
_MODELS = ("gemini-2.5-flash", "gemini-2.5-flash-lite")
_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
_TIMEOUT_S = 45.0

# Searched near the user first; widened once when nothing is that close.
_NEAR_RADIUS_M = 3000
_WIDE_RADIUS_M = 10000
_MAX_PLACES = 5

NEVA_SYSTEM_PROMPT = '''
You are Neva — a warm, witty, and effortlessly stylish FEMALE travel companion inside the NexAround app. Think of yourself as the user's smartest, most well-travelled girlfriend, the one who always knows the loveliest spots.

VOICE & PERSONALITY:
- Speak in the first person as a woman — confident, charming, caring, and a little playful. Like texting a close friend, never robotic or formal.
- You're an expert in travel, local food, culture, history, hidden gems, safety, budgeting, and itineraries — but you share it like a friend, not a search engine.

HOW TO FORMAT EVERY REPLY (this controls how beautiful it looks in the app, so follow it):
- Open with ONE short, friendly sentence.
- When you give options or tips, use a clean bullet list. Start each line with "* ", put the key phrase in **bold**, then a short, vivid description. Example:
  * **Cozy wine bar** — perfect for a relaxed, romantic evening. 🍷
  * **Lively rooftop** — great music and a buzzing crowd. ✨
- Keep it skimmable: short lines, no big walls of text.
- Use tasteful, feminine emojis NATURALLY — 1 to 3 per message, never one on every single line. Favourites: ✨🌸💫🌙💖🥂☕🛍️🗺️🌿. Never force them.
- Do NOT use markdown headings (#), tables, or code blocks — only short text, **bold**, and "* " bullets.
- When it feels natural, end with a warm, inviting question.

LOCATION AWARENESS:
- The user's current area and coordinates may be given to you in the context. When they are, tailor every idea and recommendation to THAT area and mention it naturally (e.g. "Since you're around Colombo, ...").
- For "ideas", "plans", "what to do" or "day out" style questions, suggest a few specific, realistic local spots or areas that fit — woven into your answer, not a raw list.
- Never ask the user where they are when their location is already provided in the context.

FINDING PLACES NEAR THE USER:
- When the user wants to find, reach or locate a kind of place near them — a money exchange, ATM, pharmacy, hospital, SIM card shop, supermarket, mosque, petrol station, restaurant, café and so on — ALWAYS call the find_places tool with a short Google Maps search phrase (for example "money exchange" or "pharmacy"). Never answer these from memory.
- After the results come back, recommend the closest two or three BY NAME with their distance, using ONLY the places returned. The app pins every result on a map right under your message, so say so ("I've pinned them on the map below 🗺️").
- If no places were found, say so honestly and suggest what else to try. If the user's location is unknown, ask them to turn on location so you can find places near them.
- Never invent a place, branch, address, distance or opening time.

WHAT YOU NEVER DO:
- Don't dump a long raw list of places unprompted — weave a few specific suggestions in naturally instead.
- Never give generic, copy-paste travel-blog answers — always be specific and personal.
- Never say you are an AI language model or mention Gemini/Google. You are simply Neva.

Your goal: make every traveller feel they have a brilliant, caring local friend who's got their back. 💖
'''.strip()

_FIND_PLACES_TOOL = {
    "function_declarations": [{
        "name": "find_places",
        "description": (
            "Search Google Maps for real places of one kind near the user's "
            "current location, nearest first. Use whenever the user wants to "
            "find or get to a place near them."
        ),
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "query": {
                    "type": "STRING",
                    "description": (
                        "Short Google Maps search phrase for the kind of place, "
                        "without location words: 'money exchange', 'pharmacy', "
                        "'halal restaurant'."
                    ),
                },
            },
            "required": ["query"],
        },
    }],
}


class NevaUnavailable(Exception):
    """Gemini could not be reached on any model; the app falls back to the proxy."""


def _context(latitude: Optional[float], longitude: Optional[float], area: str) -> str:
    """The same location hint the app has always prepended to the question."""
    parts: list[str] = []
    if area and area.strip() and area.strip() != "Nearby":
        parts.append(f"The user is currently in/near {area.strip()}.")
    if latitude is not None and longitude is not None:
        parts.append(f"Their coordinates are {latitude:.5f}, {longitude:.5f}.")
    if parts:
        parts.append(
            "Tailor your suggestions to this area and mention it naturally. "
            "Do not ask the user where they are."
        )
    return " ".join(parts)


def _distance_text(metres: Optional[float]) -> str:
    if metres is None:
        return "distance unknown"
    return f"{metres:,.0f} m" if metres < 1000 else f"{metres / 1000:.1f} km"


async def _generate(body: dict, api_key: str, operation: str) -> dict:
    """One generateContent call, falling through the Flash models on overload."""
    last_status = None
    async with httpx.AsyncClient(timeout=_TIMEOUT_S) as client:
        for model in _MODELS:
            try:
                async with telemetry.track(
                    "gemini", f"{operation}:{model}", sku="gemini_flash_generate",
                ) as t:
                    resp = await client.post(
                        _GEMINI_URL.format(model=model),
                        json=body,
                        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
                    )
                    t.upstream(resp)
            except httpx.HTTPError as e:
                logger.warning("Neva %s on %s failed: %s", operation, model, e)
                continue
            if resp.status_code == 200:
                return resp.json()
            last_status = resp.status_code
            # A bad key or an exhausted quota will not improve on the next model.
            if resp.status_code in (400, 401, 403, 429):
                break
            logger.warning("Neva %s: %s returned %s, trying the next model", operation, model, resp.status_code)
    raise NevaUnavailable(f"Gemini returned {last_status}")


def _parts(data: dict) -> list[dict]:
    try:
        return data["candidates"][0]["content"].get("parts") or []
    except (KeyError, IndexError, TypeError, AttributeError):
        return []


def _text(parts: list[dict]) -> str:
    return "".join(str(p.get("text") or "") for p in parts if isinstance(p, dict)).strip()


def _function_call(parts: list[dict]) -> Optional[dict]:
    for p in parts:
        call = p.get("functionCall") if isinstance(p, dict) else None
        if isinstance(call, dict) and call.get("name") == "find_places":
            return call
    return None


async def find_places(
    query: str, latitude: float, longitude: float, user_id=None,
) -> tuple[list, int]:
    """The nearest real places for `query`: (places, radius searched in metres).

    Within 3 km first, then once within 10 km. Text Search only biases toward
    the circle, so anything returned from outside it is dropped: "near me"
    means near.
    """
    allowed, reason = await spend_guard.allowed(user_id)
    if not allowed:
        logger.info("Neva place search skipped: %s", reason)
        return [], 0
    for radius in (_NEAR_RADIUS_M, _WIDE_RADIUS_M):
        result = await places_service.search(
            query=query, latitude=latitude, longitude=longitude,
            radius_m=radius, near_me=True,
        )
        close = sorted(
            (p for p in result.places if p.distance_m is not None and p.distance_m <= radius),
            key=lambda p: p.distance_m,
        )
        if close:
            return close[:_MAX_PLACES], radius
    return [], _WIDE_RADIUS_M


async def chat(
    message: str,
    *,
    api_key: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    area: str = "",
    user_id=None,
) -> dict[str, Any]:
    """Neva's reply: {"text", "places", "query", "radius_m"}.

    `places` holds `PlaceResponse` objects when she searched, else is empty.
    Raises NevaUnavailable when no model answered.
    """
    context = _context(latitude, longitude, area)
    question = f"Context: {context}\n\nUser Question: {message}" if context else message
    contents: list[dict] = [{"role": "user", "parts": [{"text": question}]}]
    config = {
        "temperature": 0.85,
        "maxOutputTokens": 1024,
        # Reasoning tokens bill at the output rate; see the proxy for the bill
        # that taught this.
        "thinkingConfig": {"thinkingBudget": 0},
    }
    body = {
        "system_instruction": {"parts": [{"text": NEVA_SYSTEM_PROMPT}]},
        "contents": contents,
        "tools": [_FIND_PLACES_TOOL],
        "tool_config": {"function_calling_config": {"mode": "AUTO"}},
        "generationConfig": config,
    }

    first = _parts(await _generate(body, api_key, "neva_chat"))
    call = _function_call(first)
    if call is None:
        return {"text": _text(first), "places": [], "query": "", "radius_m": 0}

    query = str((call.get("args") or {}).get("query") or "").strip()[:80] or message[:80]
    places: list = []
    radius = 0
    if latitude is None or longitude is None:
        result: dict[str, Any] = {"error": "The user's location is unknown."}
    else:
        try:
            places, radius = await find_places(query, latitude, longitude, user_id)
        except Exception as e:
            logger.warning("Neva place search for %r failed: %s", query, e)
            places, radius = [], 0
        result = {
            "query": query,
            "searched_within": _distance_text(radius) if radius else "",
            "places": [
                {
                    "pin": i,
                    "name": p.name,
                    "distance": _distance_text(p.distance_m),
                    "rating": p.rating or None,
                    "reviews": p.review_count or None,
                    "address": p.address or "",
                }
                for i, p in enumerate(places, start=1)
            ],
        }
        if not places:
            result["note"] = "Nothing of this kind was found near the user."

    # The model's own turn goes back verbatim: a part can carry a thought
    # signature that Gemini expects to see again beside the result.
    contents.append({"role": "model", "parts": first})
    contents.append({
        "role": "user",
        "parts": [{"functionResponse": {"name": "find_places", "response": result}}],
    })
    # Answer now; a second search would leave the map showing the first one.
    body["tool_config"] = {"function_calling_config": {"mode": "NONE"}}
    second = _parts(await _generate(body, api_key, "neva_chat_places"))
    logger.info(
        "Neva searched %r near %s,%s: %d place(s) within %d m",
        query, latitude, longitude, len(places), radius,
    )
    return {"text": _text(second), "places": places, "query": query, "radius_m": radius}
