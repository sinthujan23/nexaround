"""The transit note must name a card the traveller can actually find.

`transit_cost_lines` and `budget_flight_basis` both fall back to the cheapest
live fare when the requested tier has no card. The money was right; the
sentence beside it was not. A live Colombo -> Hanoi plan came back with only
Minimum and Comfortable - the Pareto frontier collapsed to two points - and the
budget still read "Based on the best value flight", pointing at a card that was
not on the Flights tab.
"""
import pytest

from app.services.odyssey_ai_service import (
    budget_flight_basis,
    effective_flight_tier,
    _budget_notes,
)


def _flights(*fares):
    """fares: (tier, price_per_traveler, stops, live)."""
    return {"strategies": [
        {"tier": t, "price_per_traveler": p, "stops": s, "is_live_price": live}
        for t, p, s, live in fares
    ]}


def _note(fs, tier="recommended", **kw):
    opts = dict(rooms=1, at_star_floor=True, no_airfare=False)
    opts.update(kw)
    return _budget_notes(
        flight_basis=budget_flight_basis(fs, tier),
        tier=tier,
        flight_tier=effective_flight_tier(fs, tier),
        **opts,
    )


ALL_THREE = (
    ("minimum", 30767.0, 1, True),
    ("recommended", 33000.0, 1, True),
    ("comfortable", 35082.0, 1, True),
)
HANOI = (  # what the live plan actually shipped
    ("minimum", 30767.0, 1, True),
    ("comfortable", 35082.0, 1, True),
)


def test_the_named_tier_is_used_when_it_has_a_card():
    fs = _flights(*ALL_THREE)
    assert effective_flight_tier(fs, "recommended") == "recommended"
    assert "best value" in _note(fs)["summary"]


def test_a_missing_recommended_card_is_not_named_anyway():
    """The regression: two cards, and the note claimed a third."""
    fs = _flights(*HANOI)
    assert effective_flight_tier(fs, "recommended") == "minimum"
    note = _note(fs)
    assert "best value" not in note["summary"], "names a card that is not on the tab"
    assert "lowest-priced" in note["summary"]
    assert "lowest-priced" in note["transit"]


def test_the_clients_verbatim_wording_needs_a_real_best_value_card():
    """"Based on Best Value Direct Flight" is his exact sentence - it may only
    appear where a Recommended card actually carried the non-stop."""
    with_rec = _flights(
        ("minimum", 30000.0, 1, True),
        ("recommended", 33000.0, 0, True),
    )
    assert _note(with_rec)["transit"] == "Based on Best Value Direct Flight"

    without_rec = _flights(("minimum", 30000.0, 0, True), ("comfortable", 40000.0, 1, True))
    assert effective_flight_tier(without_rec, "recommended") == "minimum"
    assert _note(without_rec)["transit"] == "Based on the lowest-priced direct flight."


@pytest.mark.parametrize("tier", ["minimum", "recommended", "comfortable"])
def test_each_tab_still_describes_its_own_card_when_it_has_one(tier):
    fs = _flights(*ALL_THREE)
    assert effective_flight_tier(fs, tier) == tier


def test_the_stay_wording_still_follows_the_tab_not_the_fare():
    """Only the flight half borrows another tier's name.

    Rooms are priced per tab and every tab has one, so the Recommended tab must
    go on saying "mid-priced room" even when its fare had to be read off the
    Minimum card.
    """
    note = _note(_flights(*HANOI), tier="recommended")
    assert note["stay"].startswith("Based on the mid-priced"), note["stay"]
    assert "lowest-priced" in note["transit"], "the fare really did come from Minimum"


def test_a_tier_that_does_have_a_card_still_names_itself():
    note = _note(_flights(*HANOI), tier="comfortable")
    assert "highest-priced" in note["transit"]
    assert note["stay"].startswith("Based on the highest-priced")


def test_nothing_priced_leaves_the_requested_tier_alone():
    assert effective_flight_tier({}, "recommended") == "recommended"
    assert effective_flight_tier({"strategies": []}, "minimum") == "minimum"
    assert "transit" not in _note({})


def test_an_estimated_fare_is_not_dressed_up_as_a_tier():
    fs = _flights(("minimum", 30000.0, 0, False))
    assert budget_flight_basis(fs) == "estimated"
    assert effective_flight_tier(fs, "recommended") == "recommended"
    assert _note(fs)["transit"].startswith("Based on an estimated fare")
