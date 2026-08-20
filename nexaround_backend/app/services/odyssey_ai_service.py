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
import re
import urllib.parse
import httpx
from app.services import telemetry
from app.services.serpapi_service import (
    SerpApiService,
    format_flight_results_for_gemini,
    format_hotel_results_for_gemini,
    extract_hotel_strategies_from_serpapi,
)

logger = logging.getLogger(__name__)


def _clean_destination(dest: str) -> str:
    """Deduplicate comma-separated destination tokens (e.g. 'Germany, Germany' -> 'Germany')."""
    if not dest:
        return ""
    parts = [p.strip() for p in dest.split(",") if p.strip()]
    unique_parts = []
    for p in parts:
        if not any(p.lower() == existing.lower() for existing in unique_parts):
            unique_parts.append(p)
    return ", ".join(unique_parts)


def _build_deep_booking_url(
    provider: str,
    item_name: str,
    destination: str,
    start_date: str,
    end_date: str,
    travelers: int = 1,
    is_flight: bool = False,
    origin_city: str = "",
    airlines: list[str] = None,
) -> str:
    prov_lower = (provider or "").lower()
    dest = _clean_destination(destination)
    name = (item_name or "").strip()

    # Avoid duplicating destination if item_name already contains destination
    if name and dest and dest.lower() in name.lower():
        query = name
    elif name and dest:
        query = f"{name}, {dest}"
    elif name:
        query = name
    else:
        query = f"hotels in {dest}" if dest else "hotels"

    encoded_query = urllib.parse.quote_plus(query)
    encoded_dest = urllib.parse.quote_plus(dest)

    if is_flight:
        origin = _clean_destination(origin_city)
        if origin.lower() in ["nearest airport", "nearest international airport", "origin", ""]:
            origin = ""

        # Build clean Google Flights query URL
        search_q = f"flights from {origin} to {dest}" if origin else f"flights to {dest}"
        if airlines and len(airlines) > 0:
            search_q += f" with {', '.join(airlines[:2])}"
        if start_date and end_date:
            search_q += f" on {start_date} through {end_date}"
        elif start_date:
            search_q += f" on {start_date}"
        return f"https://www.google.com/travel/flights?q={urllib.parse.quote_plus(search_q)}"
    else:  # Hotel
        # Google Hotels query: always destination-based so it never shows
        # "No results" for AI-generated hotel names that may not exist.
        google_hotel_q = f"hotels in {dest}" if dest else query
        if "booking" in prov_lower:
            url = f"https://www.booking.com/searchresults.html?ss={encoded_query}"
            if start_date:
                url += f"&checkin={start_date}"
            if end_date:
                url += f"&checkout={end_date}"
            url += f"&group_adults={max(travelers, 1)}"
            return url
        else:
            # Google Hotels as primary fallback
            google_url = f"https://www.google.com/travel/hotels?q={urllib.parse.quote_plus(google_hotel_q)}"
            if start_date and end_date:
                google_url += f"&dates={start_date},{end_date}"
            return google_url

# Gemini Flash models rotate through transient 503 "high demand" — WHICH model
# is overloaded changes minute to minute, so retrying one model isn't enough.
# Try a chain: a 503 on one model falls through to another that's healthy now.
_MODELS = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
]
_MODEL = _MODELS[0]  # kept for any external reference / logging



