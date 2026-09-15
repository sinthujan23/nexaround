"""The hotels a traveller is offered, and what their stay is quoted at.

Two things were wrong and are pinned here.

1. "Only 3-star and above" was implemented as `overall_rating >= 4.0` — a guest
   review score, not a star class. The two are unrelated: a hostel its guests
   love clears a 4.0 review floor, and a real 3-star hotel rated 3.9 does not.
   Filtering now goes to Google as `hotel_class=3,4,5`.

2. The Stays tab and the Budget Allocation quoted the same stay at two
   different prices. The tab showed Google's `total_rate` — one room, for
   whatever window was searched — while the budget multiplied the nightly rate
   by nights *and by the rooms the party needs*. For three travellers the tab
   read half the budget line.
"""
import copy

import pytest

from app.services.serpapi_service import (
    extract_hotel_strategies_from_serpapi,
    hotel_class_param,
    nights_between,
    property_hotel_class,
    rooms_for,
)


def _prop(name, *, nightly, hotel_class=None, rating=4.2, total=None, extracted_class=True):
    p = {
        "name": name,
        "overall_rating": rating,
        "reviews": 500,
        "rate_per_night": {"lowest": f"${nightly}", "extracted_lowest": nightly},
        "amenities": ["Wi-Fi", "Pool"],
    }
    if total is not None:
        p["total_rate"] = {"lowest": f"${total}", "extracted_lowest": total}
    if hotel_class is not None:
        p["hotel_class"] = f"{hotel_class}-star hotel"
        if extracted_class:
            p["extracted_hotel_class"] = hotel_class
    return p


# ── The class filter Google is actually asked for ───────────────────────────

@pytest.mark.parametrize("floor,expected", [
    (3, "3,4,5"),   # what "3-star and above" means
    (4, "4,5"),
    (5, "5"),
    (2, "2,3,4,5"),
    (0, ""),        # no filter — not "1,2,3,4,5", which Google rejects
    (1, ""),        # Google has no 1-star class
    (6, ""),
])
def test_hotel_class_param(floor, expected):
    assert hotel_class_param(floor) == expected


def test_hotel_class_param_survives_junk():
    assert hotel_class_param(None) == ""
    assert hotel_class_param("nonsense") == ""


# ── Reading the class back off a property ───────────────────────────────────

def test_class_read_from_extracted_integer():
    assert property_hotel_class({"extracted_hotel_class": 4}) == 4


def test_class_read_from_prose_when_integer_missing():
    """A 4-star hotel must not be mistaken for an unclassed one and dropped."""
    assert property_hotel_class({"hotel_class": "4-star hotel"}) == 4


def test_unclassed_property_is_zero():
    assert property_hotel_class({"name": "Some Guesthouse"}) == 0
    assert property_hotel_class({"extracted_hotel_class": True}) == 0


# ── Rooms: the party-size half of the mismatch ──────────────────────────────

@pytest.mark.parametrize("travelers,rooms", [
    (1, 1), (2, 2),        # one room each; sharing is the party's own call
    (3, 3), (4, 4),
    (5, 5), (6, 6),
    (0, 1), (None, 1),     # never zero rooms
])
def test_rooms_for(travelers, rooms):
    assert rooms_for(travelers) == rooms


def test_nights_between():
    assert nights_between("2026-10-01", "2026-10-06") == 5
    assert nights_between("2026-10-01", "2026-10-01") == 0
    assert nights_between("", "2026-10-06") == 0
    # Undeterminable is 0, never a silent 1 — quoting one night for a whole
    # trip is the failure this replaces.
    assert nights_between("not-a-date", "2026-10-06") == 0


# ── Est. Total = nightly x nights x rooms ───────────────────────────────────

FIXTURE = {"properties": [
    _prop("Cinnamon Grand", nightly=100, hotel_class=5, total=500),
    _prop("Fair View Hotel", nightly=40, hotel_class=3, total=200),
]}


def _extract(**kw):
    args = dict(
        destination="Colombo", currency="USD",
        check_in_date="2026-10-01", check_out_date="2026-10-06",
    )
    args.update(kw)
    return extract_hotel_strategies_from_serpapi(FIXTURE, **args)


def test_stay_total_is_per_party_not_per_room():
    """Three travellers need three rooms, and the quote has to say so.

    Google's own `total_rate` for these dates is $200 — one room. The party
    pays three times that, which is also what the budget allocation charges
    them. Sharing is the travellers' own decision to make against this figure;
    a budget that has already assumed it cannot be corrected by anyone.
    """
    solo = _extract(travelers=1)["strategies"][1]
    trio = _extract(travelers=3)["strategies"][1]

    assert solo["rooms"] == 1 and trio["rooms"] == 3
    assert solo["total_estimated_cost"] == "USD 200"     # 40 x 5 x 1
    assert trio["total_estimated_cost"] == "USD 600"     # 40 x 5 x 3


