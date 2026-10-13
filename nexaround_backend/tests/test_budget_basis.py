"""The explanation behind each Budget Allocation bar, and its tie to the bar.

The client asked for every category on the card to open and say how it was
arrived at. The risk in answering that is not the wording — it is that the
explanation and the bar are computed twice and drift, which is the shape of the
"budget split does not add up" report he already sent once. So the rule these
pin down is one rule: **whatever the sheet prints must sum to the bar it sits
under**, on every tier, including the fallbacks nobody looks at.
"""
import pytest

from app.services.odyssey_ai_service import (
    budget_basis,
    required_stay_cost,
    stay_cost_lines,
    tier_flight_cost,
    tier_food_cost,
    transit_cost_lines,
    _budget_notes,
    _rooms_for,
)

TIERS = ("minimum", "recommended", "comfortable")


def _room(name, nightly, hotel_class, leg_index, city):
    return {
        "name": name,
        "price_per_night": f"USD {nightly}",
        "hotel_class": hotel_class,
        "leg_index": leg_index,
        "city": city,
    }


@pytest.fixture
def stays():
    """Three cities: one normal, one with nothing classed, one never searched."""
    return {"strategies": [
        _room("Rome Grand", 120, 4, 0, "Rome"),
        _room("Rome Mid", 95, 3, 0, "Rome"),
        _room("Rome Hostel", 30, 0, 0, "Rome"),
        _room("Florence Guesthouse", 55, 0, 1, "Florence"),
        _room("Florence Rooms", 70, 0, 1, "Florence"),
    ]}


@pytest.fixture
def legs():
    return [
        {"city": "Rome", "nights": 5},
        {"city": "Florence", "nights": 4},
        {"city": "Venice", "nights": 3},
    ]


def _flights(*fares):
    """fares: (tier, price_per_traveler, stops, live)."""
    return {"strategies": [
        {
            "tier": tier, "price_per_traveler": price, "stops": stops,
            "is_live_price": live, "route": "CMB → FCO",
            "airlines": ["SriLankan Airlines"],
        }
        for tier, price, stops, live in fares
    ]}


# ── The sheet is the bar, not a second opinion ──────────────────────────────

@pytest.mark.parametrize("tier", TIERS)
def test_the_stay_lines_add_up_to_the_stay_bar(stays, legs, tier):
    lines = stay_cost_lines(stays, legs, 3, tier)
    assert lines, "every slept-in leg must be priced"
    assert round(sum(ln["amount"] for ln in lines), 2) == required_stay_cost(
        stays, legs, 3, tier,
    )


@pytest.mark.parametrize("tier", TIERS)
def test_every_slept_in_city_gets_its_own_line(stays, legs, tier):
    """Including Venice, which was never searched and is priced from the pool."""
    cities = [ln["city"] for ln in stay_cost_lines(stays, legs, 3, tier)]
    assert cities == ["Rome", "Florence", "Venice"]


def test_a_line_says_how_its_rate_was_found(stays, legs):
    by_city = {ln["city"]: ln for ln in stay_cost_lines(stays, legs, 3, "minimum")}
    # Rome has 3-star and above, so the hostel never sets its rate.
    assert by_city["Rome"]["basis"] == "classed"
    assert by_city["Rome"]["nightly"] == 95
    # Florence lists nothing classed at all — priced from what is there.
    assert by_city["Florence"]["basis"] == "unclassed"
    assert by_city["Florence"]["nightly"] == 55
    # Venice was never searched; the trip's other rooms stand in.
    assert by_city["Venice"]["basis"] == "pooled"


def test_rooms_are_one_per_traveller_on_every_line(stays, legs):
    lines = stay_cost_lines(stays, legs, 3, "minimum")
    assert {ln["rooms"] for ln in lines} == {_rooms_for(3)}
    rome = next(ln for ln in lines if ln["city"] == "Rome")
    assert rome["amount"] == 95 * 5 * _rooms_for(3)


@pytest.mark.parametrize("tier", TIERS)
def test_the_fare_line_adds_up_to_the_transit_bar(tier):
    fs = _flights(
        ("minimum", 400.0, 1, True),
        ("recommended", 520.0, 0, True),
        ("comfortable", 780.0, 0, True),
    )
    lines = transit_cost_lines(fs, 3, tier)
    assert round(sum(ln["amount"] for ln in lines), 2) == round(
        tier_flight_cost(fs, 3, tier), 2,
    )
    assert lines[0]["travelers"] == 3


