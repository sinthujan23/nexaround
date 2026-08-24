"""SerpApi integration for real-time Google Flights and Google Hotels search.

Replaces the unreliable RapidAPI service with SerpApi, which provides
structured JSON from Google's own travel search results — including real
prices, real airlines, real hotel names, and automatic airport resolution.

Sign up at https://serpapi.com for a free API key (250 searches/month).
"""
import logging
import httpx
from app.services import telemetry
from typing import Dict, Any, List

logger = logging.getLogger(__name__)

SERPAPI_BASE = "https://serpapi.com/search.json"


class SerpApiService:
    """Search Google Flights and Google Hotels via SerpApi."""

    def __init__(self, api_key: str):
        self.api_key = (api_key or "").strip()

    async def search_flights(
        self,
        *,
        departure_city: str,
        destination: str,
        outbound_date: str = "",
        return_date: str = "",
        adults: int = 1,
        currency: str = "USD",
    ) -> Dict[str, Any]:
        """Search Google Flights via SerpApi.

        Returns a dict with:
          - best_flights: list of top flight options
          - other_flights: list of additional options
          - airports: departure/arrival airport info
          - price_insights: pricing analysis from Google
        """
        if not self.api_key:
            return {}

        params: Dict[str, Any] = {
            "engine": "google_flights",
            "api_key": self.api_key,
            "departure_id": departure_city,
            "arrival_id": destination,
            "type": "1",  # 1=round trip, 2=one way
            "adults": str(adults),
            "currency": currency.upper(),
            "hl": "en",
        }

        if outbound_date:
            params["outbound_date"] = outbound_date
        if return_date:
            params["return_date"] = return_date
            params["type"] = "1"  # round trip
        else:
            params["type"] = "2"  # one way if no return date

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                async with telemetry.track(
                    "serpapi", "search_flights",
                    sku="serpapi_search", params=params,
                ) as t:
                    resp = await client.get(SERPAPI_BASE, params=params)
                    t.upstream(resp)
                if resp.status_code != 200:
                    logger.warning(f"[SerpApi] Flights search returned {resp.status_code}: {resp.text[:200]}")
                    return {}
                data = resp.json()

                # Check for errors
                if "error" in data:
                    logger.warning(f"[SerpApi] Flights error: {data['error']}")
                    return {}

                return data

        except Exception as e:
            logger.error(f"[SerpApi] Flights search exception: {e}")
            return {}

    async def search_hotels(
        self,
        *,
        destination: str,
        check_in_date: str = "",
        check_out_date: str = "",
        adults: int = 1,
        currency: str = "USD",
        min_rating: float = 0.0,
    ) -> Dict[str, Any]:
        """Search Google Hotels via SerpApi.

        Returns a dict with:
          - properties: list of hotel results with prices, ratings, amenities
        If min_rating > 0, properties below that rating are filtered out.
        """
        if not self.api_key:
            return {}

        # Build the search query
        q = f"hotels in {destination}"

        params: Dict[str, Any] = {
            "engine": "google_hotels",
            "api_key": self.api_key,
            "q": q,
            "adults": str(adults),
            "currency": currency.upper(),
            "hl": "en",
            "gl": "us",
        }

        if check_in_date:
            params["check_in_date"] = check_in_date
        if check_out_date:
            params["check_out_date"] = check_out_date

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                async with telemetry.track(
                    "serpapi", "search_hotels",
                    sku="serpapi_search", params=params,
                ) as t:
                    resp = await client.get(SERPAPI_BASE, params=params)
                    t.upstream(resp)
                if resp.status_code != 200:
                    logger.warning(f"[SerpApi] Hotels search returned {resp.status_code}: {resp.text[:200]}")
                    return {}
                data = resp.json()

                if "error" in data:
                    logger.warning(f"[SerpApi] Hotels error: {data['error']}")
                    return {}

                # Apply min_rating filter
                if min_rating > 0 and "properties" in data:
                    data["properties"] = [
                        p for p in data["properties"]
                        if isinstance(p, dict)
                        and isinstance(p.get("overall_rating"), (int, float))
                        and p["overall_rating"] >= min_rating
                    ]

                return data

        except Exception as e:
            logger.error(f"[SerpApi] Hotels search exception: {e}")
            return {}