def test_stay_total_matches_the_budget_stay_line():
    """The two screens must agree to the rupee.

    The budget's stay line is the cheapest hotel of each leg priced as
    `nightly x nights x rooms` (`_required_stay_cost`). Reproduced here so the
    Stays tab's own figure is checked against it rather than against itself.
    """
    from app.services.odyssey_ai_service import _extract_lowest_price, _rooms_for

    travelers, nights = 3, 5
    strategies = _extract(travelers=travelers)["strategies"]

    cheapest_nightly = min(_extract_lowest_price(s["price_per_night"]) for s in strategies)
    budget_stay_line = cheapest_nightly * nights * _rooms_for(travelers)

    cheapest_card = min(strategies, key=lambda s: _extract_lowest_price(s["price_per_night"]))
    # Parsed with the budget's own parser, not massaged first — the thousands
    # separators in the formatted total have to survive the round trip.
    tab_total = _extract_lowest_price(cheapest_card["total_estimated_cost"])

    assert tab_total == budget_stay_line == 600.0


def test_planned_nights_win_over_the_date_window():
    """A leg's own nights are what the budget charges, so they set the total."""
    s = _extract(travelers=1, nights=2)["strategies"][1]
    assert s["nights"] == 2
    assert s["total_estimated_cost"] == "USD 80"          # 40 x 2 x 1


def test_stay_total_defined_without_dates():
    """No dates used to mean no total, so a nightly rate stood in for the trip."""
    s = extract_hotel_strategies_from_serpapi(
        FIXTURE, destination="Colombo", currency="USD", travelers=2, nights=4,
    )["strategies"][1]
    assert s["total_estimated_cost"] == "USD 320"         # 40 x 4 x 2 rooms


def test_star_class_reaches_the_app():
    s = _extract(travelers=2)["strategies"]
    assert [x["hotel_class"] for x in s] == [5, 3]


def test_tips_state_the_class_floor_not_an_average_rating():
    """The old tip averaged guest scores and called the mean a floor."""
    tips = _extract(travelers=3)["general_tips"]
    assert any("3-star class or above" in t for t in tips)
    assert not any("★ or higher" in t for t in tips)
    assert any("5 nights x 3 rooms for 3 travellers" in t for t in tips)


# ── The request Google actually receives, and what comes back ───────────────

class _FakeResponse:
    status_code = 200

    def __init__(self, payload):
        self._payload = payload
        self.headers = {}
        self.text = ""

    def json(self):
        return self._payload


class _FakeClient:
    """Captures the query params of the one GET SerpApiService makes."""

    def __init__(self, payload, sink):
        self._payload = payload
        self._sink = sink

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def get(self, url, params=None):
        self._sink.append(params or {})
        # A fresh object per request, as `resp.json()` gives — the search
        # filters the response dict in place, so a shared fixture would have
        # one test's filtering show up in the next one's result.
        return _FakeResponse(copy.deepcopy(self._payload))


def _search(monkeypatch, payload, **kwargs):
    import httpx
    from app.services.serpapi_service import SerpApiService

    sink = []
    monkeypatch.setattr(
        httpx, "AsyncClient", lambda *a, **kw: _FakeClient(payload, sink),
    )
    import asyncio
    result = asyncio.run(
        SerpApiService("test-key").search_hotels(destination="Colombo", **kwargs)
    )
    return sink[0], result


def test_class_floor_is_sent_to_google_as_hotel_class(monkeypatch):
    """Filtering happens in Google's index, not over one page of results.

    Filtering locally could only ever narrow the 20 properties Google chose to
    return for an unfiltered query — so a destination whose first page is all
    guesthouses yielded nothing, however many 3-star hotels it has.
    """
    params, _ = _search(monkeypatch, {"properties": []}, min_hotel_class=3)
    assert params["hotel_class"] == "3,4,5"


def test_no_class_filter_sends_no_parameter(monkeypatch):
    params, _ = _search(monkeypatch, {"properties": []}, min_hotel_class=0)
    assert "hotel_class" not in params


def test_unclassed_property_is_dropped_from_a_filtered_search(monkeypatch):
    """Belt and braces on Google's own filter.

    An unclassed guesthouse slipping through `hotel_class=3,4,5` would put back
    exactly the properties the filter exists to exclude.
    """
    payload = {"properties": [
        _prop("Fair View Hotel", nightly=40, hotel_class=3),
        _prop("Backpacker Rest", nightly=12),                       # unclassed
        _prop("Villa Two Star", nightly=20, hotel_class=2),         # below floor
    ]}
    _, result = _search(monkeypatch, payload, min_hotel_class=3)
    assert [p["name"] for p in result["properties"]] == ["Fair View Hotel"]


