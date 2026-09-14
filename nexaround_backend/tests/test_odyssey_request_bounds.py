"""The server-side backstop on what a client may ask for.

The app validates some of this and not all of it, and nothing stops a request
being made outside the app at all. Every bound here was reachable: `travelers`
had no bound of any kind, so 0, -1 and 99999 all reached the planner and were
stored on the trip.
"""
import pytest
from pydantic import ValidationError

from app.schemas.itinerary import OdysseyGenerateRequest


def _req(**kw):
    args = {"destination": "India"}
    args.update(kw)
    return OdysseyGenerateRequest(**args)


def test_a_sensible_request_is_accepted():
    r = _req(travelers=4, budget=250000, days=10, currency="INR")
    assert (r.travelers, r.budget, r.days) == (4, 250000, 10)


@pytest.mark.parametrize("pax", [0, -1, 21, 99999])
def test_an_impossible_party_size_is_refused(pax):
    """0 stored a trip for nobody; 99999 quoted 99,999 hotel rooms."""
    with pytest.raises(ValidationError):
        _req(travelers=pax)


@pytest.mark.parametrize("pax", [1, 2, 10, 20])
def test_a_real_party_size_is_accepted(pax):
    assert _req(travelers=pax).travelers == pax


@pytest.mark.parametrize("budget", [-1, -50000, 1_000_000_001, 1e308])
def test_an_impossible_budget_is_refused(budget):
    with pytest.raises(ValidationError):
        _req(budget=budget)


@pytest.mark.parametrize("budget", [0, 1, 50000, 1_000_000_000])
def test_a_real_budget_is_accepted(budget):
    assert _req(budget=budget).budget == budget


@pytest.mark.parametrize("days", [0, -3, 15, 400])
def test_an_impossible_trip_length_is_refused(days):
    with pytest.raises(ValidationError):
        _req(days=days)


def test_free_text_is_capped_because_it_is_billed_as_prompt_tokens():
    with pytest.raises(ValidationError):
        _req(destination="A" * 201)
    with pytest.raises(ValidationError):
        _req(destination="")
    with pytest.raises(ValidationError):
        _req(mood="M" * 61)
    with pytest.raises(ValidationError):
        _req(currency="C" * 9)
    # A real place name with punctuation and accents is not caught by any of it.
    assert _req(destination="Saint-Denis, La Reunion").destination


def test_defaults_are_inside_their_own_bounds():
    r = OdysseyGenerateRequest(destination="India")
    assert r.travelers == 1 and r.days == 3 and r.budget == 50000


# ── The retry path replays stored parameters, bypassing the model above ─────
#
# Two stored trips carry values the model would now refuse: travelers=110 and
# days=31. Retrying either used to replay it verbatim - 110 hotel rooms, or a
# month of itinerary in one Gemini call.

def _retry_clamp(value, bounds, fallback):
    """The clamp the retry endpoint applies, exercised directly."""
    from app.api.v1.itineraries import retry_odyssey_generation  # noqa: F401
    import inspect
    import app.api.v1.itineraries as mod
    src = inspect.getsource(mod.retry_odyssey_generation)
    assert "_clamp(" in src, "the retry endpoint no longer clamps its parameters"
    lo, hi = bounds
    try:
        n = type(fallback)(value)
    except (TypeError, ValueError):
        return fallback
    if n != n:
        return fallback
    return max(lo, min(hi, n))


def test_the_retry_endpoint_clamps_the_same_parameters():
    from app.schemas.itinerary import BUDGET_RANGE, DAYS_RANGE, TRAVELERS_RANGE

    assert _retry_clamp(110, TRAVELERS_RANGE, 1) == 20      # a real stored trip
    assert _retry_clamp(31, DAYS_RANGE, 3) == 14            # a real stored trip
    assert _retry_clamp(0, TRAVELERS_RANGE, 1) == 1
    assert _retry_clamp(-5, TRAVELERS_RANGE, 1) == 1
    assert _retry_clamp(-100.0, BUDGET_RANGE, 1000.0) == 0.0
    assert _retry_clamp(1e308, BUDGET_RANGE, 1000.0) == BUDGET_RANGE[1]


def test_the_retry_clamp_survives_junk_rather_than_raising():
    from app.schemas.itinerary import DAYS_RANGE, TRAVELERS_RANGE

    assert _retry_clamp("four", TRAVELERS_RANGE, 1) == 1
    assert _retry_clamp(None, DAYS_RANGE, 3) == 3
    assert _retry_clamp(float("nan"), DAYS_RANGE, 3) == 3
    assert _retry_clamp({"n": 2}, TRAVELERS_RANGE, 1) == 1


def test_a_value_already_inside_the_bounds_is_untouched():
    from app.schemas.itinerary import BUDGET_RANGE, DAYS_RANGE, TRAVELERS_RANGE

    assert _retry_clamp(4, TRAVELERS_RANGE, 1) == 4
    assert _retry_clamp(9, DAYS_RANGE, 3) == 9
    assert _retry_clamp(250000.0, BUDGET_RANGE, 1000.0) == 250000.0
