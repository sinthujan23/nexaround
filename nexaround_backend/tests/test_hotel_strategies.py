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
    (1, 1), (2, 1),        # two to a room
    (3, 2), (4, 2),
    (5, 3), (6, 3),
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
    """Three travellers need two rooms, and the quote has to say so.

    Google's own `total_rate` for these dates is $200 — one room. The party
    pays twice that, which is also what the budget allocation charges them.
    """
    solo = _extract(travelers=1)["strategies"][1]
    trio = _extract(travelers=3)["strategies"][1]

    assert solo["rooms"] == 1 and trio["rooms"] == 2
    assert solo["total_estimated_cost"] == "USD 200"     # 40 x 5 x 1
    assert trio["total_estimated_cost"] == "USD 400"     # 40 x 5 x 2


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

    assert tab_total == budget_stay_line == 400.0


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
    assert s["total_estimated_cost"] == "USD 160"         # 40 x 4 x 1 room


def test_star_class_reaches_the_app():
    s = _extract(travelers=2)["strategies"]
    assert [x["hotel_class"] for x in s] == [5, 3]


def test_tips_state_the_class_floor_not_an_average_rating():
    """The old tip averaged guest scores and called the mean a floor."""
    tips = _extract(travelers=3)["general_tips"]
    assert any("3-star class or above" in t for t in tips)
    assert not any("★ or higher" in t for t in tips)
    assert any("5 nights x 2 rooms for 3 travellers" in t for t in tips)


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
    """3 -> 2 -> unfiltered, and live Google prices are kept to the last rung.

    The version this replaces retried once and then handed the whole stay to an
    LLM guess — which, for a town Google lists no classed hotel in, was every
    time.
    """
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={0: UNCLASSED},
    )
    assert tried == [3, 2, 0]
    assert strategies[0]["name"] == "Backpacker Rest"


def test_ladder_stops_at_the_first_rung_that_has_hotels(monkeypatch):
    tried, strategies = _run_hotel_search(
        monkeypatch, budget=50_000, currency="LKR", travelers=1,
        results_by_class={2: [_prop("Villa Two Star", nightly=20, hotel_class=2)]},
    )
    assert tried == [3, 2]
    assert strategies[0]["hotel_class"] == 2


def test_party_size_reaches_the_stay_total_end_to_end(monkeypatch):
    """Four travellers, five nights, two rooms: 40 x 5 x 2.

    Stocked at every rung so the assertion is about party size alone and not
    about which class floor this particular budget happens to pick.
    """
    _, strategies = _run_hotel_search(
        monkeypatch, budget=4_000, travelers=4,
        results_by_class={4: CLASSED, 3: CLASSED},
    )
    assert strategies[0]["rooms"] == 2
    assert strategies[0]["nights"] == 5
    assert strategies[0]["total_estimated_cost"] == "USD 400"


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

    assert s["total_estimated_cost"] == "USD 131,280"     # 13,128 x 5 x 2
    assert _extract_lowest_price(s["total_estimated_cost"]) == 131_280.0


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

    assert s["nights"] == 5 and s["rooms"] == 2
    # Gemini said 250 — one room. Three travellers need two.
    assert s["total_estimated_cost"] == "USD 500"        # 50 x 5 x 2


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

    travelers = 3          # 2 rooms
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
    # 30x3x2 + 45x2x2 + 25x4x2 = 180 + 180 + 200
    assert budget_line == 560.0

    per_leg_cheapest = []
    for leg_index in range(len(legs)):
        group = [s for s in strategies if s["leg_index"] == leg_index]
        cheapest = min(group, key=lambda s: _extract_lowest_price(s["price_per_night"]))
        per_leg_cheapest.append(_extract_lowest_price(cheapest["total_estimated_cost"]))

    assert per_leg_cheapest == [180.0, 180.0, 200.0]
    assert sum(per_leg_cheapest) == budget_line


def test_a_leg_with_no_hotels_is_still_slept_in():
    """Pricing an unsearched leg at zero is what made a budget look sufficient."""
    from app.services.odyssey_ai_service import required_stay_cost

    legs = [{"city": "Siem Reap", "nights": 3}, {"city": "Battambang", "nights": 2}]
    strategies = _stays_tab_totals({"Siem Reap": [30]}, travelers=2, legs=legs[:1])

    # 30x3x1 for the searched leg + 30x2x1 carried onto the one that found none.
    assert required_stay_cost({"strategies": strategies}, legs, 2) == 150.0


def test_no_hotels_at_all_costs_nothing_rather_than_guessing():
    from app.services.odyssey_ai_service import required_stay_cost

    assert required_stay_cost({}, [{"city": "Colombo", "nights": 5}], 2) == 0.0
    assert required_stay_cost({"strategies": []}, [], 2) == 0.0