def test_unfiltered_search_keeps_unclassed_properties(monkeypatch):
    """The last rung of the fallback ladder must not filter anything out."""
    payload = {"properties": [
        _prop("Backpacker Rest", nightly=12),
        _prop("Villa Two Star", nightly=20, hotel_class=2),
    ]}
    _, result = _search(monkeypatch, payload, min_hotel_class=0)
    assert len(result["properties"]) == 2


def test_class_verification_reads_prose_when_integer_absent(monkeypatch):
    """A real 4-star hotel must survive even without `extracted_hotel_class`."""
    payload = {"properties": [
        _prop("Prose Only Hotel", nightly=90, hotel_class=4, extracted_class=False),
    ]}
    _, result = _search(monkeypatch, payload, min_hotel_class=3)
    assert [p["name"] for p in result["properties"]] == ["Prose Only Hotel"]


def test_guest_rating_and_star_class_are_separate_filters(monkeypatch):
    """The bug in one sentence.

    A guesthouse its guests rate 4.8 clears a 4.0 review floor; a 3-star hotel
    rated 3.9 does not. Only the class filter answers "3-star and above".
    """
    payload = {"properties": [
        _prop("Beloved Guesthouse", nightly=15, rating=4.8),         # unclassed
        _prop("Fair View Hotel", nightly=40, hotel_class=3, rating=3.9),
    ]}
    _, by_rating = _search(monkeypatch, payload, min_rating=4.0)
    _, by_class = _search(monkeypatch, payload, min_hotel_class=3)

    assert [p["name"] for p in by_rating["properties"]] == ["Beloved Guesthouse"]
    assert [p["name"] for p in by_class["properties"]] == ["Fair View Hotel"]


# ── The class ladder a real trip walks ──────────────────────────────────────

def _run_hotel_search(monkeypatch, *, budget, travelers, results_by_class, currency="USD"):
    """Drive `generate_hotel_strategies` with a scripted SerpApi.

    `results_by_class` maps a class floor to the properties Google returns for
    it, so a destination with no classed hotels is expressed as `{0: [...]}`.
    Returns (class floors tried in order, the strategies produced).
    """
    import asyncio
    from app.services import odyssey_ai_service

    tried = []

    class _ScriptedSerp:
        def __init__(self, key):
            pass

        async def search_hotels(self, *, min_hotel_class=0, **kw):
            tried.append(min_hotel_class)
            return {"properties": copy.deepcopy(results_by_class.get(min_hotel_class, []))}

    monkeypatch.setattr(odyssey_ai_service, "SerpApiService", _ScriptedSerp)

    result = asyncio.run(odyssey_ai_service.generate_hotel_strategies(
        destination="Colombo", days=6, budget=budget, currency=currency,
        travelers=travelers, hotel_check_in_date="2026-10-01",
        hotel_check_out_date="2026-10-06", api_key="", serpapi_key="k",
    ))
    return tried, result.get("strategies", [])


CLASSED = [_prop("Fair View Hotel", nightly=40, hotel_class=3)]
UNCLASSED = [_prop("Backpacker Rest", nightly=12)]


def test_a_tight_budget_still_starts_at_three_star(monkeypatch):
    """A small budget is a reason to sort by price, not to lower the class.

    The floor this replaced dropped to "no filter" below ~$35/night, so the
    traveller who asked for 3-star and above got guesthouses purely because
    their budget was modest.
    """
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={3: CLASSED},
    )
    assert tried == [3]
    assert strategies[0]["hotel_class"] == 3


def test_a_generous_budget_narrows_to_four_star(monkeypatch):
    tried, _ = _run_hotel_search(
        monkeypatch, budget=20_000, travelers=1,
        results_by_class={4: [_prop("Grand", nightly=300, hotel_class=4)]},
    )
    assert tried == [4]


def test_ladder_widens_only_when_a_search_comes_back_empty(monkeypatch):
    """The trip's floor, then no filter — and live Google prices to the last rung.

    The version this replaces retried once and then handed the whole stay to an
    LLM guess — which, for a town Google lists no classed hotel in, was every
    time. The 2-star rung that used to sit in the middle is gone: on exactly
    those towns it bought a third search to return the same empty list, and the
    unfiltered rung below now prefers classed properties itself.
    """
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={0: UNCLASSED},
    )
    assert tried == [3, 0]
    assert strategies[0]["name"] == "Backpacker Rest"


def test_ladder_stops_at_the_first_rung_that_has_hotels(monkeypatch):
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=20_000, travelers=1,
        results_by_class={4: [_prop("Grand", nightly=300, hotel_class=4)]},
    )
    assert tried == [4]
    assert strategies[0]["hotel_class"] == 4


