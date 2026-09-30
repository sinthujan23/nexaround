"""Klook: "Things to do in <city>" where WeGoTrip sells nothing (user, 2026-09-29).

What these pin:
- the link is Klook's search for the city, credited to us the way
  Travelpayouts' Links API credits Klook (campaign 137, promo 4110);
- only cities where WeGoTrip put nothing on a stop get a row, at most five,
  longest stay first, as Booking Plan rows (the one place every app build
  opens a link). Selling something in the city is not enough: Oslo, Bergen
  and Mumbai have only general audio walks and got neither partner;
- shadow records and changes nothing; off asks nothing.
"""
import copy
import time
import urllib.parse

import pytest

from app.services.providers import config, enrich, klook

import test_odyssey_end_to_end as e2e
from test_odyssey_end_to_end import world  # noqa: F401  (fixture)
from test_wegotrip_tickets import _TAJ, _with_sights


def test_the_link_is_klooks_search_credited_to_us():
    assert klook.booking_link("Colombo", marker="781739", project_id="577812") == (
        "https://tp.media/r?campaign_id=137&marker=781739&p=4110&trs=577812"
        "&u=https%3A%2F%2Fwww.klook.com%2Fsearch%2Fresult%2F%3Fquery%3DColombo"
    )


def test_a_city_name_with_spaces_and_accents_survives_the_link():
    link = klook.booking_link("Nuwara Eliya", marker="781739", project_id="577812")
    page = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)["u"][0]
    assert urllib.parse.parse_qs(urllib.parse.urlparse(page).query)["query"] == ["Nuwara Eliya"]
    assert klook.search_url("Malé") == "https://www.klook.com/search/result/?query=Mal%C3%A9"


def test_without_both_ids_the_search_still_opens():
    assert klook.booking_link("Kandy", marker="781739", project_id="") == (
        "https://www.klook.com/search/result/?query=Kandy"
    )


def test_klook_links_are_recognised_and_others_are_not():
    assert klook.is_klook_link(klook.booking_link("Kandy", marker="1", project_id="2"))
    assert klook.is_klook_link("https://www.klook.com/en-US/city/527-male-things-to-do/")
    assert not klook.is_klook_link("https://tp.media/r?campaign_id=150&marker=1&p=4487&u=x")  # WeGoTrip
    assert not klook.is_klook_link("https://www.google.com/travel/hotels")


_LEGS = [
    {"city": "Colombo", "start_day": 1, "end_day": 1},
    {"city": "Kandy", "start_day": 2, "end_day": 4},
    {"city": "Ella", "start_day": 5, "end_day": 6},
    {"city": "Galle", "start_day": 7, "end_day": 7},
    {"city": "Colombo", "start_day": 8, "end_day": 9},
]


def test_cities_are_linked_once_longest_stay_first():
    # Colombo: 1 + 2 nights across two legs; Kandy 3; Ella 2; Galle 1.
    assert klook.cities_to_link(_LEGS, covered=set()) == ["Colombo", "Kandy", "Ella", "Galle"]


def test_every_city_of_the_south_india_plan_gets_its_row_up_to_five():
    """Plan 7a7939d1 (2026-09-29): five cities; three rows lost Mangaluru."""
    legs = [{"city": c, "start_day": s, "end_day": e} for c, s, e in (
        ("Chennai", 1, 3), ("Mysuru", 4, 6), ("Kochi", 7, 9), ("Mangaluru", 10, 11), ("Mumbai", 12, 14))]
    assert klook.cities_to_link(legs, covered=set()) == ["Chennai", "Mysuru", "Kochi", "Mumbai", "Mangaluru"]
    six = legs + [{"city": "Goa", "start_day": 15, "end_day": 15}]
    assert klook.cities_to_link(six, covered=set()) == ["Chennai", "Mysuru", "Kochi", "Mumbai", "Mangaluru"]


def test_cities_wegotrip_sells_in_are_left_to_wegotrip():
    legs = [{"city": "Agra", "start_day": 1, "end_day": 2}, {"city": "Kochi", "start_day": 3, "end_day": 5}]
    assert klook.cities_to_link(legs, covered={"Agra"}) == ["Kochi"]
    assert klook.cities_to_link(legs, covered={"Agra", "Kochi"}) == []


def test_the_row_names_klook_and_opens_like_the_others():
    row = klook.plan_item("Colombo", "https://tp.media/r?x")
    assert row == {
        "label": "BOOK CLOSER TO TRAVEL",
        "item": "Things to do in Colombo on Klook",
        "reason": "Tours, day trips and tickets. Book the popular ones a few days ahead.",
        "url": "https://tp.media/r?x",
    }
    # A row in a group the app already orders (odyssey_plan_view.dart labelOrder).
    assert row["label"] in ("BOOK NOW", "BOOK AFTER VISA", "BOOK CLOSER TO TRAVEL", "CAN WAIT")
    # Not a first word another provider replaces rows by.
    assert row["item"].split()[0] not in ("WeGoTrip", "Airalo", "GetTransfer", "Flights")


# ── Applied to a plan ────────────────────────────────────────────────────────

