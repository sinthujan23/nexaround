"""Aviasales: a "Book on Aviasales" link on each flight option (user, 2026-09-29).

What these pin:
- the search paths are the ones verified in a browser on 2026-09-29, for every
  shape a plan flies (one way, round trip, into one city and home from
  another), with the travellers and the cabin;
- the option's Google Flights link and provider stay as they are: installed
  app builds rebuild an "Aviasales" flight link into a bare, untracked search;
- live mode also points the Booking Plan's flight row at Aviasales and names
  it there; shadow and off change nothing.
"""
import datetime as dt
import time
import urllib.parse

import pytest

from app.services.providers import aviasales, config, enrich

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)


@pytest.fixture(autouse=True)
def _before_the_trips(monkeypatch):
    """Every date below is still ahead, whatever day the suite runs on."""
    monkeypatch.setattr(aviasales, "_today", lambda: dt.date(2026, 9, 29))


# ── The search path ──────────────────────────────────────────────────────────

@pytest.mark.parametrize("legs, adults, cabin, path", [
    ([("DXB", "BCN", "2026-11-15")], 1, "Economy", "DXB1511BCN1"),
    ([("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-24")], 2, "", "DXB1511BCN24112"),
    ([("CMB", "MAD", "2026-10-11"), ("BCN", "CMB", "2026-10-17")], 1, "Economy", "CMB1110MAD-BCN1710CMB1"),
    ([("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-24")], 2, "Business", "DXB1511BCN2411c2"),
    ([("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-24")], 2, "Premium economy", "DXB1511BCN2411w2"),
    ([("DXB", "BCN", "2026-11-15")], 2, "First", "DXB1511BCNf2"),
    ([("CMB", "MAD", "2026-10-11"), ("BCN", "CMB", "2026-10-17")], 2, "Business", "CMB1110MAD-BCN1710CMBc2"),
])
def test_the_paths_verified_in_a_browser(legs, adults, cabin, path):
    assert aviasales.search_path(legs, adults=adults, travel_class=cabin) == path


def test_a_city_searched_across_its_airports_opens_on_the_first():
    legs = [("DWC,DXB", "BCN", "2026-11-15")]
    assert aviasales.search_path(legs) == "DWC1511BCN1"


def test_a_party_bigger_than_aviasales_takes_is_capped():
    assert aviasales.search_path([("DXB", "BCN", "2026-11-15")], adults=12).endswith("BCN9")


@pytest.mark.parametrize("legs", [
    [],
    [("DXB", "", "2026-11-15")],
    [("Dubai", "BCN", "2026-11-15")],
    [("DXB", "DXB", "2026-11-15")],
    [("DXB", "BCN", "2026-09-20")],                                   # already flown
    [("DXB", "BCN", "")],
    [("DXB", "BCN", "2026-11-15"), ("BCN", "DXB", "2026-11-10")],     # home before leaving
    [("DXB", "BCN", "2026-11-15"), ("BCN", "MAD", "2026-11-18"), ("MAD", "DXB", "2026-11-24")],
])
def test_what_cannot_be_searched_gets_no_link(legs):
    assert aviasales.search_path(legs) == ""


# ── Reading an option's legs (shapes taken from real plans, 2026-09-29) ─────

def test_an_open_jaw_option_reads_both_tickets():
    option = {
        "trip_type": "open_jaw",
        "outbound": {"origin": "CMB", "destination": "MAD", "date": "2026-10-11"},
        "return": {"origin": "BCN", "destination": "CMB", "date": "2026-10-17"},
    }
    assert aviasales.legs_for(option, {}) == [
        ("CMB", "MAD", "2026-10-11"), ("BCN", "CMB", "2026-10-17"),
    ]


def test_a_round_trip_with_no_return_block_comes_home_from_the_gateway():
    """Plan 27cc792d: the Minimum tier lists only its outbound."""
    option = {
        "trip_type": "round_trip", "return_date": "2026-10-14",
        "outbound": {"origin": "CMB", "destination": "BUD", "date": "2026-10-01"},
    }
    flights = {"departure_airport": {"iata": "BUD"}, "origin_airport": "CMB"}
    assert aviasales.legs_for(option, flights) == [
        ("CMB", "BUD", "2026-10-01"), ("BUD", "CMB", "2026-10-14"),
    ]