def test_the_fare_line_says_when_the_tier_had_no_card_of_its_own():
    """`tier_flight_cost` falls back to the cheapest; the sheet must admit it."""
    fs = _flights(("recommended", 520.0, 0, True))
    line = transit_cost_lines(fs, 2, "minimum")[0]
    assert line["tier_exact"] is False
    assert line["amount"] == 520.0 * 2


def test_no_fares_means_no_fare_line():
    assert transit_cost_lines({"strategies": []}, 2, "minimum") == []
    assert transit_cost_lines(None, 2, "minimum") == []
    assert tier_flight_cost(None, 2, "minimum") == 0.0


# ── The card's four blocks ──────────────────────────────────────────────────

# What `ground_costs` returns for a 12-day, three-traveller plan that priced
# its meals, its tickets (two left unpriced) and its rides.
GROUND = {
    "tier": "upper",
    "food_per_day": 50.0, "food_source": "plan", "food_typical": 45.0,
    "food_held": "", "meal_average": 20.0, "meals_priced": 20,
    "activities": 900.0, "activities_source": "plan",
    "activities_priced": 8, "activities_estimated": 2, "activities_estimate": 150.0,
    "transport": 420.0, "transport_source": "plan",
    "transport_priced": 6, "transport_estimated": 0, "transport_estimate": 0.0,
    "days": 12, "travelers": 3,
}


def _breakdown(stays, legs, fs, tier, travelers=3, ground=GROUND):
    """One tab the way `generate_odyssey` builds it."""
    stay = required_stay_cost(stays, legs, travelers, tier)
    transit = round(tier_flight_cost(fs, travelers, tier) + ground["transport"], 2)
    food = tier_food_cost(ground, tier)
    activities = ground["activities"]
    return {
        "stay": stay, "transit": transit, "food": food, "activities": activities,
        "total": round(stay + transit + food + activities, 2),
    }


def _basis(stays, legs, fs, tier, ground=GROUND, **kw):
    args = dict(
        tier=tier,
        breakdown=_breakdown(stays, legs, fs, tier, ground=ground),
        flight_strategies=fs, hotel_strategies=stays, city_legs=legs,
        travelers=3, days=12, currency="USD", ground=ground,
        no_airfare=False, at_star_floor=False,
    )
    args.update(kw)
    return budget_basis(**args)


def _sheet_sum(block, line):
    return round(sum(i["amount"] for i in block[line]["items"]), 2)


@pytest.mark.parametrize("tier", TIERS)
def test_every_category_explains_itself(stays, legs, tier):
    fs = _flights(("minimum", 400.0, 1, True), ("recommended", 520.0, 0, True))
    block = _basis(stays, legs, fs, tier)
    assert set(block) == {"summary", "stay", "transit", "food", "activities"}
    for name in ("stay", "transit", "food", "activities"):
        part = block[name]
        assert part["formula"], f"{name} has no formula line"
        assert part["items"], f"{name} explains nothing"
        assert part["total"] > 0, name


@pytest.mark.parametrize("tier", TIERS)
def test_the_stay_sheet_sums_to_the_stay_bar(stays, legs, tier):
    fs = _flights(("recommended", 520.0, 0, True))
    bd = _breakdown(stays, legs, fs, tier)
    block = _basis(stays, legs, fs, tier)
    items = block["stay"]["items"]
    assert round(sum(i["amount"] for i in items), 2) == bd["stay"]
    assert block["stay"]["total"] == bd["stay"]


@pytest.mark.parametrize("tier", TIERS)
@pytest.mark.parametrize("line", ["transit", "food", "activities"])
def test_every_sheet_sums_to_its_bar(stays, legs, tier, line):
    fs = _flights(("minimum", 400.0, 1, True), ("recommended", 520.0, 0, True))
    bd = _breakdown(stays, legs, fs, tier)
    block = _basis(stays, legs, fs, tier)
    assert _sheet_sum(block, line) == bd[line]
    assert block[line]["total"] == bd[line]


def test_the_transit_sheet_is_the_fare_and_the_day_plans_rides(stays, legs):
    fs = _flights(("minimum", 400.0, 1, True))
    block = _basis(stays, legs, fs, "minimum")
    fare, rides = block["transit"]["items"]
    assert fare["amount"] == 1200.0                      # 400 x 3 travellers
    assert rides["label"] == "Getting around"
    assert rides["amount"] == GROUND["transport"]
    assert block["transit"]["formula"].endswith("+ getting around")


def test_unpriced_rides_are_shown_as_their_own_row(stays, legs):
    ground = dict(GROUND, transport=500.0, transport_estimated=2, transport_estimate=80.0)
    fs = _flights(("minimum", 400.0, 1, True))
    block = _basis(stays, legs, fs, "minimum", ground=ground)
    rows = block["transit"]["items"]
    assert [r["amount"] for r in rows] == [1200.0, 420.0, 80.0]
    assert rows[-1]["label"] == "2 more rides without a price"


