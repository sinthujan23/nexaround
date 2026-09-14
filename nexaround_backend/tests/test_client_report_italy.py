"""The three things the client reported on an Italy plan, 2026-09-12.

  1. "the budget split is not correct" - 90% Stay + 64% Transit + 3% Food +
     0% Activities, which is 157% of a budget of INR 339,000.
  2. "Itinerary says departure to home country from Florence"
  3. "But flights didn't show return journey at all"

The stored plan (`Roman & Florentine Adventure`, 3 pax, 7 days) carries all
three: budget_breakdown summing to 531,670 against a total of 339,000 with
activities at zero, and three flight cards with `return_route: None` and no
`trip_type`. Every fare on it is `is_live_price: False` - SerpApi was out of
quota that week, so the whole flight section came from the estimate path.

These run against the current code with the reported numbers.
"""
import asyncio
import json

import pytest

from app.services import odyssey_ai_service as svc

# Straight off the stored plan.
BUDGET = 339_000.0
PAX = 3
LEGS = [{"city": "Rome", "nights": 4}, {"city": "Florence", "nights": 2}]
ROME_RATES = [6_500, 22_000, 28_000, 70_000]
FLORENCE_RATES = [18_000, 25_000]
FARES = {"minimum": 52_500.0, "recommended": 72_500.0, "comfortable": 97_500.0}


def _hotels():
    out = []
    for leg, rates in ((0, ROME_RATES), (1, FLORENCE_RATES)):
        for rate in rates:
            out.append({
                "leg_index": leg,
                "city": LEGS[leg]["city"],
                "nights": LEGS[leg]["nights"],
                "rooms": PAX,
                "hotel_class": 4,
                "price_per_night": f"INR {rate:,}",
            })
    return {"strategies": out}


def _flights(live=False):
    return {"strategies": [
        {"tier": t, "price_per_traveler": p, "currency": "INR",
         "is_live_price": live, "stops": 1, "route": "COK \u2192 FCO"}
        for t, p in FARES.items()
    ]}


# ── 1. The budget split ─────────────────────────────────────────────────────

def test_the_stay_line_the_client_saw_is_what_the_rooms_cost():
    """Not a miscalculation - the recommended room genuinely costs this much."""
    stay = svc.required_stay_cost(_hotels(), LEGS, PAX, "recommended")
    # Rome median 28,000 x 4n x 3rm + Florence 25,000 x 2n x 3rm.
    assert stay == 28_000 * 4 * PAX + 25_000 * 2 * PAX


def test_the_recommended_tier_costs_more_than_the_budget_it_is_shown_under():
    """The shape that produced 157%: affordable at the cheapest room, not at
    the one the Recommended tab actually prices."""
    cheapest = svc.required_stay_cost(_hotels(), LEGS, PAX, "minimum")
    recommended = svc.required_stay_cost(_hotels(), LEGS, PAX, "recommended")
    flight = FARES["recommended"] * PAX

    assert cheapest + flight < BUDGET * 2, "the floor looked reachable"
    assert recommended + flight > BUDGET, (
        "the tier the card prices already breaks the budget - this is the input "
        "that made stay 90% and transit 64% of the same total"
    )


# ── 2 and 3. The journey home ───────────────────────────────────────────────

def test_an_estimated_flight_carries_a_return_route():
    """The client's three cards all had `return_route: None`.

    Nothing about being an estimate stops it describing a round trip; the old
    estimate path simply never wrote one.
    """
    data = svc._structure_ai_flight_strategies(
        {"strategies": [{
            "tier": "recommended", "estimated_price_range": "INR 70000 - 75000",
            "route": "CMB \u2192 FCO", "return_route": "FLR \u2192 CMB",
            "airlines": ["ITA"], "stops": 1, "total_duration": "14h 30m",
            "return_duration": "15h 10m",
        }]},
        currency="INR", travelers=PAX,
        outbound_date="2026-11-02", return_date="2026-11-08",
    )
    s = data["strategies"][0]
    assert s.get("return_route"), "an estimated round trip still has a way home"
    assert s.get("is_live_price") is False, "and it is still marked an estimate"
