"""Go City: a sightseeing-pass row for its big cities (user, 2026-09-30).

What these pin:
- the link is the city's pass page on Go City, credited to us the way
  Travelpayouts' Links API credits Go City (campaign 62, promo 1942);
- a row only for a Go City city the plan spends at least two days in, and only
  in that city's own country; at most two;
- the row names no price and promises no pass type (neither can be read);
- shadow records and changes nothing; off asks nothing.
"""
import time

import pytest

from app.services.providers import config, enrich, gocity

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


def test_the_link_opens_the_citys_pass_prices_credited_to_us():
    assert gocity.booking_link("new-york", marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=62&marker=781739&p=1942&trs=577812"
        "&u=https%3A%2F%2Fgocity.com%2Fen%2Fnew-york%2Fpasses"
    )
    assert gocity.booking_link("rome", marker="781739", project_id="") == "https://gocity.com/en/rome/passes"


@pytest.mark.parametrize("city, country, slug", [
    ("New York", "US", "new-york"),
    ("New York City", "US", "new-york"),
    ("Honolulu", "US", "oahu"),
    ("Praha", "CZ", "prague"),
    ("Göteborg", "SE", "gothenburg"),
    ("Cancún", "MX", "cancun"),
    ("Hong Kong", "", "hong-kong"),
    ("Paris", "US", ""),        # Paris, Texas
    ("Sydney", "CA", ""),       # Sydney, Nova Scotia
    ("Colombo", "LK", ""),
    ("Oslo", "NO", ""),
])
def test_cities_are_recognised_by_their_plan_names(city, country, slug):
    assert gocity.destination_for(city, country) == slug


def test_only_stays_of_two_days_or_more_and_at_most_two_cities():
    legs = [
        {"city": "London", "country": "GB", "start_day": 1, "end_day": 3},
        {"city": "Paris", "country": "FR", "start_day": 4, "end_day": 4},     # one day: no pass
        {"city": "Amsterdam", "country": "NL", "start_day": 5, "end_day": 6},
        {"city": "Bruges", "country": "BE", "start_day": 7, "end_day": 8},    # no Go City
        {"city": "Dublin", "country": "IE", "start_day": 9, "end_day": 10},   # third: over the limit
    ]
    assert gocity.cities_to_link(legs) == ["london", "amsterdam"]


def test_a_city_visited_twice_adds_its_days_up():
    legs = [
        {"city": "Paris", "country": "FR", "start_day": 1, "end_day": 1},
        {"city": "Lyon", "country": "FR", "start_day": 2, "end_day": 3},
        {"city": "Paris", "country": "FR", "start_day": 4, "end_day": 4},
    ]
    assert gocity.cities_to_link(legs) == ["paris"]
    assert gocity.cities_to_link(legs[:1]) == []


def test_the_row_promises_no_price_and_no_one_pass_type():
    row = gocity.plan_item("prague", "https://tp.media/r?x")
    assert row["item"] == "Go City pass for Prague: one pass, many top attractions"
    assert "depending on the city" in row["reason"]
    assert not any(ch.isdigit() for ch in row["item"] + row["reason"])
    assert row["label"] in ("BOOK NOW", "BOOK AFTER VISA", "BOOK CLOSER TO TRAVEL", "CAN WAIT")
    assert row["url"] == "https://tp.media/r?x"


def test_go_city_links_are_recognised_and_others_are_not():
    assert gocity.is_gocity_link(gocity.booking_link("rome", marker="1", project_id="2"))
    assert gocity.is_gocity_link("https://gocity.com/en/rome/passes")
    assert not gocity.is_gocity_link("https://tp.media/r?campaign_id=137&p=4110&u=x")   # Klook
    assert not gocity.is_gocity_link("https://notgocity.com/")


# ── Applied to a plan ────────────────────────────────────────────────────────

_LEGS = [
    {"city": "New York", "country": "US", "start_day": 1, "end_day": 4},
    {"city": "Niagara Falls", "country": "US", "start_day": 5, "end_day": 5},
]


def _pending():
    return enrich.Pending(modes={"gocity": "live"}, legs=_LEGS, country="United States")


def test_live_adds_the_row_and_keeps_the_rest():
    meta = {"booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "reason": "", "url": "https://h"}]}
    entry = enrich._apply_gocity(meta, _pending(), live=True, marker="781739", project_id="577812")
    assert [r["item"] for r in meta["booking_plan"]] == [
        "Hotel", "Go City pass for New York: one pass, many top attractions",
    ]
    assert entry == {"mode": "live", "cities": ["new-york"], "rows": 1}
    # A second pass replaces its row rather than doubling it.
    enrich._apply_gocity(meta, _pending(), live=True, marker="781739", project_id="577812")
    assert len(meta["booking_plan"]) == 2


def test_shadow_records_the_link_and_changes_nothing():
    meta = {"booking_plan": []}
    entry = enrich._apply_gocity(meta, _pending(), live=False, marker="781739", project_id="577812")
    assert meta == {"booking_plan": []}
    assert entry["links"]["new-york"].startswith("https://tp.media/r?campaign_id=62")


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def test_a_plan_with_no_go_city_city_gets_no_row(world, monkeypatch):
    # The e2e world is Delhi and Agra: no Go City there.
    _switches(monkeypatch, gocity="live")
    _, meta, _ = e2e.run(world)
    assert not [r for r in meta["booking_plan"] if r["item"].startswith("Go City")]
    assert meta["provider_audit"]["gocity"] == {"mode": "live", "cities": [], "rows": 0}


def test_off_asks_nothing(world):
    _, meta, _ = e2e.run(world)
    assert "gocity" not in meta.get("provider_audit", {})
