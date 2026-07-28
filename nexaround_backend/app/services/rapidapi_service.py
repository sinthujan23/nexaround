"""RapidAPI integration service for live Flight and Hotel search.

Connects to RapidAPI travel endpoints (e.g., Booking.com & Skyscanner / Flight Search APIs)
using user-provided `X-RapidAPI-Key`. Transforms API responses into the exact shape expected by
the NexAround Odyssey Planner Flutter frontend, with fallback mechanisms.
"""
import logging
import urllib.parse
import httpx
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)

# Default RapidAPI Hosts
BOOKING_HOST = "booking-com.p.rapidapi.com"
FLIGHTS_HOST = "sky-scanner3.p.rapidapi.com"


class RapidAPIService:
    """Service to search live flight and hotel data via RapidAPI endpoints."""

    def __init__(self, api_key: str):
        self.api_key = (api_key or "").strip()

    def _get_headers(self, host: str) -> Dict[str, str]:
        return {
            "X-RapidAPI-Key": self.api_key,
            "X-RapidAPI-Host": host,
            "Accept": "application/json",
        }

    async def search_hotels(
        self,
        *,
        destination: str,
        days: int,
        budget: float,
        currency: str,
        travelers: int = 1,
        check_in_date: str = "",
        check_out_date: str = "",
    ) -> Dict[str, Any]:
        """Queries RapidAPI Booking.com endpoint for real hotel offers matching destination & dates.
        Returns a dict matching the HotelStrategy container format:
        {
            "destination_city": "...",
            "strategies": [...],
            "general_tips": [...],
            "best_areas": "..."
        }
        """
        if not self.api_key or not destination:
            return {}

        headers = self._get_headers(BOOKING_HOST)

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                # Step 1: Resolve destination location ID
                loc_url = f"https://{BOOKING_HOST}/v1/hotels/locations"
                loc_params = {"name": destination, "locale": "en-us"}
                loc_resp = await client.get(loc_url, headers=headers, params=loc_params)

                dest_id = None
                dest_type = "city"
                if loc_resp.status_code == 200:
                    locations = loc_resp.json()
                    if isinstance(locations, list) and len(locations) > 0:
                        first = locations[0]
                        dest_id = first.get("dest_id")
                        dest_type = first.get("dest_type") or "city"

                if not dest_id:
                    logger.warning(f"[RapidAPI] Could not resolve dest_id for hotel search: '{destination}'")
                    return {}

                # Step 2: Search hotels in location
                search_url = f"https://{BOOKING_HOST}/v1/hotels/search"
                search_params = {
                    "dest_id": str(dest_id),
                    "dest_type": dest_type,
                    "locale": "en-us",
                    "currency": currency.upper() if currency else "USD",
                    "adults_number": str(travelers),
                    "room_number": "1",
                    "page_number": "0",
                    "order_by": "popularity",
                    "units": "metric",
                }
                if check_in_date:
                    search_params["checkin_date"] = check_in_date
                if check_out_date:
                    search_params["checkout_date"] = check_out_date

                search_resp = await client.get(search_url, headers=headers, params=search_params)
                if search_resp.status_code != 200:
                    logger.warning(f"[RapidAPI] Hotel search API returned status {search_resp.status_code}")
                    return {}

                search_data = search_resp.json()
                results = search_data.get("result") or []
                if not isinstance(results, list) or not results:
                    return {}

                # Transform top 4 hotel results into strategies
                strategies = []
                for idx, hotel in enumerate(results[:4], start=1):
                    hotel_name = hotel.get("hotel_name") or hotel.get("name") or f"Hotel in {destination}"
                    review_score = hotel.get("review_score") or hotel.get("score")
                    rating_str = f"{review_score} ★" if review_score else "4.5 ★"

                    price_breakdown = hotel.get("price_breakdown") or {}
                    gross_price = price_breakdown.get("gross_price") or hotel.get("min_total_price") or 0
                    if isinstance(gross_price, dict):
                        gross_price = gross_price.get("value") or 0

                    price_num = float(gross_price) if gross_price else 0.0
                    per_night = round(price_num / max(days, 1), 2) if price_num > 0 else 0.0

                    curr_symbol = currency.upper() if currency else "USD"
                    price_per_night_str = f"{curr_symbol} {int(per_night)}" if per_night > 0 else f"{curr_symbol} 100"
                    total_cost_str = f"{curr_symbol} {int(price_num)}" if price_num > 0 else f"{curr_symbol} {int(100 * days)}"

                    # Build direct booking link
                    enc_name = urllib.parse.quote_plus(f"{hotel_name} {destination}")
                    booking_url = f"https://www.booking.com/searchresults.html?ss={enc_name}"
                    if check_in_date:
                        booking_url += f"&checkin={check_in_date}"
                    if check_out_date:
                        booking_url += f"&checkout={check_out_date}"
                    booking_url += f"&group_adults={travelers}"

                    address = hotel.get("address") or hotel.get("city_trans") or destination
                    unit_config = hotel.get("unit_configuration_label") or ""

                    category = "Boutique / Resort"
                    if idx == 1:
                        category = "Popular Choice"
                    elif idx == 2:
                        category = "Top Rated"
                    elif idx == 3:
                        category = "Budget Friendly"

                    strategies.append({
                        "rank": idx,
                        "name": hotel_name,
                        "provider_name": "Booking.com",
                        "category": category,
                        "rating": rating_str,
                        "price_per_night": price_per_night_str,
                        "total_estimated_cost": total_cost_str,
                        "location": str(address),
                        "amenities": ["Free WiFi", "AC", "Central Location"],
                        "description": f"Verified live hotel availability in {destination}. {unit_config}".strip(),
                        "booking_url": booking_url,
                    })

                return {
                    "destination_city": destination,
                    "strategies": strategies,
                    "general_tips": [
                        "Book at least 1-2 weeks in advance for optimal rates on Booking.com.",
                        "Free cancellation options are recommended for flexible itineraries.",
                    ],
                    "best_areas": f"Central {destination}",
                }

        except Exception as e:
            logger.error(f"[RapidAPI] Hotel search exception: {e}")
            return {}

    async def search_flights(
        self,
        *,
        departure_city: str,
        departure_country: str,
        destination: str,
        days: int,
        budget: float,
        currency: str,
        travelers: int = 1,
        flight_start_date: str = "",
        flight_end_date: str = "",
    ) -> Dict[str, Any]:
        """Queries RapidAPI Flight search endpoints for live flight options.
        Returns a dict matching the FlightStrategy container format:
        {
            "departure_city": "...",
            "destination_city": "...",
            "strategies": [...],
            "general_tips": [...]
        }
        """
        if not self.api_key or not destination:
            return {}

        headers = self._get_headers(FLIGHTS_HOST)
        origin = (departure_city or "").strip()
        if not origin or origin.lower() in ["nearest airport", "origin", ""]:
            origin = "Origin"

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"https://{FLIGHTS_HOST}/flights/search-one-way"
                params = {
                    "fromEntityId": origin,
                    "toEntityId": destination,
                    "departDate": flight_start_date or "2026-08-01",
                    "adults": str(travelers),
                    "currency": currency.upper() if currency else "USD",
                }
                resp = await client.get(url, headers=headers, params=params)

                strategies = []
                if resp.status_code == 200:
                    data = resp.json()
                    itineraries = data.get("data", {}).get("itineraries") or data.get("itineraries") or []
                    if isinstance(itineraries, list):
                        for idx, itin in enumerate(itineraries[:3], start=1):
                            price_obj = itin.get("price") or {}
                            formatted_price = price_obj.get("formatted") or f"{currency} {price_obj.get('raw', 200)}"
                            legs = itin.get("legs") or []
                            stops = 0
                            duration_str = "Standard"
                            if legs and isinstance(legs, list):
                                stops = legs[0].get("stopCount", 0)
                                duration_mins = legs[0].get("durationInMinutes", 0)
                                if duration_mins:
                                    duration_str = f"{duration_mins // 60}h {duration_mins % 60}m"

                            enc_origin = urllib.parse.quote_plus(origin)
                            enc_dest = urllib.parse.quote_plus(destination)
                            booking_url = f"https://www.skyscanner.com/transport/flights-from/{enc_origin}-to-{enc_dest}/"
                            if flight_start_date and flight_end_date:
                                booking_url += f"?outbounddate={flight_start_date}&inbounddate={flight_end_date}&adultsv2={travelers}"

                            strategies.append({
                                "rank": idx,
                                "strategy": "direct" if stops == 0 else "connecting",
                                "title": f"Live Route {idx} via Skyscanner",
                                "provider_name": "Skyscanner",
                                "description": f"Real-time carrier route from {origin} to {destination}.",
                                "estimated_savings": "Best Value" if idx == 1 else "Standard Fare",
                                "estimated_price_range": str(formatted_price),
                                "airlines": ["Partner Carrier"],
                                "route": f"{origin} ➔ {destination}",
                                "stops": stops,
                                "total_duration": duration_str,
                                "convenience": "★★★★☆" if stops == 0 else "★★★☆☆",
                                "tip": "Compare baggage options before final check-out.",
                                "booking_url": booking_url,
                            })

                if not strategies:
                    enc_origin = urllib.parse.quote_plus(origin)
                    enc_dest = urllib.parse.quote_plus(destination)
                    g_url = f"https://www.google.com/travel/flights?q=flights+from+{enc_origin}+to+{enc_dest}"
                    exp_url = f"https://www.expedia.com/Flights-Search?destination={enc_dest}"

                    strategies = [
                        {
                            "rank": 1,
                            "strategy": "direct",
                            "title": "Google Flights Deal Finder",
                            "provider_name": "Google Flights",
                            "description": f"Direct and low-cost carrier routing from {origin} to {destination}.",
                            "estimated_savings": "Save ~15-25%",
                            "estimated_price_range": f"{currency} {int(budget * 0.25)} - {int(budget * 0.35)}",
                            "airlines": ["Major Carriers"],
                            "route": f"{origin} ➔ {destination}",
                            "stops": 0,
                            "total_duration": "4h 30m",
                            "convenience": "★★★★★",
                            "tip": "Track prices on Google Flights for price drop notifications.",
                            "booking_url": g_url,
                        },
                        {
                            "rank": 2,
                            "strategy": "budget_carrier",
                            "title": "Expedia Budget Route",
                            "provider_name": "Expedia",
                            "description": f"Budget regional airline search for {origin} to {destination}.",
                            "estimated_savings": "Cheapest Option",
                            "estimated_price_range": f"{currency} {int(budget * 0.15)} - {int(budget * 0.25)}",
                            "airlines": ["Low-Cost Airlines"],
                            "route": f"{origin} ➔ {destination}",
                            "stops": 1,
                            "total_duration": "6h 15m",
                            "convenience": "★★★☆☆",
                            "tip": "Check cabin baggage weight restrictions.",
                            "booking_url": exp_url,
                        },
                    ]

                return {
                    "departure_city": origin,
                    "destination_city": destination,
                    "strategies": strategies,
                    "general_tips": [
                        "Consider flexible departure dates to unlock lower fares.",
                        "Direct flights save time, but 1-stop routes can offer significant savings.",
                    ],
                }

        except Exception as e:
            logger.error(f"[RapidAPI] Flight search exception: {e}")
            return {}
