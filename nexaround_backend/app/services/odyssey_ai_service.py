"""Server-side AI "Odyssey" (trip blueprint) generation via Gemini.

Runs on the backend so the long (20-40s) generative call never depends on the
phone staying in the foreground. The output is shaped to match exactly what the
Flutter app's `Odyssey.fromItinerary` expects: the itinerary `items` list is
`[meta, day, day, ...]` where `meta` carries the trip-level fields and each
`day` carries its activities.
"""
import asyncio
import json
import logging
import urllib.parse
import httpx

logger = logging.getLogger(__name__)


def _build_deep_booking_url(
    provider: str,
    item_name: str,
    destination: str,
    start_date: str,
    end_date: str,
    travelers: int = 1,
    is_flight: bool = False,
) -> str:
    prov_lower = (provider or "").lower()
    dest = (destination or "").strip()
    name = (item_name or "").strip()
    query = f"{name} {dest}".strip() if name else dest
    encoded_query = urllib.parse.quote_plus(query)
    encoded_dest = urllib.parse.quote_plus(dest)

    if is_flight:
        if "google" in prov_lower:
            date_q = f"flights from {name or 'origin'} to {dest}"
            if start_date and end_date:
                date_q += f" on {start_date} return {end_date}"
            return f"https://www.google.com/travel/flights?q={urllib.parse.quote_plus(date_q)}"
        elif "skyscanner" in prov_lower:
            if start_date and end_date:
                return f"https://www.skyscanner.com/transport/flights-from/{urllib.parse.quote_plus(name or 'flights')}-to-{encoded_dest}/?outbounddate={start_date}&inbounddate={end_date}&adultsv2={travelers}"
            return f"https://www.skyscanner.com/transport/flights-from/{urllib.parse.quote_plus(name or 'flights')}-to-{encoded_dest}/"
        elif "expedia" in prov_lower:
            if start_date and end_date:
                return f"https://www.expedia.com/Flights-Search?trip=roundtrip&leg1=from:{urllib.parse.quote_plus(name or 'origin')},to:{encoded_dest},departure:{start_date}TANYT&leg2=from:{encoded_dest},to:{urllib.parse.quote_plus(name or 'origin')},departure:{end_date}TANYT&passengers=adults:{travelers}"
            return f"https://www.expedia.com/Flights-Search?destination={encoded_dest}"
        elif "kayak" in prov_lower:
            if start_date and end_date:
                return f"https://www.kayak.com/flights/{urllib.parse.quote_plus(name or 'origin')}-{encoded_dest}/{start_date}/{end_date}/{travelers}adults"
            return f"https://www.kayak.com/flights/{encoded_dest}"
        else:
            return f"https://www.google.com/travel/flights?q={urllib.parse.quote_plus(f'flights to {dest}')}"
    else:  # Hotel
        if "booking" in prov_lower:
            url = f"https://www.booking.com/searchresults.html?ss={encoded_query}"
            if start_date:
                url += f"&checkin={start_date}"
            if end_date:
                url += f"&checkout={end_date}"
            url += f"&group_adults={travelers}"
            return url
        elif "agoda" in prov_lower:
            url = f"https://www.agoda.com/search?text={encoded_query}"
            if start_date:
                url += f"&checkIn={start_date}"
            if end_date:
                url += f"&checkOut={end_date}"
            url += f"&adults={travelers}"
            return url
        elif "expedia" in prov_lower:
            url = f"https://www.expedia.com/Hotel-Search?destination={encoded_query}"
            if start_date:
                url += f"&startDate={start_date}"
            if end_date:
                url += f"&endDate={end_date}"
            url += f"&adults={travelers}"
            return url
        elif "hotels" in prov_lower:
            url = f"https://www.hotels.com/Hotel-Search?destination={encoded_query}"
            if start_date:
                url += f"&startDate={start_date}"
            if end_date:
                url += f"&endDate={end_date}"
            url += f"&adults={travelers}"
            return url
        elif "airbnb" in prov_lower:
            url = f"https://www.airbnb.com/s/{encoded_dest}/homes?query={encoded_query}"
            if start_date:
                url += f"&checkin={start_date}"
            if end_date:
                url += f"&checkout={end_date}"
            url += f"&adults={travelers}"
            return url
        else:
            return f"https://www.google.com/travel/hotels?q={encoded_query}"