def _pending(mode="live"):
    return enrich.Pending(modes={"klook": mode}, legs=_LEGS, country="Sri Lanka")


def test_live_adds_one_row_per_uncovered_city_and_keeps_the_rest():
    meta = {"booking_plan": [{"label": "BOOK NOW", "item": "Hotel", "reason": "", "url": "https://h"}]}
    entry = enrich._apply_klook(meta, _pending(), covered={"Kandy"}, live=True, marker="781739", project_id="577812")
    items = [r["item"] for r in meta["booking_plan"]]
    assert items == ["Hotel", "Things to do in Colombo on Klook", "Things to do in Ella on Klook",
                     "Things to do in Galle on Klook"]
    assert entry == {"mode": "live", "cities": ["Colombo", "Ella", "Galle"], "rows": 3}


def test_a_second_pass_replaces_its_rows():
    meta = {"booking_plan": []}
    for _ in range(2):
        enrich._apply_klook(meta, _pending(), covered=set(), live=True, marker="781739", project_id="577812")
    assert len(meta["booking_plan"]) == 4


def test_shadow_records_the_links_and_changes_nothing():
    meta = {"booking_plan": []}
    entry = enrich._apply_klook(meta, _pending("shadow"), covered=set(), live=False, marker="781739", project_id="577812")
    assert meta == {"booking_plan": []}
    assert entry["mode"] == "shadow" and list(entry["links"]) == ["Colombo", "Kandy", "Ella", "Galle"]


# ── End to end through generate_odyssey ──────────────────────────────────────

def _switches(monkeypatch, **modes):
    values = {config.mode_key(p): m for p, m in modes.items()}
    values.update({config.TRAVELPAYOUTS_MARKER: "781739", config.TRAVELPAYOUTS_PROJECT_ID: "577812"})
    monkeypatch.setattr(config, "_config", values)
    monkeypatch.setattr(config, "_config_at", time.time())


@pytest.fixture
def one_rate(monkeypatch):
    async def _rate(code):
        return 1.0
    monkeypatch.setattr(enrich, "usd_rate", _rate)


def _wegotrip_sells(monkeypatch, catalogue):
    async def _catalogue(cities, country):
        return copy.deepcopy(catalogue)
    monkeypatch.setattr(enrich.wegotrip, "catalogue_for", _catalogue)


def _klook_rows(meta):
    return [r["item"] for r in meta["booking_plan"] if r["item"].endswith("on Klook")]


def test_a_city_wegotrip_put_a_ticket_on_is_left_to_it(world, monkeypatch, one_rate):
    # The e2e world: Delhi days 1-3, Agra days 4-6, with the Taj Mahal on day 4.
    _wegotrip_sells(monkeypatch, {"Agra": [_TAJ], "Delhi": []})
    _with_sights(monkeypatch)
    _switches(monkeypatch, klook="live", wegotrip="live")
    _, meta, _ = e2e.run(world)
    assert _klook_rows(meta) == ["Things to do in Delhi on Klook"]
    row = next(r for r in meta["booking_plan"] if r["item"].endswith("on Klook"))
    assert row["url"].startswith("https://tp.media/r?campaign_id=137&marker=781739&p=4110")
    assert meta["provider_audit"]["klook"]["cities"] == ["Delhi"]


def test_selling_something_that_fits_no_stop_does_not_count(world, monkeypatch, one_rate):
    """Oslo, Bergen and Mumbai: only general audio walks, no stop matched."""
    walk = {**_TAJ, "id": 5, "title": "Agra: Self-Guided Audio Walk Through the Old Bazaars"}
    _wegotrip_sells(monkeypatch, {"Agra": [walk], "Delhi": []})
    _with_sights(monkeypatch)
    _switches(monkeypatch, klook="live", wegotrip="live")
    _, meta, _ = e2e.run(world)
    assert meta["provider_audit"]["wegotrip"]["matched"] == []
    assert _klook_rows(meta) == ["Things to do in Delhi on Klook", "Things to do in Agra on Klook"]


def test_wegotrip_in_shadow_leaves_every_city_to_klook(world, monkeypatch, one_rate):
    _wegotrip_sells(monkeypatch, {"Agra": [_TAJ], "Delhi": []})
    _with_sights(monkeypatch)
    _switches(monkeypatch, klook="live", wegotrip="shadow")
    _, meta, _ = e2e.run(world)
    assert len(meta["provider_audit"]["wegotrip"]["matched"]) == 1, "shadow matched it but shows nothing"
    assert _klook_rows(meta) == ["Things to do in Delhi on Klook", "Things to do in Agra on Klook"]


def test_with_wegotrip_off_every_city_gets_its_row(world, monkeypatch):
    _switches(monkeypatch, klook="live")
    _, meta, _ = e2e.run(world)
    assert [r["item"] for r in meta["booking_plan"] if r["item"].endswith("on Klook")] == [
        "Things to do in Delhi on Klook", "Things to do in Agra on Klook",
    ]


def test_off_adds_nothing(world):
    _, meta, _ = e2e.run(world)
    assert not [r for r in meta.get("booking_plan") or [] if r["item"].endswith("on Klook")]
    assert "klook" not in meta.get("provider_audit", {})
