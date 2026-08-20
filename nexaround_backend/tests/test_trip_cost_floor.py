"""The budget floor that keeps impossible trips away from the model.

Every case here is about one of two failure modes, and they are not equally
bad: letting an absurd budget through wastes a Gemini call plus two SerpAPI
lookups, while blocking a real trip stops a paying traveller from using the
feature at all. The tests lean hard on the second never happening.
"""
import pytest

from app.services import trip_cost_floor as tcf


def _floor(dest, days=3, travelers=1, currency="LKR", departure="LK", flights=True):
    return tcf.minimum_budget(
        destination=dest, days=days, travelers=travelers, currency=currency,
        departure_country=departure, include_flights=flights,
    )


# ── The case that prompted this ─────────────────────────────────────────────

def test_two_hundred_rupees_cannot_buy_three_days_in_dubai():
    floor = _floor("Dubai")
    assert floor is not None
    assert 200 < floor["minimum"]
    assert floor["includes_flight"] is True


def test_a_realistic_dubai_budget_is_allowed():
    floor = _floor("Dubai")
    assert 250_000 >= floor["minimum"], "a realistic budget must not be blocked"


# ── Never block when unsure ─────────────────────────────────────────────────

@pytest.mark.parametrize("destination", [
    "Atlantis", "Narnia", "somewhere nice", "", "   ", "zzzz",
])
def test_unknown_destinations_are_allowed_through(destination):
    """The floor must stay silent unless it is confident. A wrong guess here
    stops a real traveller; a miss merely costs one generation."""
    assert _floor(destination) is None


def test_unknown_currency_is_allowed_through():
    assert _floor("Dubai", currency="XYZ") is None


# ── Domestic trips carry no flight floor ────────────────────────────────────

def test_domestic_trips_do_not_add_a_flight_floor():
    floor = tcf.minimum_budget(
        destination="Kandy", days=3, currency="LKR",
        departure_country="LK", include_flights=False,
    )
    assert floor is not None
    assert floor["includes_flight"] is False
    assert floor["flight_usd"] == 0


def test_a_blank_departure_country_is_treated_as_domestic():
    """Under-counting is the safe direction: assuming a flight the traveller is
    not taking would block a trip they can afford."""
    floor = tcf.minimum_budget(
        destination="Kandy", days=3, currency="LKR",
        departure_country="", include_flights=False,
    )
    assert floor is not None
    assert floor["includes_flight"] is False


# ── The floor scales with the trip ──────────────────────────────────────────

def test_more_days_costs_more():
    assert _floor("Dubai", days=7)["minimum"] > _floor("Dubai", days=3)["minimum"]


def test_more_travellers_costs_more():
    assert _floor("Dubai", travelers=3)["minimum"] > _floor("Dubai", travelers=1)["minimum"]


def test_expensive_countries_cost_more_than_cheap_ones():
    assert _floor("Switzerland")["minimum"] > _floor("India")["minimum"]


def test_currency_is_respected():
    """200 LKR and 200 USD are three orders of magnitude apart; comparing
    either against one threshold would be meaningless."""
    lkr = _floor("Dubai", currency="LKR")["minimum"]
    usd = _floor("Dubai", currency="USD")["minimum"]
    assert lkr > usd * 100


# ── Place matching ──────────────────────────────────────────────────────────

@pytest.mark.parametrize("text,expected", [
    ("Dubai", "AE"), ("dubai", "AE"), ("Dubai, UAE", "AE"),
    ("  DUBAI  ", "AE"), ("New York", "US"), ("Colombo", "LK"),
    ("Kandy, Sri Lanka", "LK"),
])
def test_place_names_resolve(text, expected):
    assert tcf.country_for(text) == expected


def test_longest_match_wins():
    """'new zealand' must not be resolved by a stray 'new york' fragment or
    vice versa."""
    assert tcf.country_for("New Zealand") == "NZ"
    assert tcf.country_for("New York") == "US"


# ── The message ─────────────────────────────────────────────────────────────

def test_the_message_names_the_amount_to_type():
    """'Too low' leaves the traveller guessing, and guessing costs another
    round trip."""
    floor = _floor("Dubai")
    msg = tcf.shortfall_message(floor, "Dubai")
    assert "Dubai" in msg
    assert f"{floor['minimum']:,.0f}" in msg
    assert "3-day" in msg, "attributive form is singular"
    assert "3-days" not in msg


def test_the_message_mentions_travellers_only_when_plural():
    assert "travellers" not in tcf.shortfall_message(_floor("Dubai"), "Dubai")
    assert "3 travellers" in tcf.shortfall_message(
        _floor("Dubai", travelers=3), "Dubai"
    )


# ── Floors must stay floors ─────────────────────────────────────────────────

def test_daily_floors_stay_austere():
    """These are dorm-bed-and-street-food numbers. If one drifts upward into
    'realistic' territory it starts blocking genuine shoestring travellers."""
    for tier, amount in tcf.DAILY_FLOOR_USD.items():
        assert 10 <= amount <= 200, f"{tier} floor of ${amount} is not a floor"


def test_every_tier_named_by_a_country_actually_exists():
    for country, tier in tcf.COUNTRY_TIER.items():
        assert tier in tcf.DAILY_FLOOR_USD, f"{country} points at unknown tier {tier}"


def test_every_place_maps_to_a_country_we_price():
    for place, country in tcf.PLACE_COUNTRY.items():
        assert country in tcf.COUNTRY_TIER, f"{place} -> {country} has no tier"