def test_a_two_star_town_is_reached_without_its_own_search(monkeypatch):
    """What the removed 2-star rung used to deliver, one search cheaper."""
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={0: [_prop("Villa Two Star", nightly=20, hotel_class=2)]},
    )
    assert tried == [3, 0]
    assert strategies[0]["hotel_class"] == 2


def test_the_unfiltered_rung_drops_unclassed_hotels_when_enough_are_classed(monkeypatch):
    """A trip that could afford 3-star is not shown hostels beside hotels."""
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={0: [
            _prop("Villa Two Star", nightly=20, hotel_class=2),
            _prop("Hotel Three", nightly=30, hotel_class=3),
            _prop("Hotel Four", nightly=45, hotel_class=4),
            _prop("Backpacker Rest", nightly=12),
        ]},
    )
    assert tried == [3, 0]
    names = [s["name"] for s in strategies]
    assert "Backpacker Rest" not in names
    assert "Villa Two Star" in names


def test_the_unfiltered_rung_keeps_everything_in_a_town_with_few_classed_hotels(monkeypatch):
    """One lonely hotel card is worse than four real guesthouses."""
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={0: [
            _prop("Hotel Three", nightly=30, hotel_class=3),
            _prop("Backpacker Rest", nightly=12),
            _prop("Village Homestay", nightly=15),
        ]},
    )
    assert tried == [3, 0]
    assert "Backpacker Rest" in [s["name"] for s in strategies]


def test_party_size_reaches_the_stay_total_end_to_end(monkeypatch):
    """Four travellers, five nights, four rooms: 40 x 5 x 4.

    Stocked at every rung so the assertion is about party size alone and not
    about which class floor this particular budget happens to pick.
    """
    _, strategies = _run_hotel_search(
        monkeypatch, budget=4_000, travelers=4,
        results_by_class={4: CLASSED, 3: CLASSED},
    )
    assert strategies[0]["rooms"] == 4
    assert strategies[0]["nights"] == 5
    assert strategies[0]["total_estimated_cost"] == "USD 800"


def test_large_stay_total_survives_the_budget_parser():
    """Formatted totals cross back through `_extract_lowest_price` intact.

    "LKR 131,281" read as 131 would understate a stay by three orders of
    magnitude, so the separators the display format adds are checked against
    the parser the budget line uses.
    """
    from app.services.odyssey_ai_service import _extract_lowest_price

    big = {"properties": [_prop("Grand", nightly=13_128, hotel_class=4)]}
    s = extract_hotel_strategies_from_serpapi(
        big, destination="Colombo", currency="USD", travelers=4, nights=5,
    )["strategies"][0]

    assert s["total_estimated_cost"] == "USD 262,560"     # 13,128 x 5 x 4
    assert _extract_lowest_price(s["total_estimated_cost"]) == 262_560.0


# ── The Gemini fallback, held to the same arithmetic ────────────────────────

def test_gemini_fallback_stay_total_is_recomputed(monkeypatch):
    """The last path on which the two screens could still disagree.

    With no SerpApi results the hotels come from Gemini, and its
    `total_estimated_cost` is a number the model chose — for one room, or the
    party, or one night, unknowably — while the budget kept computing
    `nightly x nights x rooms`.
    """
    import asyncio
    from app.services import odyssey_ai_service

    async def _fake_gemini(prompt, api_key, **kw):
        return ('{"strategies": [{"name": "Lake View", "price_per_night": "USD 50",'
                ' "total_estimated_cost": "USD 250"}], "general_tips": [],'
                ' "best_areas": "Fort"}'), None

    monkeypatch.setattr(odyssey_ai_service, "_call_gemini", _fake_gemini)

    result = asyncio.run(odyssey_ai_service.generate_hotel_strategies(
        destination="Colombo", days=6, budget=4_000, currency="USD",
        travelers=3, hotel_check_in_date="2026-10-01",
        hotel_check_out_date="2026-10-06", api_key="k", serpapi_key="",
    ))
    s = result["strategies"][0]

    assert s["nights"] == 5 and s["rooms"] == 3
    # Gemini said 250 — one room. Three travellers need three.
    assert s["total_estimated_cost"] == "USD 750"        # 50 x 5 x 3


# ── The two screens, reconciled ─────────────────────────────────────────────
#
# The Budget Allocation's "Stay / Accommodation" line and the Stays tab's
# "Est. Total" are one calculation shown twice. These hold the two functions
# against each other so they cannot drift apart again.

