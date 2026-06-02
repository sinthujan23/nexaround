"""Server-side AI "Odyssey" (trip blueprint) generation via Gemini.

Runs on the backend so the long (20-40s) generative call never depends on the
phone staying in the foreground. The output is shaped to match exactly what the
Flutter app's `Odyssey.fromItinerary` expects: the itinerary `items` list is
`[meta, day, day, ...]` where `meta` carries the trip-level fields and each
`day` carries its activities.
"""
import json
import logging
import httpx

logger = logging.getLogger(__name__)

_MODEL = "gemini-2.5-flash"
_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{_MODEL}:generateContent"

_SYSTEM = (
    "You are NexAround's expert local travel designer for Sri Lanka and beyond. "
    "You craft realistic, budget-aware, day-by-day trip blueprints. You always "
    "reply with a single JSON object that matches the requested schema exactly - "
    "no markdown, no commentary, no code fences. Costs must be realistic for the "
    "destination and stay within the user's total budget. Prefer genuine, "
    "well-known places over invented ones."
)


def build_meta_item(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    days: int,
    nights: int,
    summary: str = "",
    budget_split: str = "",
    visa: str = "",
    logistics: str = "",
) -> dict:
    """The `odyssey_meta` header stored as items[0]. Used both for the initial
    'generating' placeholder and for the finished plan."""
    return {
        "kind": "odyssey_meta",
        "destination": destination,
        "mood": mood,
        "budget": budget,
        "currency": currency,
        "days": days,
        "nights": nights,
        "summary": summary,
        "budget_split": budget_split,
        "visa": visa,
        "logistics": logistics,
    }


async def generate_odyssey(
    *,
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
    api_key: str,
) -> tuple[str, list[dict]]:
    """Generate the plan. Returns (title, items) ready to store on an Itinerary.

    Raises on any failure (no Gemini key handled by the caller, network error,
    unparseable response, or an empty plan) so the caller can mark the itinerary
    'failed'.
    """
    prompt = _build_prompt(destination, mood, budget, days, currency)
    # thinking_budget=0 disables gemini-2.5-flash's hidden "thinking" tokens, which
    # otherwise count against maxOutputTokens and were truncating the plan's JSON
    # mid-output (finishReason MAX_TOKENS) -> _parse_json raised "did not return a
    # JSON object". The plan is pure structured output and needs no reasoning. Give
    # it a larger budget than the default so longer multi-day trips fit comfortably.
    text = await _call_gemini(prompt, api_key, max_tokens=8192, thinking_budget=0)
    plan = _parse_json(text)

    g_days = _as_int(plan.get("days"), days)
    nights = _as_int(plan.get("nights"), g_days - 1 if g_days > 1 else 0)
    title = str(plan.get("title") or "Your Odyssey")

    meta = build_meta_item(
        destination=str(plan.get("destination") or destination),
        mood=mood,
        budget=budget,
        currency=str(plan.get("currency") or currency),
        days=g_days,
        nights=nights,
        summary=str(plan.get("summary") or ""),
        budget_split=str(plan.get("budget_split") or ""),
        visa=str(plan.get("visa") or plan.get("visa_status") or ""),
        logistics=_logistics_text(plan.get("logistics")),
    )

    day_items: list[dict] = []
    for d in (plan.get("day_plans") or plan.get("plan") or []):
        if not isinstance(d, dict):
            continue
        activities = []
        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            activities.append({
                "time": str(a.get("time") or ""),
                "name": str(a.get("name") or a.get("attraction_name") or ""),
                "tip": str(a.get("tip") or a.get("note") or ""),
                "cost": str(a.get("cost") or ""),
            })
        day_items.append({
            "kind": "day",
            "day": _as_int(d.get("day"), len(day_items) + 1),
            "theme": str(d.get("theme") or ""),
            "activities": activities,
        })

    if not day_items:
        raise ValueError("Generated plan had no days")

    return title, [meta] + day_items


async def generate_replacement_activity(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    day_no: int,
    theme: str,
    time_slot: str,
    old_name: str,
    reason: str,
    existing_names: list[str],
    api_key: str,
) -> dict:
    """Generate ONE replacement stop for a single activity the user wants
    swapped out (e.g. already visited / not interested). Returns a dict shaped
    like an activity: {time, name, tip, cost}. The original `time_slot` is
    preserved so the day's ordering stays stable.

    Raises on any failure so the caller can surface an error to the user.
    """
    prompt = _build_swap_prompt(
        destination=destination,
        mood=mood,
        budget=budget,
        currency=currency,
        day_no=day_no,
        theme=theme,
        time_slot=time_slot,
        old_name=old_name,
        reason=reason,
        existing_names=existing_names,
    )
    # thinking_budget=0 disables gemini-2.5-flash's hidden "thinking" tokens —
    # they otherwise eat the output budget and can leave zero text for a small
    # task like this. A single activity needs no reasoning, so turn it off.
    text = await _call_gemini(prompt, api_key, max_tokens=2048, thinking_budget=0)
    data = _parse_json(text)

    name = str(data.get("name") or data.get("attraction_name") or "").strip()
    if not name:
        raise ValueError("Replacement had no place name")

    return {
        "time": time_slot or str(data.get("time") or ""),
        "name": name,
        "tip": str(data.get("tip") or data.get("note") or ""),
        "cost": str(data.get("cost") or ""),
    }