def test_an_older_option_falls_back_to_its_route_text():
    option = {
        "trip_type": "round_trip", "route": "CMB → KUL", "return_route": "KUL → CMB",
        "outbound_date": "2026-10-26", "return_date": "2026-10-28",
    }
    assert aviasales.legs_for(option, {}) == [
        ("CMB", "KUL", "2026-10-26"), ("KUL", "CMB", "2026-10-28"),
    ]


def test_a_one_way_option_is_one_leg():
    option = {"trip_type": "one_way", "outbound": {"origin": "CMB", "destination": "BCN", "date": "2026-10-07"}}
    assert aviasales.legs_for(option, {}) == [("CMB", "BCN", "2026-10-07")]


def test_a_return_fare_with_no_date_home_is_not_searched_as_one_way():
    option = {"trip_type": "round_trip", "outbound": {"origin": "CMB", "destination": "BUD", "date": "2026-10-01"}}
    assert aviasales.legs_for(option, {}) == []


@pytest.mark.parametrize("legs, text", [
    ([("CMB", "BUD", "")], "CMB → BUD"),
    ([("CMB", "BUD", ""), ("BUD", "CMB", "")], "CMB → BUD and back"),
    ([("CMB", "MAD", ""), ("BCN", "CMB", "")], "CMB → MAD, BCN → CMB"),
])
def test_the_trip_reads_plainly(legs, text):
    assert aviasales.trip_text(legs) == text


# ── The link ─────────────────────────────────────────────────────────────────

def test_the_link_is_credited_to_us_through_travelpayouts():
    link = aviasales.booking_link("CMB1110MAD-BCN1710CMB1", marker="781739", project_id="577812")
    assert link == (
        "https://tp.media/r?marker=781739&trs=577812&p=4114"
        "&u=https%3A%2F%2Fwww.aviasales.com%2Fsearch%2FCMB1110MAD-BCN1710CMB1"
    )


def test_without_both_ids_the_link_still_opens_the_search():
    assert aviasales.booking_link("DXB1511BCN1", marker="781739", project_id="") == (
        "https://www.aviasales.com/search/DXB1511BCN1"
    )


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


def _search(link: str) -> str:
    page = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)["u"][0]
    return page.removeprefix(aviasales.SEARCH_PAGE)


def test_live_puts_a_link_on_every_option_and_keeps_googles(world, monkeypatch):
    _, before, _ = e2e.run(world)
    _switches(monkeypatch, aviasales="live")
    _, meta, _ = e2e.run(world)

    options = meta["flight_strategies"]["strategies"]
    assert options and all(o.get("aviasales_url", "").startswith("https://tp.media/r?") for o in options)
    # The world's trip: Colombo → Delhi 2 Nov, home 7 Nov, two travellers.
    assert {_search(o["aviasales_url"]) for o in options} == {"CMB0211DEL07112"}
    # What installed builds read is untouched.
    was = {o["title"]: (o["booking_url"], o["provider_name"]) for o in before["flight_strategies"]["strategies"]}
    assert {o["title"]: (o["booking_url"], o["provider_name"]) for o in options} == was
    assert meta["provider_audit"]["aviasales"] == {
        "mode": "live", "options": len(options), "linked": len(options),
        "path": "CMB0211DEL07112", "plan_row": True,
    }


def test_live_sends_the_booking_plan_flight_row_to_aviasales_and_says_so(world, monkeypatch):
    _, before, _ = e2e.run(world)
    row_before = next(r for r in before["booking_plan"] if "google.com/travel/flights" in r["url"])
    _switches(monkeypatch, aviasales="live")
    _, meta, _ = e2e.run(world)

    row = next(r for r in meta["booking_plan"] if r["label"] == row_before["label"]
               and r["item"].startswith("Flights on Aviasales"))
    assert row["item"] == "Flights on Aviasales: CMB → DEL and back"
    assert _search(row["url"]) == "CMB0211DEL07112"
    # This world's traveller needs an e-visa, and that reason stays on the row.
    assert (row["label"], row["reason"]) == ("BOOK AFTER VISA", row_before["reason"])
    assert not [r for r in meta["booking_plan"] if "google.com/travel/flights" in r["url"]]


