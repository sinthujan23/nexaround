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

def _breakdown(stays, legs, fs, tier, travelers=3, food_share=0.6):
    stay = required_stay_cost(stays, legs, travelers, tier)
    transit = tier_flight_cost(fs, travelers, tier)
    total = round((stay + transit) * 1.35, 2)
    rest = total - stay - transit
    return {
        "stay": stay, "transit": transit,
        "food": round(rest * food_share, 2),
        "activities": round(rest * (1 - food_share), 2),
        "total": total,
    }


def _basis(stays, legs, fs, tier, **kw):
    args = dict(
        tier=tier,
        breakdown=_breakdown(stays, legs, fs, tier),
        flight_strategies=fs, hotel_strategies=stays, city_legs=legs,
        travelers=3, days=12, currency="USD", food_share=0.6,
        no_airfare=False, at_star_floor=False,
    )
    args.update(kw)
    return budget_basis(**args)


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
    block = budget_basis(
        tier=tier, breakdown=bd, flight_strategies=fs, hotel_strategies=stays,
        city_legs=legs, travelers=3, days=12, currency="USD", food_share=0.6,
        no_airfare=False, at_star_floor=False,
    )
    items = block["stay"]["items"]
    assert round(sum(i["amount"] for i in items), 2) == bd["stay"]
    assert block["stay"]["total"] == bd["stay"]


def test_the_food_ladder_ends_on_the_food_bar(stays, legs):
    fs = _flights(("minimum", 400.0, 1, True))
    bd = _breakdown(stays, legs, fs, "minimum")
    block = _basis(stays, legs, fs, "minimum")
    items = block["food"]["items"]
    assert items[-1]["amount"] == bd["food"]
    left = next(i for i in items if i["label"].startswith("Left for"))
    assert left["amount"] == round(bd["total"] - bd["transit"] - bd["stay"], 2)
    assert block["activities"]["items"][-1]["amount"] == bd["activities"]


def test_the_transit_sheet_owns_up_to_the_85_percent_cap(stays, legs):
    """A fare bigger than the budget is held at 85%; both figures get printed.

    Without the second row the sheet would show a fare that is not the bar
    beneath it — the precise way an explanation becomes a new bug report.
    """
    fs = _flights(("minimum", 9000.0, 0, True))
    bd = _breakdown(stays, legs, fs, "minimum")
    bd["transit"] = round(bd["total"] * 0.85, 2)   # what `_waterfall` does
    block = budget_basis(
        tier="minimum", breakdown=bd, flight_strategies=fs,
        hotel_strategies=stays, city_legs=legs, travelers=3, days=12,
        currency="USD", food_share=0.6, no_airfare=False, at_star_floor=False,
    )
    items = block["transit"]["items"]
    assert len(items) == 2
    assert items[-1]["amount"] == bd["transit"]
    assert "85%" in items[-1]["label"]


def test_a_route_with_no_fares_is_not_given_an_invented_derivation(stays, legs):
    """`_waterfall` still reserves 30% for transit; the sheet must say so.

    Naming a fare here would be inventing one — the failure mode the whole
    sheet exists to avoid.
    """
    fs = {"strategies": []}
    bd = _breakdown(stays, legs, fs, "minimum")
    bd["transit"] = round(bd["total"] * 0.30, 2)
    block = budget_basis(
        tier="minimum", breakdown=bd, flight_strategies=fs,
        hotel_strategies=stays, city_legs=legs, travelers=3, days=12,
        currency="USD", food_share=0.6, no_airfare=False, at_star_floor=False,
    )
    only = block["transit"]["items"][0]
    assert only["label"] == "Estimated share of the budget"
    assert only["amount"] == bd["transit"]


def test_the_ground_only_trip_says_ground_only(stays, legs):
    block = _basis(stays, legs, {"strategies": []}, "minimum", no_airfare=True)
    assert block["transit"]["items"][0]["label"] == "Ground transport only"
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