def _build_swap_prompt(
    *,
    destination: str,
    mood: str,
    budget: float,
    currency: str,
    day_no: int,
    theme: str,
    time_slot: str,
    old_name: str,
    reason: str,
    existing_names: list[str],
) -> str:
    avoid = ", ".join(n for n in existing_names if n) or "(none)"
    why = reason.strip() or "the traveler wants a different option"
    slot = time_slot or "this time slot"
    return f"""A traveler is on a {mood} trip to {destination} (total budget {int(budget)} {currency}).

On Day {day_no} ("{theme}"), one stop needs replacing.
- Stop to replace: "{old_name}" (scheduled for {slot})
- Why replace it: {why}

These places are ALREADY in the trip - do NOT suggest any of them again:
{avoid}

Suggest exactly ONE different, real, well-known place or activity near "{destination}" that:
- fits the day's "{theme}" theme and the "{slot}" time slot,
- matches the "{mood}" travel style,
- keeps within the overall {int(budget)} {currency} budget,
- is NOT in the avoid-list above.

Return ONLY a JSON object with this exact shape (no markdown, no commentary):
{{ "time": "{slot}", "name": "Place or activity name", "tip": "Short practical tip under ~12 words", "cost": "{currency} amount or 'Free'" }}
"""


def _build_prompt(destination: str, mood: str, budget: float, days: int, currency: str) -> str:
    nights = days - 1 if days > 1 else 0
    return f"""Design a {days}-day travel Odyssey.

Trip brief:
- Destination: {destination}
- Travel style / mood: {mood}
- Total budget: {int(budget)} {currency} (this is the hard cap for the whole trip)
- Currency to use in all costs: {currency}

Return ONLY a JSON object with EXACTLY this shape:
{{
  "title": "Evocative 2-4 word trip name",
  "destination": "{destination}",
  "days": {days},
  "nights": {nights},
  "currency": "{currency}",
  "summary": "1-2 sentence overview matching the '{mood}' style.",
  "budget_split": "Short split, e.g. '40% Stay - 30% Food - 30% Experiences'",
  "visa": "One line on visa/entry needs for this destination (or 'No visa info' if domestic).",
  "logistics": ["3-5 short practical tips: transport, money, SIM, entry fees, timing"],
  "day_plans": [
    {{
      "day": 1,
      "theme": "Short day theme",
      "activities": [
        {{ "time": "09:00", "name": "Place or activity name", "tip": "Short practical tip", "cost": "{currency} amount or 'Free'" }}
      ]
    }}
  ]
}}

Rules:
- Produce exactly {days} entries in "day_plans", each with 3-5 activities.
- Keep the SUM of all activity costs within the {int(budget)} {currency} budget.
- Use real, recognisable places near "{destination}".
- Be concise; tips under ~12 words.
"""


async def _call_gemini(prompt: str, api_key: str, max_tokens: int = 4096, thinking_budget=None) -> str:
    generation_config = {
        "temperature": 0.8,
        "maxOutputTokens": max_tokens,
        "responseMimeType": "application/json",
    }
    # thinkingBudget=0 turns off gemini-2.5-flash's hidden reasoning tokens
    # (which count against maxOutputTokens). Pass None to leave it on the default.
    if thinking_budget is not None:
        generation_config["thinkingConfig"] = {"thinkingBudget": thinking_budget}
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "system_instruction": {"parts": [{"text": _SYSTEM}]},
        "generationConfig": generation_config,
    }
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    async with httpx.AsyncClient(timeout=90.0) as client:
        resp = await client.post(_URL, json=body, headers=headers)
        resp.raise_for_status()
        data = resp.json()

    candidates = data.get("candidates") or []
    if not candidates:
        raise ValueError(f"Gemini returned no candidates (feedback={data.get('promptFeedback')})")
    cand = candidates[0]
    parts = (cand.get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    if not text.strip():
        raise ValueError(f"Gemini returned no text (finishReason={cand.get('finishReason')})")
    return text


def _parse_json(raw: str) -> dict:
    raw = (raw or "").strip()
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end > start:
        parsed = json.loads(raw[start:end + 1])
        if isinstance(parsed, dict):
            return parsed
    raise ValueError("Gemini did not return a JSON object")


def _logistics_text(raw) -> str:
    if isinstance(raw, str):
        return raw
    if isinstance(raw, list):
        return "\n".join(f"{i + 1}. {step}" for i, step in enumerate(raw))
    return ""


def _as_int(value, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default