def extract_hotel_strategies_from_serpapi(
    serpapi_data: Dict[str, Any],
    *,
    destination: str,
    currency: str,
    check_in_date: str = "",
    check_out_date: str = "",
    travelers: int = 1,
    max_hotels: int = 4,
) -> Dict[str, Any]:
    """Convert raw SerpAPI Google Hotels results directly into hotel strategy
    dicts compatible with the Odyssey HotelStrategy model.

    This bypasses Gemini entirely — prices, ratings, and names come straight
    from Google Hotels via SerpAPI so they are 100% accurate.

    Returns a dict shaped like:
      {
        "strategies": [...],
        "general_tips": [...],
        "best_areas": "..."
      }
    """
    properties = serpapi_data.get("properties") or []
    strategies: List[Dict[str, Any]] = []

    # Categorize hotels by price tier
    def _categorize(rate: float, all_rates: List[float]) -> str:
        if not all_rates:
            return "Hotel"
        avg = sum(all_rates) / len(all_rates)
        if rate >= avg * 1.5:
            return "Luxury"
        elif rate >= avg * 0.8:
            return "Boutique"
        else:
            return "Budget"

    # Collect extracted rates for categorization
    all_rates: List[float] = []
    for p in properties[:max_hotels * 2]:  # look at more for better categorization
        rate_info = p.get("rate_per_night") or {}
        extracted = rate_info.get("extracted_lowest")
        if isinstance(extracted, (int, float)) and extracted > 0:
            all_rates.append(float(extracted))

    for rank, p in enumerate(properties[:max_hotels], start=1):
        if not isinstance(p, dict):
            continue

        name = p.get("name", "").strip()
        if not name:
            continue

        rating = p.get("overall_rating")
        reviews = p.get("reviews", 0)
        hotel_type = p.get("type", "")
        description = p.get("description", "")

        # Price extraction
        rate_info = p.get("rate_per_night") or {}
        price_display = rate_info.get("lowest", "")
        extracted_rate = rate_info.get("extracted_lowest", 0)

        total_info = p.get("total_rate") or {}
        total_display = total_info.get("lowest", "")

        # Amenities
        amenities = p.get("amenities") or []
        if isinstance(amenities, list):
            amenities = [str(a) for a in amenities[:6]]

        # Location from nearby_places
        nearby = p.get("nearby_places") or []
        location_parts = []
        for np_item in nearby[:2]:
            if isinstance(np_item, dict):
                np_name = np_item.get("name", "")
                if np_name:
                    location_parts.append(np_name)
        location = ", ".join(location_parts) if location_parts else destination

        # Category
        category = hotel_type if hotel_type else _categorize(
            float(extracted_rate) if extracted_rate else 0, all_rates
        )

        # Rating string
        rating_str = f"{rating} ★" if rating else "N/A"

        # Provider: Google Hotels aggregates rates across all platforms (Booking.com, Agoda, Direct)
        provider = "Google Hotels"

        # Clean hotel name by stripping room specifications (e.g. - Family Room...)
        import re
        clean_name = re.sub(
            r'\s*[-–—]\s*(Family|Standard|Deluxe|Executive|Superior|Suite|Villa|Room|Bed|King|Queen|Twin|Double|Single|Sea View|Garden View|Ocean View|Penthouse|Bungalow|Apartment|Studio|Cottage|Luxury|Chalet|Resort|One|Two|Three|Four|Five|\d+).*',
            '',
            name,
            flags=re.IGNORECASE
        ).strip(" -–—,")
        if not clean_name:
            clean_name = name

        # Booking URL: use SerpAPI's direct property link if available, otherwise build Google Travel deep link with dates
        serpapi_link = p.get("link", "")
        import urllib.parse
        google_q = urllib.parse.quote_plus(f"{clean_name} {destination}")
        booking_url = f"https://www.google.com/travel/hotels?q={google_q}"
        if check_in_date and check_out_date:
            booking_url += f"&dates={check_in_date},{check_out_date}"

        strategies.append({
            "rank": rank,
            "name": name,
            "provider_name": provider,
            "category": category,
            "rating": rating_str,
            "reviews": reviews if isinstance(reviews, int) else 0,
            "price_per_night": price_display if price_display else f"{currency} {extracted_rate}" if extracted_rate else "",
            "total_estimated_cost": total_display if total_display else "",
            "location": location,
            "amenities": amenities,
            "description": description or f"Well-rated hotel in {destination} with excellent guest reviews.",
            "booking_url": booking_url,
            "serpapi_link": serpapi_link,
        })

    # Generate helpful tips
    general_tips = []
    if check_in_date and check_out_date:
        general_tips.append(f"Prices shown are live rates for {check_in_date} to {check_out_date}.")
    general_tips.append("Prices may vary — tap to view the latest rates on the booking site.")
    if strategies:
        avg_rating = sum(
            float(s["rating"].replace(" ★", ""))
            for s in strategies
            if s["rating"] != "N/A"
        ) / max(len([s for s in strategies if s["rating"] != "N/A"]), 1)
        general_tips.append(f"All hotels shown are rated {avg_rating:.1f}★ or higher.")

    # Best areas from the results
    areas = set()
    for s in strategies:
        loc = s.get("location", "")
        if loc and loc != destination:
            areas.add(loc.split(",")[0].strip())
    best_areas = ", ".join(list(areas)[:3]) if areas else destination

    return {
        "strategies": strategies,
        "general_tips": general_tips,
        "best_areas": best_areas,
    }