# Gemini Flash models rotate through transient 503 "high demand" — WHICH model
# is overloaded changes minute to minute, so retrying one model isn't enough.
# Try a chain: a 503 on one model falls through to another that's healthy now.
_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.5-pro",
]
_MODEL = _MODELS[0]  # kept for any external reference / logging


def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

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
    travelers: int = 1,
    summary: str = "",
    budget_split: str = "",
    visa: str = "",
    logistics: str = "",
    booking_partners: list[dict] = None,
    cover_url: str = "",
    flight_strategies: dict = None,
    hotel_strategies: dict = None,
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
        "travelers": travelers,
        "summary": summary,
        "budget_split": budget_split,
        "visa": visa,
        "logistics": logistics,
        "booking_partners": booking_partners or [],
        "cover_url": cover_url,
        "flight_strategies": flight_strategies or {},
        "hotel_strategies": hotel_strategies or {},
    }


async def fetch_unsplash_cover_photo(destination: str, api_key: str) -> str:
    """Query Unsplash for a random landscape orientation photo matching `destination`.
    Returns the regular URL string, or empty string on failure.
    """
    if not api_key:
        return ""
    try:
        url = "https://api.unsplash.com/photos/random"
        params = {
            "query": destination,
            "orientation": "landscape",
            "client_id": api_key,
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, params=params)
            if response.status_code == 200:
                data = response.json()
                if isinstance(data, dict):
                    urls = data.get("urls") or {}
                    return str(urls.get("regular") or "")
            else:
                logger.error(f"Unsplash API returned status code {response.status_code}: {response.text}")
    except Exception as e:
        logger.error(f"Failed to fetch cover photo from Unsplash: {e}")
    return ""


async def generate_flight_strategies(
    *,
    departure_city: str,
    departure_country: str,
    destination: str,
    days: int,
    budget: float,
    currency: str,
    travelers: int,
    flight_start_date: str = "",
    flight_end_date: str = "",
    api_key: str,
) -> dict:
    """Uses Gemini to generate flight routing strategies, typical budget/local airlines,
    estimated price ranges, and pre-filled search/booking links.
    """
    if not departure_city:
        departure_city = "Nearest Airport"

    date_str = ""
    if flight_start_date and flight_end_date:
        date_str = f"- Departure Date: {flight_start_date}\n- Return Date: {flight_end_date}"

    prompt = f"""Analyze flight options for a trip from "{departure_city}" ({departure_country}) to "{destination}".
The travelers want to find the cheapest flight options.

Trip Details:
- Departure: {departure_city}, {departure_country}
- Destination: {destination}
{date_str}
- Duration: {days} days
- Group Size: {travelers} traveler(s)
- Total Trip Budget: {int(budget)} {currency} (flights should fit or be optimized against this)

Your task is to act as an agentic flight finder. Propose 2-4 distinct, realistic flight strategies.
These can be:
- "direct": Direct flight option (if available) or standard single-carrier route.
- "budget_carrier": Utilizing low-cost carriers (e.g. AirAsia, Scoot, Ryanair, IndiGo, Cinnamon Air, FitsAir, Southwest, etc. depending on region).
- "split_ticket": Booking separate tickets to save money.
- "nearby_airport": Flying into or out of a nearby airport.

For each strategy, estimate realistic price ranges in {currency} (total for all {travelers} travelers combined), specify the booking platform/provider name (e.g. "Expedia", "Skyscanner", "Google Flights", "Kayak"), and generate a pre-filled direct booking/search URL incorporating the dates if provided.

Field Rules:
- "title": Concise 3-6 word strategy name (e.g., "Fly via Expedia Budget Deal").
- "provider_name": Booking platform name (e.g. "Expedia", "Skyscanner", "Kayak", "Google Flights").
- "estimated_savings": Very short tag under 4 words (e.g., "Save ~20%").
- "estimated_price_range": Short price string only (e.g., "USD 180 - 300").
- "route": Short airport code route (e.g., "TRR -> CMB -> MAA").
- "convenience": Star rating string ONLY (e.g., "★★★☆☆").
- "best_months": Short month list under 5 words (e.g., "Jan-Mar, Jul-Sep").
- "booking_url": Real search landing page or booking URL (e.g. Expedia, Skyscanner, Google Flights).

Return ONLY a JSON object with this exact shape:
{{
  "departure_city": "{departure_city}",
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "strategy": "split_ticket",
      "title": "Expedia Split Ticket Option",
      "provider_name": "Expedia",
      "description": "Explanation of how to book this strategy.",
      "estimated_savings": "Save ~35%",
      "estimated_price_range": "{currency} 100,000 - 150,000",
      "airlines": ["Airline A", "Airline B"],
      "route": "CMB -> KUL -> NRT",
      "stops": 1,
      "total_duration": "12h",
      "convenience": "★★★☆☆",
      "tip": "Short booking tip.",
      "booking_url": "https://www.expedia.com/Flights"
    }}
  ],
  "general_tips": [
    "Tip 1...",
    "Tip 2..."
  ]
}}
"""
    try:
        text = await _call_gemini(prompt, api_key, max_tokens=4096, thinking_budget=0)
        data = _parse_json(text)
        strategies = data.get("strategies")
        if isinstance(strategies, list):
            for strat in strategies:
                if isinstance(strat, dict):
                    airlines = strat.get("airlines")
                    if isinstance(airlines, str):
                        strat["airlines"] = [a.strip() for a in airlines.split(",") if a.strip()]
                    elif not isinstance(airlines, list):
                        strat["airlines"] = []
                    else:
                        strat["airlines"] = [str(a) for a in airlines]
                    # Ensure deep pre-filled booking URL
                    provider = strat.get("provider_name") or "Google Flights"
                    item_name = strat.get("title") or destination
                    strat["booking_url"] = _build_deep_booking_url(
                        provider=provider,
                        item_name=item_name,
                        destination=destination,
                        start_date=flight_start_date,
                        end_date=flight_end_date,
                        travelers=travelers,
                        is_flight=True,
                    )
        return data
    except Exception as e:
        logger.error(f"Failed to generate flight strategies: {e}")
        return {}


