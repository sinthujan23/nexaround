import pytest

from app.services.serpapi_service import (
    extract_connecting_hub_strategies_from_serpapi,
)


def _leg(dep, arr, airline, number, minutes=240):
    return {
        "departure_airport": {"id": dep, "name": f"{dep} Airport", "time": "2026-11-09 10:00"},
        "arrival_airport": {"id": arr, "name": f"{arr} Airport", "time": "2026-11-09 14:00"},
        "duration": minutes,
        "airline": airline,
        "flight_number": number,
        "travel_class": "Economy",
    }


def _option(price, legs, total_duration=240):
    return {
        "flights": legs,
        "total_duration": total_duration,
        "price": price,
        "type": "Round trip",
    }


def test_connecting_hub_strategies_combines_prices_and_routes():
    # Leg 1: COK -> DXB ($200)
    leg1_data = {
        "best_flights": [
            _option(200, [_leg("COK", "DXB", "Emirates", "EK 531", minutes=240)]),
        ]
    }
    # Leg 2: DXB -> LAD ($600)
    leg2_data = {
        "best_flights": [
            _option(600, [_leg("DXB", "LAD", "Emirates", "EK 793", minutes=480)]),
        ]
    }

    result = extract_connecting_hub_strategies_from_serpapi(
        leg1_data,
        leg2_data,
        origin_code="COK",
        hub_code="DXB",
        dest_code="LAD",
        departure_city="Cochin",
        destination="Luanda",
        currency="USD",
        outbound_date="2026-11-09",
        return_date="2026-11-13",
        travelers=2,
    )

    assert result != {}
    strategies = result["strategies"]
    assert len(strategies) >= 1

    s = strategies[0]
    # Total price must be 200 + 600 = 800 per traveler
    assert s["price_per_traveler"] == 800.0
    # Group total for 2 travelers: 800 * 2 = 1600
    assert s["price_total"] == 1600.0
    # Route must show linear connection
    assert s["route"] == "COK → DXB → LAD"
    assert s["return_route"] == "LAD → DXB → COK"
    assert s["stops"] >= 1
    assert "Emirates" in s["airlines"]
    assert s["outbound"]["origin"] == "COK"
    assert s["outbound"]["destination"] == "LAD"
    assert s["return_leg"]["origin"] == "LAD"
    assert s["return_leg"]["destination"] == "COK"


def test_connecting_hub_strategies_empty_when_a_leg_has_no_options():
    leg1_data = {"best_flights": []}
    leg2_data = {
        "best_flights": [
            _option(600, [_leg("DXB", "LAD", "Emirates", "EK 793")]),
        ]
    }
    result = extract_connecting_hub_strategies_from_serpapi(
        leg1_data,
        leg2_data,
        origin_code="COK",
        hub_code="DXB",
        dest_code="LAD",
        departure_city="Cochin",
        destination="Luanda",
        currency="USD",
    )
    assert result == {}