def test_a_route_with_no_fares_is_not_given_an_invented_derivation(stays, legs):
    """No fare is no airfare in the total, said out loud - never a share of
    the budget dressed up as a flight."""
    block = _basis(stays, legs, {"strategies": []}, "minimum")
    assert [i["label"] for i in block["transit"]["items"]] == ["Getting around"]
    assert block["transit"]["caveat"] == (
        "No fare came back for this route, so no airfare is included."
    )


def test_flights_left_out_say_so(stays, legs):
    block = _basis(stays, legs, {"strategies": []}, "minimum", flights_included=False)
    assert "you chose to book them yourself" in block["transit"]["caveat"]


def test_the_ground_only_trip_says_ground_only(stays, legs):
    block = _basis(stays, legs, {"strategies": []}, "minimum", no_airfare=True)
    assert block["transit"]["items"][0]["label"] == "Getting around"
    assert block["transit"]["caveat"] == "Nothing flies this route, so this is ground transport only."
    assert "transit" not in _budget_notes(
        rooms=3, at_star_floor=False, flight_basis="none", no_airfare=True,
    )


# ── The note describes the tier it is shown on ──────────────────────────────

def test_the_note_follows_the_fare_its_own_tier_priced(stays, legs):
    """Cheapest fare connects, dearest is direct — neither note may borrow the
    other's sentence, which is what one note for all three tabs was doing."""
    fs = _flights(
        ("minimum", 400.0, 1, True),
        ("recommended", 520.0, 0, True),
    )
    cheap = _basis(stays, legs, fs, "minimum")
    mid = _basis(stays, legs, fs, "recommended")
    assert "Direct" not in cheap["transit"]["note"]
    assert "No direct flight is offered" in cheap["transit"]["note"]
    assert mid["transit"]["note"] == "Based on Best Value Direct Flight"


def test_an_estimated_fare_is_never_called_a_direct_flight(stays, legs):
    fs = _flights(("minimum", 400.0, 0, False))
    block = _basis(stays, legs, fs, "minimum")
    assert "estimated" in block["transit"]["note"].lower()
    assert "No live fare" in block["transit"]["caveat"]


def test_the_stay_note_admits_when_the_star_floor_gave_way(stays):
    """Florence lists nothing at 3 stars; the sheet says so rather than
    repeating a floor it did not hold to."""
    fs = _flights(("minimum", 400.0, 1, True))
    searched = [{"city": "Rome", "nights": 5}, {"city": "Florence", "nights": 4}]
    block = _basis(stays, searched, fs, "minimum")
    assert "3-star" not in block["stay"]["note"]
    assert "3 stars or above" in block["stay"]["caveat"]


def test_the_stay_sheet_admits_a_city_it_never_priced(stays, legs):
    """Venice was never searched, so its nights carry the trip's other rates."""
    fs = _flights(("minimum", 400.0, 1, True))
    block = _basis(stays, legs, fs, "minimum")
    assert "came back empty" in block["stay"]["caveat"]


def test_the_per_day_line_divides_by_party_and_days(stays, legs):
    fs = _flights(("minimum", 400.0, 1, True))
    bd = _breakdown(stays, legs, fs, "minimum")
    block = _basis(stays, legs, fs, "minimum")
    per_day = bd["food"] / (3 * 12)
    assert f"{per_day:,.0f}" in block["food"]["note"]


# ── What a line may and may not claim about itself ──────────────────────────

def test_a_borrowed_rate_is_not_attributed_to_another_citys_hotel(stays, legs):
    """Venice was never searched, so its nights carry a Rome or Florence rate.

    Printing that property's name against Venice told the traveller they were
    being quoted a Venice hotel that does not exist there — found by running a
    five-city plan through the whole generator, where a Hakone leg came back
    reading "Kyoto Ryokan".
    """
    venice = next(
        ln for ln in stay_cost_lines(stays, legs, 3, "minimum")
        if ln["city"] == "Venice"
    )
    assert venice["basis"] == "pooled"
    assert venice["hotel"] == ""
    assert venice["hotel_class"] == 0
    assert venice["nightly"] > 0, "the rate itself still stands in"

    fs = _flights(("minimum", 400.0, 1, True))
    block = _basis(stays, legs, fs, "minimum")
    line = next(i for i in block["stay"]["items"] if i["label"].startswith("Venice"))
    for name in ("Rome", "Florence", "Hostel", "Guesthouse", "Grand", "Mid"):
        assert name not in line["detail"], line["detail"]