async def generate_hotel_strategies(
    *,
    destination: str,
    days: int,
    budget: float,
    currency: str,
    travelers: int,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
    api_key: str,
) -> dict:
    """Uses Gemini to generate hotel/accommodation options with pre-filled search/booking links."""
    date_str = ""
    if hotel_check_in_date and hotel_check_out_date:
        date_str = f"- Check-in Date: {hotel_check_in_date}\n- Check-out Date: {hotel_check_out_date}"

    prompt = f"""Analyze accommodation options for a trip to "{destination}".
The travelers want recommended places to stay.

Trip Details:
- Destination: {destination}
{date_str}
- Duration: {days} days
- Group Size: {travelers} traveler(s)
- Total Trip Budget: {int(budget)} {currency}

Your task is to act as an agentic hotel finder. Propose 2-4 distinct, realistic hotel/stay options (e.g. Luxury, Boutique, Budget, Resort, Apartment).
For each option, include:
- Name of hotel or stay category
- Provider name (e.g. "Booking.com", "Agoda", "Expedia", "Hotels.com", "Airbnb")
- Price per night and total estimated stay cost in {currency}
- Rating (e.g. "4.8 ★")
- Top 3 amenities
- Direct search/booking URL for that platform (e.g. https://www.booking.com/searchresults.html?ss={destination})

Return ONLY a JSON object with this exact shape:
{{
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "name": "Hotel / Resort Name",
      "provider_name": "Booking.com",
      "category": "Boutique / Luxury / Budget",
      "rating": "4.7 ★",
      "price_per_night": "{currency} 120",
      "total_estimated_cost": "{currency} 600",
      "location": "City Center",
      "amenities": ["Free WiFi", "Breakfast Included", "Pool"],
      "description": "Short explanation of why this stay fits the trip.",
      "booking_url": "https://www.booking.com/"
    }}
  ],
  "general_tips": [
    "Book at least 2 weeks in advance for best rates."
  ],
  "best_areas": "Central District, Beachfront"
}}
"""
    try:
        text = await _call_gemini(prompt, api_key, max_tokens=4096, thinking_budget=0)
        data = _parse_json(text)
        strategies = data.get("strategies")
        if isinstance(strategies, list):
            for strat in strategies:
                if isinstance(strat, dict):
                    provider = strat.get("provider_name") or "Booking.com"
                    item_name = strat.get("name") or destination
                    strat["booking_url"] = _build_deep_booking_url(
                        provider=provider,
                        item_name=item_name,
                        destination=destination,
                        start_date=hotel_check_in_date,
                        end_date=hotel_check_out_date,
                        travelers=travelers,
                        is_flight=False,
                    )
        return data
    except Exception as e:
        logger.error(f"Failed to generate hotel strategies: {e}")
        return {}