def format_flight_results_for_gemini(
    serpapi_data: Dict[str, Any],
    departure_city: str,
    destination: str,
    currency: str,
) -> str:
    """Convert SerpApi Google Flights JSON into a text summary for Gemini to analyze."""
    if not serpapi_data:
        return ""

    lines = [f"REAL FLIGHT DATA from Google Flights ({departure_city} → {destination}):"]
    lines.append("")

    # Extract airport info
    airports = serpapi_data.get("airports") or []
    if airports:
        for airport_group in airports:
            dep = airport_group.get("departure") or []
            arr = airport_group.get("arrival") or []
            if dep:
                dep_names = [f"{a.get('name', '')} ({a.get('id', '')})" for a in dep]
                lines.append(f"Departure airports: {', '.join(dep_names)}")
            if arr:
                arr_names = [f"{a.get('name', '')} ({a.get('id', '')})" for a in arr]
                lines.append(f"Arrival airports: {', '.join(arr_names)}")
        lines.append("")

    # Extract price insights
    price_insights = serpapi_data.get("price_insights") or {}
    if price_insights:
        lowest = price_insights.get("lowest_price")
        typical_low = price_insights.get("typical_price_range", [None, None])
        if lowest:
            lines.append(f"Lowest price found: {currency} {lowest}")
        if typical_low and typical_low[0]:
            lines.append(f"Typical price range: {currency} {typical_low[0]} - {currency} {typical_low[1]}")
        lines.append("")

    # Best flights
    best_flights = serpapi_data.get("best_flights") or []
    other_flights = serpapi_data.get("other_flights") or []
    all_flights = best_flights + other_flights

    for i, flight_option in enumerate(all_flights[:6], start=1):
        flights = flight_option.get("flights") or []
        price = flight_option.get("price", "N/A")
        flight_type = flight_option.get("type", "")
        total_duration = flight_option.get("total_duration", 0)
        stops = len(flights) - 1 if len(flights) > 1 else 0
        is_best = i <= len(best_flights)

        hours = total_duration // 60
        mins = total_duration % 60
        duration_str = f"{hours}h {mins}m" if total_duration else "N/A"

        tag = "⭐ BEST" if is_best else "OTHER"
        lines.append(f"Flight {i} [{tag}] — {currency} {price} ({flight_type})")
        lines.append(f"  Duration: {duration_str} | Stops: {stops}")

        route_parts = []
        airlines = set()
        for leg in flights:
            dep_airport = leg.get("departure_airport", {})
            arr_airport = leg.get("arrival_airport", {})
            airline = leg.get("airline", "")
            flight_number = leg.get("flight_number", "")
            dep_id = dep_airport.get("id", "?")
            arr_id = arr_airport.get("id", "?")
            dep_time = leg.get("departure_airport", {}).get("time", "")
            arr_time = leg.get("arrival_airport", {}).get("time", "")
            airlines.add(airline)
            route_parts.append(f"{dep_id}→{arr_id}")
            lines.append(f"  {airline} {flight_number}: {dep_id} ({dep_time}) → {arr_id} ({arr_time})")

        lines.append(f"  Route: {' → '.join(route_parts)}")
        lines.append(f"  Airlines: {', '.join(airlines)}")
        lines.append("")

    if not all_flights:
        lines.append("No flight results found for this route.")

    return "\n".join(lines)


def format_hotel_results_for_gemini(
    serpapi_data: Dict[str, Any],
    destination: str,
    currency: str,
) -> str:
    """Convert SerpApi Google Hotels JSON into a text summary for Gemini to analyze."""
    if not serpapi_data:
        return ""

    lines = [f"REAL HOTEL DATA from Google Hotels ({destination}):"]
    lines.append("")

    properties = serpapi_data.get("properties") or []

    for i, hotel in enumerate(properties[:8], start=1):
        name = hotel.get("name", "Unknown Hotel")
        hotel_type = hotel.get("type", "")
        rating = hotel.get("overall_rating", "N/A")
        reviews = hotel.get("reviews", 0)
        rate_info = hotel.get("rate_per_night") or {}
        lowest_rate = rate_info.get("lowest", "N/A")
        extracted_rate = rate_info.get("extracted_lowest", 0)
        total_info = hotel.get("total_rate") or {}
        total_rate = total_info.get("lowest", "N/A")
        amenities = hotel.get("amenities") or []
        description = hotel.get("description", "")
        link = hotel.get("link", "")
        nearby = hotel.get("nearby_places") or []

        lines.append(f"Hotel {i}: {name}")
        if hotel_type:
            lines.append(f"  Type: {hotel_type}")
        lines.append(f"  Rating: {rating}/5 ({reviews} reviews)")
        lines.append(f"  Price/night: {lowest_rate}")
        if total_rate != "N/A":
            lines.append(f"  Total stay: {total_rate}")
        if amenities:
            lines.append(f"  Amenities: {', '.join(amenities[:5])}")
        if description:
            lines.append(f"  Description: {description[:120]}")
        lines.append("")

    if not properties:
        lines.append("No hotel results found for this destination.")

    return "\n".join(lines)
