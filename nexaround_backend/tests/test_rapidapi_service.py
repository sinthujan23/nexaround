"""Unit tests for RapidAPIService."""
import asyncio
from app.services.rapidapi_service import RapidAPIService


def test_empty_api_key_returns_empty():
    service = RapidAPIService("")

    hotels = asyncio.run(
        service.search_hotels(
            destination="Paris",
            days=5,
            budget=1000,
            currency="USD",
        )
    )
    assert hotels == {}

    flights = asyncio.run(
        service.search_flights(
            departure_city="London",
            departure_country="UK",
            destination="Paris",
            days=5,
            budget=1000,
            currency="USD",
        )
    )
    assert flights == {}


def test_headers_construction():
    key = "test-rapidapi-key-12345"
    service = RapidAPIService(key)
    headers = service._get_headers("booking-com.p.rapidapi.com")
    assert headers["X-RapidAPI-Key"] == key
    assert headers["X-RapidAPI-Host"] == "booking-com.p.rapidapi.com"
    assert headers["Accept"] == "application/json"