async def generate_odyssey(
    *,
    destination: str,
    mood: str,
    budget: float,
    days: int,
    currency: str,
    travelers: int = 1,
    api_key: str,
    unsplash_api_key: str = "",
    include_flights: bool = False,
    departure_city: str = "",
    departure_country: str = "",
    flight_start_date: str = "",
    flight_end_date: str = "",
    include_hotels: bool = False,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
) -> tuple[str, list[dict]]:
    """Generate the plan. Returns (title, items) ready to store on an Itinerary."""
    prompt = _build_prompt(destination, mood, budget, days, currency, travelers)
    text = await _call_gemini(prompt, api_key, max_tokens=8192, thinking_budget=0)
    plan = _parse_json(text)

    g_days = _as_int(plan.get("days"), days)
    nights = _as_int(plan.get("nights"), g_days - 1 if g_days > 1 else 0)
    title = str(plan.get("title") or "Your Odyssey")

    # Fetch Unsplash cover photo, flight strategies, and hotel strategies concurrently
    final_destination = str(plan.get("destination") or destination)

    async def _get_cover():
        if unsplash_api_key:
            try:
                return await fetch_unsplash_cover_photo(final_destination, unsplash_api_key)
            except Exception as e:
                logger.error(f"Cover photo fetch failed: {e}")
                return ""
        return ""

    async def _get_flights():
        if include_flights and departure_city:
            try:
                return await generate_flight_strategies(
                    departure_city=departure_city,
                    departure_country=departure_country,
                    destination=final_destination,
                    days=g_days,
                    budget=budget,
                    currency=str(plan.get("currency") or currency),
                    travelers=travelers,
                    flight_start_date=flight_start_date or "",
                    flight_end_date=flight_end_date or "",
                    api_key=api_key,
                )
            except Exception as e:
                logger.error(f"Flight strategy sub-job failed: {e}")
                return {}
        return {}

    async def _get_hotels():
        if include_hotels:
            try:
                return await generate_hotel_strategies(
                    destination=final_destination,
                    days=g_days,
                    budget=budget,
                    currency=str(plan.get("currency") or currency),
                    travelers=travelers,
                    hotel_check_in_date=hotel_check_in_date or "",
                    hotel_check_out_date=hotel_check_out_date or "",
                    api_key=api_key,
                )
            except Exception as e:
                logger.error(f"Hotel strategy sub-job failed: {e}")
                return {}
        return {}

    cover_url, flight_strategies, hotel_strategies = await asyncio.gather(
        _get_cover(), _get_flights(), _get_hotels()
    )

    meta = build_meta_item(
        destination=final_destination,
        mood=mood,
        budget=budget,
        currency=str(plan.get("currency") or currency),
        days=g_days,
        nights=nights,
        travelers=travelers,
        summary=str(plan.get("summary") or ""),
        budget_split=str(plan.get("budget_split") or ""),
        visa=str(plan.get("visa") or plan.get("visa_status") or ""),
        logistics=_logistics_text(plan.get("logistics")),
        booking_partners=plan.get("booking_partners") or [],
        cover_url=cover_url,
        flight_strategies=flight_strategies,
        hotel_strategies=hotel_strategies,
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


def _build_prompt(destination: str, mood: str, budget: float, days: int, currency: str, travelers: int = 1) -> str:
    nights = days - 1 if days > 1 else 0
    per_person = int(budget / travelers) if travelers > 0 else int(budget)
    return f"""Design a {days}-day travel Odyssey for a group of {travelers} traveler(s).

Trip brief:
- Destination: {destination}
- Travel style / mood: {mood}
- Group size: {travelers} traveler(s)
- Total budget: {int(budget)} {currency} for the whole group of {travelers} (hard cap for the entire trip; about {per_person} {currency} per person)
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
  "booking_partners": [
    {{ "name": "Agoda", "type": "hotels", "url": "https://www.agoda.com/search?query=Colombo" }},
    {{ "name": "PickMe", "type": "transit", "url": "https://pickme.lk/" }}
  ],
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

Rules for "booking_partners":
- List 3 real, popular travel websites, booking platforms, or local apps commonly used by travelers for this specific destination country/region.
- For Russia: Use Yandex Travel (transit/hotels), Ostrovok (hotels), or Aviasales (flights). Do not use Booking.com or Skyscanner for Russia.
- For Sri Lanka: Use Booking.com (hotels), PickMe (transit/cabs), Klook (tours), or similar.
- For general South-East Asia: Use Agoda (hotels), Grab (transit), or Klook (tours).
- For Western Europe / Americas: Use Booking.com (hotels), Viator (tours), Skyscanner (flights/transit).
- The "url" field should be a real search landing page or homepage URL for that provider, prefilled/related to the destination if possible.
- The "type" field must be one of: "hotels", "tours", "transit".

Rules:
- Plan for {travelers} traveler(s): size accommodation, meals and tickets for the group, and make every activity "cost" the TOTAL for all {travelers}.
- Produce exactly {days} entries in "day_plans", each with 3-5 activities.
- Keep the SUM of all activity costs within the {int(budget)} {currency} budget (this covers all {travelers} travelers).
- Use real, recognisable places near "{destination}".
- Be concise; tips under ~12 words.
"""


async def _call_gemini(prompt: str, api_key: str, max_tokens: int = 4096, thinking_budget=None) -> str:
    api_key = (api_key or "").strip().strip('"').strip("'")
    base_generation_config = {
        "temperature": 0.8,
        "maxOutputTokens": max_tokens,
        "responseMimeType": "application/json",
    }
    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
    # Odyssey is a one-shot background job, so a single 503 would permanently
    # fail it. Rotate through the model chain twice (with a short backoff
    # between passes) so a model that's overloaded right now is bypassed for
    # one that's currently healthy.
    data = None
    attempts = _MODELS * 2
    async with httpx.AsyncClient(timeout=90.0) as client:
        for i, model in enumerate(attempts):
            generation_config = dict(base_generation_config)
            # Only gemini-2.5+ models support thinkingConfig; 1.5/2.0 reject it
            if thinking_budget is not None and ("2.5" in model or "thinking" in model):
                generation_config["thinkingConfig"] = {"thinkingBudget": thinking_budget}

            body = {
                "contents": [{"parts": [{"text": prompt}]}],
                "system_instruction": {"parts": [{"text": _SYSTEM}]},
                "generationConfig": generation_config,
            }
            resp = await client.post(_model_url(model), json=body, headers=headers)
            if resp.status_code != 200 and i < len(attempts) - 1:
                logger.warning(
                    "Gemini status %s for %s — falling through to next model (details: %s)",
                    resp.status_code, model, resp.text[:200],
                )
                # Brief pause once we've cycled the whole chain once.
                if (i + 1) % len(_MODELS) == 0:
                    await asyncio.sleep(2)
                continue
            resp.raise_for_status()
            data = resp.json()
            break

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


async def generate_replacement_partner(
    *,
    destination: str,
    partner_name: str,
    partner_type: str,
    reason: str,
    avoid_names: list[str],
    api_key: str,
) -> dict:
    avoid = ", ".join(avoid_names) or "(none)"
    why = reason.strip() or "the traveler wants a different option"
    
    prompt = f"""A traveler is on a trip to "{destination}".
They want to replace the booking platform/app "{partner_name}" of type "{partner_type}" because: {why}.

These platforms/apps are already used or rejected for this trip - do NOT suggest any of them:
{avoid}

Suggest exactly ONE other real, popular travel website, booking platform, or local app commonly used for "{destination}" of type "{partner_type}" (hotels, tours, or transit) that is different from the avoided list.
- For Russia: Use Yandex Travel, Ostrovok, or Aviasales. Do not use Booking.com or Skyscanner for Russia.
- For Sri Lanka: Use Booking.com, PickMe, Klook, or similar.
- For general South-East Asia: Use Agoda, Grab, or Klook.
- For Western Europe / Americas: Use Booking.com, Viator, Skyscanner.

Return ONLY a JSON object with this exact shape:
{{ "name": "Platform Name", "type": "{partner_type}", "url": "Search or landing URL for this platform in {destination}" }}
"""
    text = await _call_gemini(prompt, api_key, max_tokens=1024, thinking_budget=0)
    data = _parse_json(text)
    return {
        "name": str(data.get("name") or "").strip(),
        "type": partner_type,
        "url": str(data.get("url") or "").strip(),
    }