def _stays_tab_totals(nightly_by_city, *, travelers, legs):
    """The Stays tab as the app renders it: strategies tagged per leg."""
    strategies = []
    for leg_index, leg in enumerate(legs):
        extracted = extract_hotel_strategies_from_serpapi(
            {"properties": [
                _prop(f"{leg['city']} Hotel {i}", nightly=rate, hotel_class=3)
                for i, rate in enumerate(nightly_by_city[leg["city"]])
            ]},
            destination=leg["city"], currency="USD",
            travelers=travelers, nights=leg["nights"],
        )
        for s in extracted["strategies"]:
            s["leg_index"] = leg_index
            s["city"] = leg["city"]
            strategies.append(s)
    return strategies


@pytest.mark.parametrize("travelers", [1, 2, 3, 4, 5, 6])
def test_budget_stay_line_equals_the_cheapest_stays_card(travelers):
    """One city, any party size: the figures must be identical.

    This is the screenshot the report came with — a single-destination trip
    where "Stay / Accommodation" in the budget and the Stays tab disagreed.
    """
    from app.services.odyssey_ai_service import _extract_lowest_price, required_stay_cost

    legs = [{"city": "Colombo", "nights": 5}]
    strategies = _stays_tab_totals({"Colombo": [40, 100]}, travelers=travelers, legs=legs)

    budget_line = required_stay_cost({"strategies": strategies}, legs, travelers)
    cheapest_card = min(strategies, key=lambda s: _extract_lowest_price(s["price_per_night"]))

    assert _extract_lowest_price(cheapest_card["total_estimated_cost"]) == budget_line


def test_multi_city_budget_stay_line_is_the_sum_of_each_leg_cheapest():
    """A four-city trip is four stays, each priced in its own city.

    The budget line is the sum, so no single card equals it — but each leg's
    cheapest card must be one of its addends, or the tab and the budget are
    telling the traveller different things again.
    """
    from app.services.odyssey_ai_service import _extract_lowest_price, required_stay_cost

    travelers = 3          # 3 rooms
    legs = [
        {"city": "Siem Reap", "nights": 3},
        {"city": "Phnom Penh", "nights": 2},
        {"city": "Sihanoukville", "nights": 4},
    ]
    strategies = _stays_tab_totals(
        {"Siem Reap": [30, 90], "Phnom Penh": [45, 120], "Sihanoukville": [25, 60]},
        travelers=travelers, legs=legs,
    )

    budget_line = required_stay_cost({"strategies": strategies}, legs, travelers)
    # 30x3x3 + 45x2x3 + 25x4x3 = 270 + 270 + 300
    assert budget_line == 840.0

    per_leg_cheapest = []
    for leg_index in range(len(legs)):
        group = [s for s in strategies if s["leg_index"] == leg_index]
        cheapest = min(group, key=lambda s: _extract_lowest_price(s["price_per_night"]))
        per_leg_cheapest.append(_extract_lowest_price(cheapest["total_estimated_cost"]))

    assert per_leg_cheapest == [270.0, 270.0, 300.0]
    assert sum(per_leg_cheapest) == budget_line


def test_a_leg_with_no_hotels_is_still_slept_in():
    """Pricing an unsearched leg at zero is what made a budget look sufficient."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Siem Reap", "nights": 3}, {"city": "Battambang", "nights": 2}]
    strategies = _stays_tab_totals({"Siem Reap": [30]}, travelers=2, legs=legs[:1])

    # 30x3x2 for the searched leg + 30x2x2 carried onto the one that found none.
    assert required_stay_cost({"strategies": strategies}, legs, 2) == 300.0


def test_no_hotels_at_all_costs_nothing_rather_than_guessing():
    from app.services.odyssey_ai_service import required_stay_cost

    assert required_stay_cost({}, [{"city": "Colombo", "nights": 5}], 2) == 0.0
    assert required_stay_cost({"strategies": []}, [], 2) == 0.0


# ── Budget Allocation tiers ────────────────────────────────────────────────
#
# Client report: "This rate never changes when shifting the budget level tabs."
# Stay / Accommodation showed an identical figure on Minimum, Recommended and
# Comfortable while transit, food and activities all moved, because every
# scenario was priced at `min(rates)`. Hotels are now ranked by price the same
# way flight strategies are.


def test_stay_cost_moves_with_the_budget_tier():
    """The reported bug: all three tabs quoted one stay figure."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Colombo", "nights": 5}]
    # Four hotels, which is what SerpApi returns per leg (max_hotels=4).
    strategies = _stays_tab_totals(
        {"Colombo": [40, 60, 95, 155]}, travelers=2, legs=legs,
    )

    minimum = required_stay_cost({"strategies": strategies}, legs, 2, "minimum")
    recommended = required_stay_cost({"strategies": strategies}, legs, 2, "recommended")
    comfortable = required_stay_cost({"strategies": strategies}, legs, 2, "comfortable")

    # 5 nights x 2 rooms, at the cheapest / median / dearest nightly rate.
    assert minimum == 400.0
    assert recommended == 950.0
    assert comfortable == 1550.0
    assert minimum < recommended < comfortable