def _model_url(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

_SYSTEM = (
    "You are NexAround's expert local travel designer. "
    "You craft realistic, budget-aware, day-by-day trip blueprints. You always "
    "reply with a single JSON object that matches the requested schema exactly - "
    "no markdown, no commentary, no code fences. "
    "CRITICAL: If the user provides an unrealistically low or impossible budget (e.g. 1 USD, 10 USD, or very low funds), "
    "DO NOT FAIL OR REFUSE. Instead, generate an ultra-low budget / free exploration itinerary for the destination, "
    "and include a clear, helpful 'budget_advisory' disclaimer explaining the realistic costs required."
)


def _days_between(start: str, end: str) -> int:
    """Calculate the number of days between two YYYY-MM-DD date strings."""
    try:
        from datetime import datetime as dt
        s = dt.strptime(start, "%Y-%m-%d")
        e = dt.strptime(end, "%Y-%m-%d")
        return max((e - s).days, 1)
    except Exception:
        return 1


def _to_expedia_date(date_str: str) -> str:
    """Convert YYYY-MM-DD to MM/DD/YYYY for Expedia deep links."""
    try:
        parts = date_str.split("-")
        if len(parts) == 3:
            return f"{parts[1]}/{parts[2]}/{parts[0]}"
    except Exception:
        pass
    return date_str


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
    start_date: str = "",
    end_date: str = "",
    departure_city: str = "",
    budget_breakdown: dict = None,
    budget_advisory: str = "",
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
        "start_date": start_date,
        "end_date": end_date,
        "departure_city": departure_city,
        "budget_breakdown": budget_breakdown or {},
        "budget_advisory": budget_advisory,
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
            async with telemetry.track(
                "unsplash", "cover_photo_search",
                sku="unsplash_photo", cache_key=f"unsplash:{destination.strip().lower()}",
            ) as t:
                response = await client.get(url, params=params)
                t.upstream(response)
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
    serpapi_key: str = "",
) -> dict:
    """Generates flight routing strategies using live SerpApi Google Flights data + Gemini."""
    real_data_context = ""

    if serpapi_key:
        try:
            logger.info("Fetching live flight data via SerpApi (Google Flights)...")
            serp = SerpApiService(serpapi_key)
            serp_result = await serp.search_flights(
                departure_city=departure_city,
                destination=destination,
                outbound_date=flight_start_date,
                return_date=flight_end_date,
                adults=travelers,
                currency=currency,
            )
            real_data_context = format_flight_results_for_gemini(
                serp_result, departure_city, destination, currency
            )
        except Exception as e:
            logger.warning(f"SerpApi flight search failed, falling back to Gemini knowledge: {e}")

    date_str = ""
    if flight_start_date and flight_end_date:
        date_str = f"- Departure Date: {flight_start_date}\n- Return Date: {flight_end_date}"

    real_data_prompt_section = ""
    if real_data_context:
        real_data_prompt_section = f"""
LIVE GOOGLE FLIGHTS SEARCH RESULTS:
{real_data_context}

INSTRUCTION: Base your strategies on the real Google Flights data above. Extract the exact departure/arrival airport codes, actual airlines, actual durations, and real price ranges.
"""

    prompt = f"""Analyze flight options for a trip from "{departure_city}" ({departure_country}) to "{destination}".
The travelers want to find the cheapest flight options.

Trip Details:
- Departure: {departure_city}, {departure_country}
- Destination: {destination}
{date_str}
- Duration: {days} days
- Group Size: {travelers} traveler(s)
- Total Trip Budget: {int(budget)} {currency} (flights should fit or be optimized against this)
{real_data_prompt_section}
Your task is to act as an agentic flight finder. Propose 2-4 distinct, realistic flight strategies.
These can be:
- "direct": Direct flight option (if available) or standard single-carrier route.
- "budget_carrier": Utilizing low-cost carriers (e.g. AirAsia, Scoot, Ryanair, IndiGo, FitsAir, Southwest, etc. depending on region).
- "split_ticket": Booking separate tickets to save money.
- "nearby_airport": Flying into or out of a nearby airport.

IMPORTANT RULES:
- In the "route" field, always use real IATA airport codes (e.g., CMB, BKK, KUL, NRT, LHR). If the departure city (e.g., Kinniya) does not have an airport, use the nearest major airport (e.g., CMB for Colombo).
- provider_name MUST be "Google Flights" for all strategies.
- Estimate realistic price ranges in {currency}.

Field Rules:
- "title": Concise 3-6 word strategy name.
- "provider_name": MUST be "Google Flights".
- "estimated_savings": Very short tag under 4 words (e.g., "Save ~20%").
- "estimated_price_range": Short price string only (e.g., "USD 180 - 300").
- "route": Short IATA airport code route (e.g., "CMB → KUL").
- "convenience": Star rating string ONLY (e.g., "★★★☆☆").
- "tip": Short booking tip.
- "booking_url": Leave empty, will be generated server-side.

Return ONLY a JSON object with this exact shape:
{{
  "departure_city": "{departure_city}",
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "strategy": "direct",
      "title": "Direct Flight via Google Flights",
      "provider_name": "Google Flights",
      "description": "Description of route and strategy.",
      "estimated_savings": "Save ~15%",
      "estimated_price_range": "{currency} 200 - 400",
      "airlines": ["Airline A", "Airline B"],
      "route": "CMB → KUL",
      "stops": 0,
      "total_duration": "4h 30m",
      "convenience": "★★★★★",
      "tip": "Short booking tip.",
      "booking_url": ""
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
                    # Extract origin & destination airport/city from route (e.g. "CMB → LHR")
                    route_str = str(strat.get("route") or "")
                    route_origin = departure_city
                    route_dest = destination
                    if route_str:
                        r_parts = [p.strip() for p in route_str.replace("->", "→").split("→") if p.strip()]
                        if r_parts:
                            route_origin = r_parts[0]
                        if len(r_parts) > 1:
                            route_dest = r_parts[-1]

                    # Force Google Flights as provider and build deep search URL
                    strat["provider_name"] = "Google Flights"
                    strat["booking_url"] = _build_deep_booking_url(
                        provider="Google Flights",
                        item_name=strat.get("title") or destination,
                        destination=route_dest,
                        start_date=flight_start_date,
                        end_date=flight_end_date,
                        travelers=travelers,
                        is_flight=True,
                        origin_city=route_origin,
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
    serpapi_key: str = "",
) -> dict:
    """Generates hotel/accommodation strategies using SerpApi Google Hotels directly.
    
    Option A: Uses SerpAPI results directly with 4.0★ minimum rating filter.
    Gemini is NOT used for hotel selection — prices, ratings, and hotel names
    come straight from Google Hotels via SerpAPI for 100% accuracy.
    
    Falls back to Gemini-based generation only if SerpAPI returns no results.
    """

    # ── Primary path: SerpAPI direct extraction ──────────────────────────────
    if serpapi_key:
        try:
            logger.info("Fetching live hotel data via SerpApi (Google Hotels) with 4.0★ min rating...")
            serp = SerpApiService(serpapi_key)
            serp_result = await serp.search_hotels(
                destination=destination,
                check_in_date=hotel_check_in_date,
                check_out_date=hotel_check_out_date,
                adults=travelers,
                currency=currency,
                min_rating=4.0,  # Only 4★+ hotels
            )

            properties = serp_result.get("properties") or []
            if properties:
                logger.info(f"SerpAPI returned {len(properties)} hotels rated 4.0★+ for {destination}")
                result = extract_hotel_strategies_from_serpapi(
                    serp_result,
                    destination=destination,
                    currency=currency,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    travelers=travelers,
                    max_hotels=4,
                )
                return result
            else:
                logger.warning(f"SerpAPI returned 0 hotels after 4.0★ filter for {destination}. "
                              "Trying with 3.5★ minimum...")
                # Retry with slightly lower threshold
                serp_result = await serp.search_hotels(
                    destination=destination,
                    check_in_date=hotel_check_in_date,
                    check_out_date=hotel_check_out_date,
                    adults=travelers,
                    currency=currency,
                    min_rating=3.5,
                )
                properties = serp_result.get("properties") or []
                if properties:
                    logger.info(f"SerpAPI returned {len(properties)} hotels rated 3.5★+ for {destination}")
                    result = extract_hotel_strategies_from_serpapi(
                        serp_result,
                        destination=destination,
                        currency=currency,
                        check_in_date=hotel_check_in_date,
                        check_out_date=hotel_check_out_date,
                        travelers=travelers,
                        max_hotels=4,
                    )
                    return result

        except Exception as e:
            logger.warning(f"SerpApi hotel search failed, falling back to Gemini: {e}")

    # ── Fallback: Gemini-based generation (only when SerpAPI unavailable) ────
    logger.info("Using Gemini fallback for hotel strategies (no SerpAPI results)")
    
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

Your task is to act as an agentic hotel finder. Propose 2-4 distinct, realistic hotel/stay options.
For each option, include a REAL, well-known hotel name that actually exists in {destination}.
Categories: Luxury, Boutique, Budget, Resort, or Apartment.

IMPORTANT RULES:
- provider_name MUST be either "Google Travel" or "Booking.com".
- Use REAL hotel names that exist in {destination}.
- Estimate REALISTIC per-night rates in {currency}.
- booking_url: Leave empty, will be generated server-side.

Return ONLY a JSON object with this exact shape:
{{
  "destination_city": "{destination}",
  "strategies": [
    {{
      "rank": 1,
      "name": "Real Hotel Name",
      "provider_name": "Booking.com",
      "category": "Boutique / Luxury / Budget",
      "rating": "4.7 ★",
      "price_per_night": "{currency} 120",
      "total_estimated_cost": "{currency} 600",
      "location": "City Center",
      "amenities": ["Free WiFi", "Breakfast Included", "Pool"],
      "description": "Short explanation of why this stay fits the trip.",
      "booking_url": ""
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
    serpapi_key: str = "",
    include_flights: bool = False,
    departure_city: str = "",
    departure_country: str = "",
    flight_start_date: str = "",
    flight_end_date: str = "",
    include_hotels: bool = False,
    hotel_check_in_date: str = "",
    hotel_check_out_date: str = "",
    start_date: str = "",
    end_date: str = "",
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
                    serpapi_key=serpapi_key,
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
                    serpapi_key=serpapi_key,
                )
            except Exception as e:
                logger.error(f"Hotel strategy sub-job failed: {e}")
                return {}
        return {}

    cover_url, flight_strategies, hotel_strategies = await asyncio.gather(
        _get_cover(), _get_flights(), _get_hotels()
    )

    final_start_date = start_date or flight_start_date or hotel_check_in_date or ""
    final_end_date = end_date or flight_end_date or hotel_check_out_date or ""

    # Extract cheapest flight & stay costs if available to synchronize budget breakdown
    cheapest_flight_cost = 0.0
    if flight_strategies and isinstance(flight_strategies.get("strategies"), list):
        f_costs = [
            _extract_lowest_price(s.get("estimated_price_range"))
            for s in flight_strategies["strategies"]
            if isinstance(s, dict) and _extract_lowest_price(s.get("estimated_price_range")) > 0
        ]
        if f_costs:
            # Flight strategies express per-person rate; multiply by travelers for group total
            cheapest_flight_cost = min(f_costs) * max(travelers, 1)

    cheapest_hotel_cost = 0.0
    if hotel_strategies and isinstance(hotel_strategies.get("strategies"), list):
        h_costs = [
            _extract_lowest_price(s.get("total_estimated_cost") or s.get("price_per_night"))
            for s in hotel_strategies["strategies"]
            if isinstance(s, dict) and _extract_lowest_price(s.get("total_estimated_cost") or s.get("price_per_night")) > 0
        ]
        if h_costs:
            cheapest_hotel_cost = min(h_costs)

    # Base budget allocation
    tot = float(budget) if budget > 0 else 1.0
    
    if cheapest_flight_cost > 0:
        # Cap transit to max 85% of total budget if flight cost is extremely high
        transit_amt = min(cheapest_flight_cost, round(tot * 0.85, 2))
    else:
        transit_amt = round(tot * 0.30, 2)

    rem_after_transit = max(tot - transit_amt, round(tot * 0.15, 2))

    if cheapest_hotel_cost > 0:
        stay_amt = min(cheapest_hotel_cost, round(rem_after_transit * 0.60, 2))
    else:
        stay_amt = round(rem_after_transit * 0.45, 2)

    rem_for_food_act = max(tot - (transit_amt + stay_amt), round(tot * 0.05, 2))
    food_amt = round(rem_for_food_act * 0.60, 2)
    activities_amt = round(tot - (stay_amt + transit_amt + food_amt), 2)

    budget_breakdown = {
        "stay": stay_amt,
        "transit": transit_amt,
        "food": food_amt,
        "activities": activities_amt,
        "total": tot,
    }

    # Dynamically generate budget_split text string to guarantee 100% agreement with breakdown
    stay_pct = round((stay_amt / tot) * 100)
    transit_pct = round((transit_amt / tot) * 100)
    food_pct = round((food_amt / tot) * 100)
    activities_pct = max(100 - (stay_pct + transit_pct + food_pct), 0)
    harmonized_budget_split = f"{stay_pct}% Stay - {transit_pct}% Transit - {food_pct}% Food - {activities_pct}% Activities"

    # Advisory calculation: ensure ultra-low budgets always carry a clear disclaimer
    gemini_advisory = str(plan.get("budget_advisory") or "").strip()
    estimated_min_daily = 35.0 * max(travelers, 1) * g_days
    if not gemini_advisory:
        if budget <= 10 or budget < estimated_min_daily or (cheapest_flight_cost + cheapest_hotel_cost > budget and budget > 0):
            gemini_advisory = (
                f"Your budget of {int(budget)} {currency} is below the typical minimum required for a {g_days}-day trip to {final_destination}. "
                f"We've tailored an ultra-saver plan featuring free attractions and budget-friendly exploration, but additional funds will be required for actual flights, accommodation, and daily meals."
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
        budget_split=harmonized_budget_split,
        visa=str(plan.get("visa") or plan.get("visa_status") or ""),
        logistics=_logistics_text(plan.get("logistics")),
        booking_partners=plan.get("booking_partners") or [],
        cover_url=cover_url,
        flight_strategies=flight_strategies,
        hotel_strategies=hotel_strategies,
        start_date=final_start_date,
        end_date=final_end_date,
        departure_city=departure_city or "",
        budget_breakdown=budget_breakdown,
        budget_advisory=gemini_advisory,
    )

    day_items: list[dict] = []
    for d in (plan.get("day_plans") or plan.get("plan") or []):
        if not isinstance(d, dict):
            continue
        activities = []
        for a in (d.get("activities") or []):
            if not isinstance(a, dict):
                continue
            act_type = str(a.get("type") or "").strip().lower()
            restaurants = []
            if isinstance(a.get("restaurants"), list):
                for r in a.get("restaurants"):
                    if isinstance(r, dict):
                        restaurants.append({
                            "name": str(r.get("name") or ""),
                            "cuisine": str(r.get("cuisine") or ""),
                            "price_range": str(r.get("price_range") or ""),
                            "rating": str(r.get("rating") or ""),
                            "tip": str(r.get("tip") or ""),
                        })
            act_dict = {
                "time": str(a.get("time") or ""),
                "name": str(a.get("name") or a.get("attraction_name") or ""),
                "tip": str(a.get("tip") or a.get("note") or ""),
                "cost": str(a.get("cost") or ""),
            }
            if act_type:
                act_dict["type"] = act_type
            if restaurants:
                act_dict["restaurants"] = restaurants
            activities.append(act_dict)
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
    """Generate ONE replacement activity with restaurants."""
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

    act_type = str(data.get("type") or "").strip().lower()
    restaurants = []
    if isinstance(data.get("restaurants"), list):
        for r in data.get("restaurants"):
            if isinstance(r, dict):
                restaurants.append({
                    "name": str(r.get("name") or ""),
                    "cuisine": str(r.get("cuisine") or ""),
                    "price_range": str(r.get("price_range") or ""),
                    "rating": str(r.get("rating") or ""),
                    "tip": str(r.get("tip") or ""),
                })

    res = {
        "time": time_slot or str(data.get("time") or ""),
        "name": name,
        "tip": str(data.get("tip") or data.get("note") or ""),
        "cost": str(data.get("cost") or ""),
    }
    if act_type:
        res["type"] = act_type
    if restaurants:
        res["restaurants"] = restaurants
    return res


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
{{ "time": "{slot}", "name": "Place or activity name", "tip": "Short practical tip under ~12 words", "cost": "{currency} amount or 'Free'", "type": "transport|attraction|dining|exploration|accommodation|other", "restaurants": [] }}
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

CRITICAL LOW / IMPOSSIBLE BUDGET HANDLING:
1. If the total budget of {int(budget)} {currency} is NOT realistic or too low to cover standard travel/hotel/flights for {travelers} traveler(s) in {destination} for {days} days (e.g. 1 USD, very low amount):
   - NEVER fail, refuse, or return an empty error plan.
   - Design an ultra-saver / backpacker / free-exploration itinerary: prioritize free iconic sights, self-guided walking tours, scenic parks, public viewpoints, free museums/galleries, and affordable street food/market stalls.
   - Populate "budget_advisory" with a clear, polite disclaimer explaining: "A total budget of {int(budget)} {currency} is insufficient for a standard {days}-day trip to {destination} (realistic budget typically starts from ~{currency} X). This itinerary is optimized as an ultra-saver plan with free sights and low-cost exploration, but additional funds will be needed for realistic lodging, transit, and meals."
2. If the budget is sufficient and realistic, set "budget_advisory": "".

CRITICAL BUDGET PRIORITY RULES:
1. Flights & Transit (Priority 1) and Stay & Accommodation (Priority 2) MUST BE ALLOCATED FIRST!
2. Allocate realistic funds for Flights (~40-50%) and Stay (~30-35%).
3. Stay (Accommodation) budget MUST NEVER be near zero or under 25% of total budget unless flights alone exceed 70% or total budget is an ultra-saver amount.
4. Food & Dining (~10-15%) and Activities (~5-10%) share the remaining budget.

Return ONLY a JSON object with EXACTLY this shape:
{{
  "title": "Evocative 2-4 word trip name",
  "destination": "{destination}",
  "days": {days},
  "nights": {nights},
  "currency": "{currency}",
  "summary": "1-2 sentence overview matching the '{mood}' style.",
  "budget_split": "Short split, e.g. '35% Stay - 45% Transit - 12% Food - 8% Activities'",
  "budget_advisory": "Notice if budget cap is insufficient for realistic flight/hotel rates, otherwise empty string.",
  "budget_breakdown": {{
    "stay": {int(budget * 0.35)},
    "transit": {int(budget * 0.45)},
    "food": {int(budget * 0.12)},
    "activities": {int(budget * 0.08)},
    "total": {int(budget)}
  }},
  "visa": "One line on visa/entry needs for this destination (or 'No visa info' if domestic).",
  "logistics": ["3-5 short practical tips: transport, money, SIM, entry fees, timing"],
  "booking_partners": [
    {{ "name": "Booking.com", "type": "hotels", "url": "https://www.booking.com" }},
    {{ "name": "Viator", "type": "tours", "url": "https://www.viator.com" }},
    {{ "name": "Skyscanner", "type": "transit", "url": "https://www.skyscanner.com" }}
  ],
  "day_plans": [
    {{
      "day": 1,
      "theme": "Short day theme",
      "activities": [
        {{ "time": "09:00", "name": "Place or activity name", "tip": "Short practical tip", "cost": "{currency} amount or 'Free'", "price_source": "Official Ticket / Metered Taxi / Menu Avg / Public Access", "price_basis": "1-sentence note on rate baseline or conditions", "type": "transport|attraction|dining|exploration|accommodation|other", "restaurants": [] }}
      ]
    }}
  ]
}}

Rules for "type" field in each activity:
- "transport": Travel/transit between locations (e.g. "Travel to X", "Taxi to Y", "Ferry to Z"). Cost = estimated ride/fare.
- "attraction": Ticketed landmarks, museums, temples, cathedrals, galleries, parks with entry fees. Cost = ticket price.
- "dining": Meals — lunch, dinner, breakfast, brunch, street food, food tours. Cost = cheapest restaurant option available. Include "restaurants" array with 3-5 nearby restaurant suggestions.
- "exploration": Free self-guided walking, wandering, exploring streets/markets. Cost = "Free".
- "accommodation": Hotel check-in/check-out. Cost = "Free" (hotel cost is in budget_breakdown).
- "other": Any activity that doesn't fit above categories.

Rules for "restaurants" in dining activities:
- Only include "restaurants" array for activities with type "dining".
- Each restaurant: {{ "name": "Restaurant Name", "cuisine": "Italian / Local / etc", "price_range": "{currency} X - Y per person", "rating": "4.5", "tip": "Known for X" }}
- List 3-5 real, popular restaurants near the dining location.
- The activity "cost" should match the cheapest restaurant's lower price range.

Rules for "booking_partners":
- List ONLY 2-4 real, popular travel websites, ride-hailing apps, booking platforms, or local apps that directly match the transit/hotel/tour recommendations in this plan.
- If ride-hailing or transit is recommended, include the exact app used in that region (e.g. Uber for US/Europe/India, PickMe for Sri Lanka, Grab for SE Asia, Yandex for Russia).
- For stays & hotels: Include the recommended hotel booking site (e.g. Booking.com, Agoda, Ostrovok).
- For tours & tickets: Include the recommended activity platform (e.g. Headout, GetYourGuide, Klook, Viator).
- The "url" field MUST be the official search URL of that exact provider (e.g. https://www.uber.com, https://www.viator.com, https://www.booking.com).
- The "type" field must be one of: "hotels", "tours", "transit".

Rules:
- Plan for {travelers} traveler(s): size accommodation, meals and tickets for the group, and make every activity "cost" the TOTAL for all {travelers}.
- In "budget_breakdown", strictly divide the total budget of {int(budget)} {currency} across the 4 core categories: "stay" (accommodation), "transit" (flights/intercity transport), "food" (all meals & dining), and "activities" (tours/tickets). Ensure stay + transit + food + activities == {int(budget)}.
- Produce exactly {days} entries in "day_plans", each with 3-5 activities.
- Keep the SUM of all activity costs within the "activities" and "food" budget portion of {int(budget)} {currency}.
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
    async with httpx.AsyncClient(timeout=45.0) as client:
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
            try:
                async with telemetry.track(
                    "gemini", f"odyssey_generate:{model}",
                    sku="gemini_flash_generate",
                ) as t:
                    resp = await client.post(_model_url(model), json=body, headers=headers)
                    t.upstream(resp)
                if resp.status_code != 200 and i < len(attempts) - 1:
                    logger.warning(
                        "Gemini status %s for %s — falling through to next model (details: %s)",
                        resp.status_code, model, resp.text[:200],
                    )
                    # Brief pause once we've cycled the whole chain once (skip pause if 404)
                    if (i + 1) % len(_MODELS) == 0 and resp.status_code != 404:
                        await asyncio.sleep(1)
                    continue
                resp.raise_for_status()
                data = resp.json()
                break
            except Exception as e:
                if i < len(attempts) - 1:
                    logger.warning("Gemini exception for %s — falling through: %s", model, e)
                    continue
                raise e

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


def _extract_lowest_price(price_str: str) -> float:
    """Extracts the lowest numeric value from a price range or price string."""
    if not price_str:
        return 0.0
    cleaned = re.sub(r"[^\d.\-\s]", "", str(price_str))
    numbers = re.findall(r"\d+(?:\.\d+)?", cleaned)
    if numbers:
        try:
            return float(numbers[0])
        except ValueError:
            pass
    return 0.0


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