def test_shadow_records_the_search_and_changes_nothing(world, monkeypatch):
    _, before, _ = e2e.run(world)
    _switches(monkeypatch, aviasales="shadow")
    _, meta, _ = e2e.run(world)
    assert not [o for o in meta["flight_strategies"]["strategies"] if "aviasales_url" in o]
    assert meta["booking_plan"] == before["booking_plan"]
    assert meta["provider_audit"]["aviasales"]["path"] == "CMB0211DEL07112"
    assert "plan_row" not in meta["provider_audit"]["aviasales"]


def test_off_adds_nothing(world, monkeypatch):
    _, meta, _ = e2e.run(world)
    assert not [o for o in meta["flight_strategies"]["strategies"] if "aviasales_url" in o]
    assert "aviasales" not in meta.get("provider_audit", {})


# ── The Booking Plan row on its own ──────────────────────────────────────────

def _meta(reason):
    option = {
        "tier": "recommended", "title": "1 stop · 36h 10m", "is_live_price": True,
        "booking_url": "https://www.google.com/travel/flights?q=x",
    }
    meta = {"booking_plan": [
        {"label": "BOOK NOW", "item": "1 stop · 36h 10m", "reason": reason,
         "url": "https://www.google.com/travel/flights?q=x"},
        {"label": "BOOK NOW", "item": "Hotel Villa Real", "reason": "", "url": "https://villareal.es"},
    ]}
    return meta, option


def test_a_live_fare_row_says_aviasales_shows_its_own_price():
    meta, option = _meta("Confirmed live fare — prices move, lock it in early.")
    legs = [("CMB", "MAD", "2026-10-11"), ("BCN", "CMB", "2026-10-17")]
    assert enrich._point_flight_row(meta, [(option, legs, "https://tp.media/r?a")]) is True
    assert meta["booking_plan"][0] == {
        "label": "BOOK NOW", "item": "Flights on Aviasales: CMB → MAD, BCN → CMB",
        "reason": "Fares move, so book early. Aviasales shows its live price for these flights.",
        "url": "https://tp.media/r?a",
    }
    assert meta["booking_plan"][1]["url"] == "https://villareal.es"


def test_an_estimated_fare_row_no_longer_claims_a_confirmed_fare():
    meta, option = _meta("Confirmed live fare — prices move, lock it in early.")
    option["is_live_price"] = False
    enrich._point_flight_row(meta, [(option, [("CMB", "AKL", "2026-10-11")], "https://tp.media/r?a")])
    assert meta["booking_plan"][0]["reason"] == "The fare in this plan is an estimate. Aviasales shows the live price."


def test_the_row_is_found_whichever_option_it_was_written_from():
    """Older estimated plans wrote it from the first option, not the Recommended."""
    meta = {"booking_plan": [{"label": "BOOK NOW", "item": "Cheapest Budget Carrier",
                              "reason": "", "url": "https://www.google.com/travel/flights?q=x"}]}
    options = [
        ({"tier": "recommended", "title": "Best Value Direct Flight",
          "booking_url": "https://www.google.com/travel/flights?q=x"}, [("CMB", "KUL", "")], "https://tp.media/r?a"),
        ({"tier": "minimum", "title": "Cheapest Budget Carrier",
          "booking_url": "https://www.google.com/travel/flights?q=x"}, [("CMB", "KUL", "")], "https://tp.media/r?b"),
    ]
    assert enrich._point_flight_row(meta, options) is True
    assert meta["booking_plan"][0]["url"] == "https://tp.media/r?b"


def test_a_visa_reason_on_the_row_is_kept():
    meta, option = _meta("Get your e-Visa first.")
    enrich._point_flight_row(meta, [(option, [("CMB", "AKL", "2026-10-11")], "https://tp.media/r?a")])
    assert meta["booking_plan"][0]["reason"] == "Get your e-Visa first."
    assert meta["booking_plan"][0]["url"] == "https://tp.media/r?a"