def test_stay_cost_default_tier_is_the_cheapest_room():
    """The feasibility floor and every existing caller depend on this default."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Colombo", "nights": 5}]
    strategies = _stays_tab_totals(
        {"Colombo": [40, 60, 95, 155]}, travelers=2, legs=legs,
    )

    assert required_stay_cost({"strategies": strategies}, legs, 2) == 400.0
    assert required_stay_cost(
        {"strategies": strategies}, legs, 2,
    ) == required_stay_cost({"strategies": strategies}, legs, 2, "minimum")


def test_single_hotel_leg_prices_every_tier_the_same():
    """One room to choose from is one price — honest, not a repeat of the bug."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Jaffna", "nights": 2}]
    strategies = _stays_tab_totals({"Jaffna": [50]}, travelers=2, legs=legs)

    tiers = {
        required_stay_cost({"strategies": strategies}, legs, 2, t)
        for t in ("minimum", "recommended", "comfortable")
    }
    assert tiers == {200.0}


def test_unsearched_leg_tracks_the_tier_it_is_carried_onto():
    """A leg with no hotels borrows the trip's rates, ranked by the same tier."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Siem Reap", "nights": 3}, {"city": "Battambang", "nights": 2}]
    strategies = _stays_tab_totals(
        {"Siem Reap": [30, 90]}, travelers=2, legs=legs[:1],
    )

    # Comfortable: 90x3x2 for the searched leg + 90x2x2 carried onto the empty one.
    assert required_stay_cost(
        {"strategies": strategies}, legs, 2, "comfortable",
    ) == 900.0
    # Minimum ranks the same way: 30x3x2 + 30x2x2.
    assert required_stay_cost({"strategies": strategies}, legs, 2) == 300.0


# ── The star floor: under the budget, not under the Stays list ──────────────
#
# The class ladder searches 3-star+ first and falls back to an unfiltered rung
# (`_HOTEL_CLASS_FALLBACKS`), so in a town where Google classifies little, 2-star
# properties reach the list. They belong there — a traveller may want one — but
# a 2-star rate was setting the budget's floor. Seen on a 14-day Colombo plan,
# whose Minimum tier sat at 46,396 against the 50,926 its 3-star rooms cost.

def _leg_strategies(rates_and_classes, *, city="Colombo", nights=5, travelers=2,
                    leg_index=0):
    """One leg's Stays cards, each with its own nightly rate and star class."""
    extracted = extract_hotel_strategies_from_serpapi(
        {"properties": [
            _prop(f"{city} Hotel {i}", nightly=rate, hotel_class=cls)
            for i, (rate, cls) in enumerate(rates_and_classes)
        ]},
        destination=city, currency="USD", travelers=travelers, nights=nights,
    )
    for s in extracted["strategies"]:
        s["leg_index"] = leg_index
        s["city"] = city
    return extracted["strategies"]


def test_a_two_star_rate_never_sets_the_budget_floor():
    """The cheap guesthouse stays on the list; it just stops pricing the trip."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Colombo", "nights": 5}]
    strategies = _leg_strategies([(20, 2), (40, 3), (100, 4)])

    # The 2-star card is still there for the traveller to pick.
    assert 2 in [s["hotel_class"] for s in strategies]
    # ...but Minimum is the cheapest *3-star+* room: 40 x 5 x 2, not 20 x 5 x 2.
    assert required_stay_cost({"strategies": strategies}, legs, 2, "minimum") == 400.0


def test_a_leg_with_only_low_class_hotels_is_still_priced():
    """A town where nothing clears 3-star must not price its nights at zero."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Battambang", "nights": 4}]
    strategies = _leg_strategies([(20, 2), (35, 2)], city="Battambang", nights=4)

    # No classed room exists, so the floor gives way rather than the leg.
    assert required_stay_cost({"strategies": strategies}, legs, 2, "minimum") == 160.0


def test_unclassed_hotels_price_exactly_as_before():
    """The Gemini estimate path writes no `hotel_class` at all.

    Its strategies carry no class, so the classed bucket is empty on every leg
    and the old arithmetic has to survive untouched.
    """
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Colombo", "nights": 5}]
    strategies = [
        {"leg_index": 0, "city": "Colombo", "price_per_night": "USD 40", "nights": 5},
        {"leg_index": 0, "city": "Colombo", "price_per_night": "USD 100", "nights": 5},
    ]
    assert "hotel_class" not in strategies[0]
    assert required_stay_cost({"strategies": strategies}, legs, 2, "minimum") == 400.0