def test_a_thin_market_says_why_two_tabs_quote_the_same_room(stays, legs):
    """A city with two rooms prices its middle and dearest the same.

    `_rate_for_tier` ranks by price, so with two options the median *is* the
    dearest and the Recommended tab quotes the Comfortable one. The arithmetic
    is left alone — with two rooms some pair must coincide — but the sheet says
    so rather than leaving the card looking broken, which is how the client
    reported the silent version of this.
    """
    two_rooms = {"strategies": [
        _room("Zurich Altstadt", 420, 4, 0, "Zurich"),
        _room("Zurich Grand", 780, 5, 0, "Zurich"),
    ]}
    one_leg = [{"city": "Zurich", "nights": 2}]
    fs = _flights(("minimum", 400.0, 0, True))

    assert (required_stay_cost(two_rooms, one_leg, 1, "recommended")
            == required_stay_cost(two_rooms, one_leg, 1, "comfortable"))

    mid = _basis(two_rooms, one_leg, fs, "recommended")
    assert "same room as another" in mid["stay"]["caveat"]
    cheapest = _basis(two_rooms, one_leg, fs, "minimum")
    assert cheapest["stay"]["caveat"] == "", "the cheapest room is unambiguous"


# ── Food and activities say where their figure came from ─────────────────────
#
# Both used to be "what is left after flights and rooms", which made them grow
# with whatever budget was typed: a 13-day Germany plan at the planner's
# default USD 50,000 put USD 2,459 a day into one person's food. They are now
# priced from the day plan, and the sheet names what it priced from.

def _fs():
    return _flights(("recommended", 520.0, 0, True))


def test_the_food_sheet_names_the_plans_own_meals(stays, legs):
    block = _basis(stays, legs, _fs(), "recommended")
    row = block["food"]["items"][0]
    assert row["label"] == "12 days × 3 travellers"
    assert row["detail"].startswith("USD 50 a day each")
    assert "average USD 20 a meal" in row["detail"]
    assert block["food"]["formula"] == "A day of eating × 12 days × 3 travellers"
    assert block["food"]["caveat"] == ""


def test_each_tier_says_how_it_eats(stays, legs):
    cheap = _basis(stays, legs, _fs(), "minimum")["food"]["items"][0]["detail"]
    dear = _basis(stays, legs, _fs(), "comfortable")["food"]["items"][0]["detail"]
    assert cheap.startswith("USD 30 a day each") and "street food" in cheap
    assert dear.startswith("USD 80 a day each") and "restaurants throughout" in dear


def test_a_plan_without_meal_prices_says_it_used_typical_eating(stays, legs):
    ground = dict(GROUND, food_source="typical", meal_average=None, meals_priced=0, food_per_day=45.0)
    block = _basis(stays, legs, _fs(), "recommended", ground=ground)
    assert "Typical mid-range eating" in block["food"]["items"][0]["detail"]
    assert "doesn't price its meals" in block["food"]["caveat"]


def test_a_capped_day_of_eating_says_it_was_capped(stays, legs):
    ground = dict(GROUND, food_held="high", food_per_day=90.0)
    block = _basis(stays, legs, _fs(), "recommended", ground=ground)
    assert "twice its typical spend" in block["food"]["caveat"]


def test_the_activities_sheet_separates_priced_and_unpriced_stops(stays, legs):
    rows = _basis(stays, legs, _fs(), "recommended")["activities"]["items"]
    assert [r["amount"] for r in rows] == [750.0, 150.0]
    assert rows[0]["detail"] == "8 priced stops × 3 travellers"
    assert rows[1]["label"] == "2 more stops without a price"


def test_typical_activities_say_so(stays, legs):
    ground = dict(GROUND, activities=792.0, activities_source="typical",
                  activities_priced=0, activities_estimated=0, activities_estimate=0.0)
    block = _basis(stays, legs, _fs(), "recommended", ground=ground)
    row = block["activities"]["items"][0]
    assert row["label"] == "Typical entry fees and tours"
    assert row["detail"].startswith("USD 22 a day")          # 792 / (12 days x 3)
    assert "doesn't price its tickets" in block["activities"]["caveat"]


def test_a_free_day_plan_has_free_activities(stays, legs):
    ground = dict(GROUND, activities=0.0, activities_source="free",
                  activities_priced=0, activities_estimated=0, activities_estimate=0.0)
    block = _basis(stays, legs, _fs(), "recommended", ground=ground)
    assert block["activities"]["items"] == [
        {"label": "Everything in your day plan is free to visit", "detail": "", "amount": 0.0},
    ]
    assert block["activities"]["note"] == ""