def test_the_star_floor_applies_per_leg_not_across_the_trip():
    """One city's 3-star rooms must not rescue another city that has none."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Colombo", "nights": 3}, {"city": "Battambang", "nights": 2}]
    strategies = (
        _leg_strategies([(20, 2), (60, 3)], city="Colombo", nights=3, leg_index=0)
        + _leg_strategies([(25, 2), (30, 2)], city="Battambang", nights=2, leg_index=1)
    )

    # Colombo takes its 3-star (60x3x2); Battambang has none, so it keeps its
    # own cheapest (25x2x2) rather than borrowing Colombo's floor.
    assert required_stay_cost({"strategies": strategies}, legs, 2, "minimum") == 460.0


def test_the_note_claims_a_star_floor_only_when_every_leg_met_it():
    """A note is worth having only if the traveller can rely on it."""
    from app.services.odyssey_ai_service import stay_priced_at_star_floor

    legs = [{"city": "Colombo", "nights": 3}, {"city": "Battambang", "nights": 2}]

    both = (
        _leg_strategies([(60, 3)], city="Colombo", nights=3, leg_index=0)
        + _leg_strategies([(30, 4)], city="Battambang", nights=2, leg_index=1)
    )
    assert stay_priced_at_star_floor({"strategies": both}, legs) is True

    one_short = (
        _leg_strategies([(60, 3)], city="Colombo", nights=3, leg_index=0)
        + _leg_strategies([(30, 2)], city="Battambang", nights=2, leg_index=1)
    )
    assert stay_priced_at_star_floor({"strategies": one_short}, legs) is False

    # The estimate path, which writes no class at all.
    unclassed = [{"leg_index": 0, "city": "Colombo", "price_per_night": "USD 40"}]
    assert stay_priced_at_star_floor({"strategies": unclassed}, legs) is False


# ── The budget note: the client's wording, only where it is true ────────────
#
# Requested by the client, who supplied both sentences. "Based on Best Value
# Direct Flight" holds on 2 of the 30 live routes held in cache, so the note is
# derived from the fare the budget actually priced rather than asserted.

def test_the_note_uses_the_clients_wording_for_a_direct_flight():
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="direct", no_airfare=False,
    )
    assert n["transit"] == "Based on Best Value Direct Flight"
    assert n["stay"] == (
        "Based on the mid-priced 3-star+ room. "
        "Individual rooms assumed for each pax."
    )
    assert n["summary"] == (
        "Mid-priced 3-star+ room, 1 per person · best value direct flight"
    )


def test_the_note_says_cheapest_on_the_tier_that_prices_the_cheapest_room():
    """The tab the card now opens on, and the one the client's rule describes.

    The note used to be written for Recommended and shown on every tab, so the
    Minimum tab — the cheapest room and the cheapest fare — claimed to be
    priced on "best value" ones.
    """
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="direct", no_airfare=False,
        tier="minimum",
    )
    assert n["stay"] == (
        "Based on the lowest-priced 3-star+ room. "
        "Individual rooms assumed for each pax."
    )
    assert n["transit"] == "Based on the lowest-priced direct flight."
    assert n["summary"] == (
        "Cheapest 3-star+ room, 1 per person · lowest-priced direct flight"
    )


def test_the_dearest_tier_never_calls_its_room_the_cheapest():
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=1, at_star_floor=True, flight_basis="connecting", no_airfare=False,
        tier="comfortable",
    )
    assert "Cheapest" not in n["summary"]
    assert n["stay"] == "Based on the highest-priced 3-star+ room."


def test_the_note_says_so_when_the_route_has_no_direct_flight():
    """28 of 30 live routes carry no non-stop; the note must not claim one."""
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="connecting", no_airfare=False,
    )
    assert "Direct Flight" not in n["transit"]
    assert n["transit"] == (
        "Based on the best value flight. No direct flight is offered on this route."
    )
    assert "direct" not in n["summary"]


def test_the_note_drops_the_flight_line_when_nothing_flies():
    """`budget_advisory` already carries the ground-transport wording in full."""
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="connecting", no_airfare=True,
    )
    assert "transit" not in n
    assert n["summary"].endswith("ground transport only")


def test_the_note_drops_the_rooms_clause_for_a_solo_traveller():
    """One traveller, one room: "individual rooms" is noise, not information."""
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=1, at_star_floor=False, flight_basis="connecting", no_airfare=False,
    )
    assert n["stay"] == "Based on the mid-priced room."
    assert "per person" not in n["summary"]
    assert n["summary"] == "Mid-priced room · best value flight"


def test_the_note_claims_three_star_only_when_the_floor_held():
    from app.services.odyssey_ai_service import _budget_notes

    held = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="connecting", no_airfare=False,
    )
    gave_way = _budget_notes(
        rooms=2, at_star_floor=False, flight_basis="connecting", no_airfare=False,
    )
    assert "3-star+" in held["summary"]
    assert "3-star" not in gave_way["summary"]
    assert gave_way["summary"].startswith("Mid-priced room, 1 per person")


def test_the_note_says_estimated_when_no_live_fare_was_found():
    """An estimate is a different claim from a price, and reads as one."""
    from app.services.odyssey_ai_service import _budget_notes

    n = _budget_notes(
        rooms=2, at_star_floor=True, flight_basis="estimated", no_airfare=False,
    )
    assert n["transit"] == (
        "Based on an estimated fare — no live price was available for this route."
    )
    assert n["summary"].endswith("· estimated fare")


# ── A leg nobody sleeps on ──────────────────────────────────────────────────
#
# A 14-day Peru plan closed "Paracas d12-13 -> Lima d14": the traveller lands
# in Lima and flies home the same day. Lima was searched anyway and shown four
# hotels priced for a night that is not in the trip, and the search was bought.

def test_a_leg_with_no_nights_is_not_searched_or_shown(monkeypatch):
    import asyncio
    from app.services import odyssey_ai_service as O

    searched = []

    async def _fake(*, destination, **kw):
        searched.append(destination)
        return {"strategies": [{
            "rank": 1, "name": f"{destination} Hotel", "price_per_night": "USD 100",
            "nights": 1, "rooms": 1, "hotel_class": 4,
            "total_estimated_cost": "USD 100",
        }], "general_tips": [], "best_areas": destination}

    monkeypatch.setattr(O, "generate_hotel_strategies", _fake)

    legs = [
        {"city": "Cusco", "nights": 4, "start_day": 1, "end_day": 4},
        {"city": "Paracas", "nights": 2, "start_day": 5, "end_day": 6},
        {"city": "Lima", "nights": 0, "start_day": 7, "end_day": 7},
    ]
    result = asyncio.run(O.generate_hotel_strategies_for_legs(
        legs=legs, days=7, budget=5000, currency="USD", travelers=2,
        hotel_check_in_date="2027-05-08", hotel_check_out_date="2027-05-14",
        api_key="k", serpapi_key="s", geo=None,
    ))

    assert searched == ["Cusco", "Paracas"], "the 0-night leg cost a search"
    cities = {s["city"] for s in result["strategies"]}
    assert cities == {"Cusco", "Paracas"}


def test_the_leg_index_still_points_at_the_original_leg(monkeypatch):
    """Skipping a leg must not renumber the ones that remain — the budget, the
    Stays tab and `_reprice_stays` all group by `leg_index`."""
    import asyncio
    from app.services import odyssey_ai_service as O

    async def _fake(*, destination, **kw):
        return {"strategies": [{
            "rank": 1, "name": f"{destination} Hotel", "price_per_night": "USD 100",
            "nights": 1, "rooms": 1, "hotel_class": 4,
            "total_estimated_cost": "USD 100",
        }], "general_tips": [], "best_areas": destination}

    monkeypatch.setattr(O, "generate_hotel_strategies", _fake)

    legs = [
        {"city": "Lima", "nights": 0, "start_day": 1, "end_day": 1},      # skipped
        {"city": "Cusco", "nights": 4, "start_day": 2, "end_day": 5},     # index 1
        {"city": "Puno", "nights": 2, "start_day": 6, "end_day": 7},      # index 2
    ]
    result = asyncio.run(O.generate_hotel_strategies_for_legs(
        legs=legs, days=7, budget=5000, currency="USD", travelers=2,
        hotel_check_in_date="2027-05-08", hotel_check_out_date="2027-05-14",
        api_key="k", serpapi_key="s", geo=None,
    ))
    by_city = {s["city"]: s["leg_index"] for s in result["strategies"]}
    assert by_city == {"Cusco": 1, "Puno": 2}


def test_a_trip_where_nobody_sleeps_anywhere_still_searches(monkeypatch):
    """A guard, not a rule: a day trip must not come back with no hotels at all
    because every leg was filtered out."""
    import asyncio
    from app.services import odyssey_ai_service as O

    async def _fake(*, destination, **kw):
        return {"strategies": [{
            "rank": 1, "name": "X", "price_per_night": "USD 100", "nights": 1,
            "rooms": 1, "hotel_class": 4, "total_estimated_cost": "USD 100",
        }], "general_tips": [], "best_areas": destination}

    monkeypatch.setattr(O, "generate_hotel_strategies", _fake)
    result = asyncio.run(O.generate_hotel_strategies_for_legs(
        legs=[{"city": "Lima", "nights": 0, "start_day": 1, "end_day": 1}],
        days=1, budget=500, currency="USD", travelers=1,
        hotel_check_in_date="2027-05-08", hotel_check_out_date="2027-05-09",
        api_key="k", serpapi_key="s", geo=None,
    ))
    assert result.get("strategies")
